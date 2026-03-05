const std = @import("std");
const assembler = @import("asm/builder.zig");
const mmiomod = @import("mmio.zig");

pub const CPUError = error{
    OutOfBounds,
    InvalidInstruction,
    MemoryTooLarge,
    MisalignedMemory,
    InvalidAddress,
};

pub const MMIODevice = struct {
    base: u16,
    size: u16,
    ctx: *anyopaque,

    read: *const fn (ctx: *anyopaque, addr: u16) CPUError!u16,
    write: *const fn (ctx: *anyopaque, addr: u16, value: u16) CPUError!void,
};

pub const register_count = 8;
pub const max_memory: u32 = 1 << 16;

pub const CPU = struct {
    running: bool,
    register: [register_count]u16,
    memory: []u8,
    start_prog: u16, // must be 16 bit aligned
    handler: [32]*const fn (*CPU, u16) CPUError!void,
    mmio: std.ArrayList(MMIODevice) = std.ArrayList(MMIODevice).empty,

    pub fn init(memory: []u8) CPUError!CPU {
        if (memory.len > max_memory) {
            return CPUError.MemoryTooLarge;
        }

        var cpu = CPU{
            .register = .{0} ** register_count,
            .running = false,
            .memory = memory,
            .start_prog = @intCast(memory.len / 2),
            .handler = .{invalid} ** 32,
        };
        cpu.handler[0x1F] = halt;
        cpu.handler[0x1] = lw;
        cpu.handler[0x2] = sw;
        cpu.handler[0x3] = lui;
        cpu.handler[0x4] = addi;
        cpu.handler[0x5] = add;
        cpu.handler[0x6] = sub;
        cpu.handler[0x7] = andInstr;
        cpu.handler[0x8] = notInstr;
        cpu.handler[0x9] = orInstr;
        cpu.handler[0xa] = xorInstr;
        cpu.handler[0xb] = sll;
        cpu.handler[0xc] = srl;
        cpu.handler[0xd] = sra;
        cpu.handler[0xe] = jr;
        cpu.handler[0xf] = beq;
        cpu.handler[0x10] = bne;
        return cpu;
    }

    pub fn loadProgram(self: *CPU, program: []const u8) CPUError!void {
        if (program.len > (max_memory - self.start_prog)) {
            return CPUError.OutOfBounds;
        }
        for (program, self.start_prog..) |byte, addr| {
            self.memory[addr] = byte;
        }
    }

    pub fn runProgram(self: *CPU) !void {
        self.running = true;
        self.register[0] = self.start_prog; // program counter init
        self.register[1] = self.start_prog - 2; // stack pointer init (aligned)
        const allocator = std.heap.page_allocator;
        while (self.running) {
            var result = std.ArrayList(u8).empty;
            defer result.deinit(allocator);

            for (self.register, 0..) |r, i| {
                const info = try std.fmt.allocPrint(allocator, "R{d}: {x:4}  |", .{ i, r });
                try result.appendSlice(allocator, info);
            }

            std.log.debug("{s}\n", .{result.items});

            const instr = try self.fetchInstr();
            try self.execInstr(instr);
        }
    }

    fn fetchInstr(self: *CPU) CPUError!u16 {
        const addr = self.register[0];

        if (addr + 1 >= self.memory.len) {
            return CPUError.OutOfBounds;
        }

        const lo = self.memory[addr];
        const hi = self.memory[addr + 1];
        self.register[0] += 2;

        return (@as(u16, hi) << 8) | lo;
    }

    fn execInstr(self: *CPU, instr: u16) CPUError!void {
        const opcode = (instr >> 11);
        std.log.debug("op {x} instr {b:13}", .{ opcode, instr & std.math.maxInt(u13) });
        const handler = self.handler[opcode];
        try handler(self, instr);
    }

    pub fn addMMIO(self: *CPU, allocator: std.mem.Allocator, device: MMIODevice) !void {
        try self.mmio.append(allocator, device);
    }

    pub fn deinitMMIO(self: *CPU, allocator: std.mem.Allocator) void {
        self.mmio.deinit(allocator);
    }

    fn findMMIO(self: *CPU, addr: u16) ?*const MMIODevice {
        for (self.mmio.items) |*dev| {
            if (addr >= dev.base and addr < dev.base + dev.size)
                return dev;
        }
        return null;
    }

    fn load16(self: *CPU, addr: u16) CPUError!u16 {
        if (self.findMMIO(addr)) |dev| {
            return dev.read(dev.ctx, addr - dev.base);
        }

        const i = @as(usize, addr);
        return (@as(u16, self.memory[i + 1]) << 8) | self.memory[i];
    }

    fn store16(self: *CPU, addr: u16, value: u16) CPUError!void {
        if (self.findMMIO(addr)) |dev| {
            return dev.write(dev.ctx, addr - dev.base, value);
        }

        const i = @as(usize, addr);
        self.memory[i] = @intCast(value & 0xff);
        self.memory[i + 1] = @intCast(value >> 8);
    }

    fn invalid(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("invalid instruction", .{});
        _ = self;
        _ = instr;
        return CPUError.InvalidInstruction;
    }

    fn halt(self: *CPU, _: u16) CPUError!void {
        std.log.debug("halt", .{});
        self.running = false;
    }

    fn lw(self: *CPU, instr: u16) CPUError!void {
        const dest: u3 = @intCast((instr >> 8) & std.math.maxInt(u3));
        const base: u3 = @intCast((instr >> 5) & std.math.maxInt(u3));
        const offset: u5 = @intCast(instr & std.math.maxInt(u5));
        const offsetScaled: i16 = @as(i5, @bitCast(offset)) * 2;
        const addr = @as(u16, @bitCast(@as(i16, @bitCast(self.register[base])) + offsetScaled));
        if (addr % 2 != 0) {
            return CPUError.MisalignedMemory;
        }
        if (addr + 1 > self.memory.len) {
            return CPUError.OutOfBounds;
        }
        self.register[dest] = try self.load16(addr);
    }

    fn sw(self: *CPU, instr: u16) CPUError!void {
        const src: u3 = @intCast((instr >> 8) & std.math.maxInt(u3));
        const base: u3 = @intCast((instr >> 5) & std.math.maxInt(u3));
        const offset: u5 = @intCast(instr & std.math.maxInt(u5));
        const offsetScaled: i16 = @as(i5, @bitCast(offset)) * 2;
        const addr = @as(u16, @bitCast(@as(i16, @bitCast(self.register[base])) + offsetScaled));
        if (addr % 2 != 0) {
            return CPUError.MisalignedMemory;
        }
        if (addr > self.memory.len - 2) {
            return CPUError.OutOfBounds;
        }
        try self.store16(addr, self.register[src]);
    }

    fn lui(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("lui", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const imm: u16 = @intCast(instr & 0xFF); // casting this to u8 throws:
        self.register[dest] = imm << 8; // type 'u3' cannot represent integer value '8'
    }

    fn addi(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("addi", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const imm: u5 = @intCast((instr) & ((1 << 5) - 1));
        self.register[dest] = self.register[src] +% imm; // wrap around
    }

    fn add(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("add", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] +% self.register[src2]; // wrap around
    }

    fn sub(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("sub", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] -% self.register[src2]; // wrap around
    }

    fn andInstr(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("and", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] & self.register[src2];
    }

    fn notInstr(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("not", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        self.register[dest] = ~self.register[src];
    }

    fn orInstr(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("or", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] | self.register[src2];
    }

    fn xorInstr(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("or", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] ^ self.register[src2];
    }

    fn sll(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("sll", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] << @truncate(self.register[src2]);
    }

    fn srl(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("srl", .{});
        const dest: u3 = @intCast((instr >> 8) & ((1 << 3) - 1));
        const src1: u3 = @intCast((instr >> 5) & ((1 << 3) - 1));
        const src2: u3 = @intCast((instr >> 2) & ((1 << 3) - 1));
        self.register[dest] = self.register[src1] >> @truncate(self.register[src2]);
    }

    fn sra(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("sra", .{});
        const dest: u3 = @intCast((instr >> 8) & 7);
        const src1: u3 = @intCast((instr >> 5) & 7);
        const src2: u3 = @intCast((instr >> 2) & 7);

        // Treat u16 as two's complement signed value
        const value = @as(i16, @bitCast(self.register[src1]));
        const shift_amt: u4 = @truncate(self.register[src2]);

        // Perform arithmetic right shift
        const result = @as(u16, @bitCast(value >> shift_amt));
        self.register[dest] = result;
    }

    fn jr(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("jr", .{});
        const dest: u3 = @intCast((instr >> 8) & 7);
        const offset = @as(i16, @bitCast(self.register[dest])) * 2;
        self.register[0] = @as(u16, @bitCast(@as(i16, @bitCast(self.register[0])) + offset));
    }

    fn beq(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("beq", .{});
        const dest: u3 = @intCast((instr >> 8) & 7);
        const src1: u3 = @intCast((instr >> 5) & 7);
        const src2: u3 = @intCast((instr >> 2) & 7);
        const jumpinstr: u16 = (@as(u16, dest) << 8);
        if (self.register[src1] == self.register[src2]) {
            try self.jr(jumpinstr);
        }
    }

    fn bne(self: *CPU, instr: u16) CPUError!void {
        std.log.debug("bne", .{});
        const dest: u3 = @intCast((instr >> 8) & 7);
        const src1: u3 = @intCast((instr >> 5) & 7);
        const src2: u3 = @intCast((instr >> 2) & 7);
        const jumpinstr: u16 = (@as(u16, dest) << 8);
        if (self.register[src1] != self.register[src2]) {
            try self.jr(jumpinstr);
        }
    }
};

test "load program" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    const program = [_]u8{ 2, 2, 31 };
    try cpu.loadProgram(&program);
    try std.testing.expect(cpu.memory[cpu.start_prog] == program[0]);
    try std.testing.expect(cpu.memory[cpu.start_prog + 1] == program[1]);
    try std.testing.expect(cpu.memory[cpu.start_prog + 2] == program[2]);
}

test "load program out of bound" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    const start_addr: usize = max_memory / 2;
    const program = [_]u8{3} ** (start_addr + 1);
    try std.testing.expectError(CPUError.OutOfBounds, cpu.loadProgram(&program));
}

test "run program" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    const program_words = [_]u16{
        assembler.lui(1, 0xFF),
        assembler.addi(1, 1, 0x1F),
        assembler.halt(),
    };
    var buffer: [program_words.len * 2]u8 = undefined;
    var program = try assembler.assemble(buffer[0..], program_words[0..]);
    try cpu.loadProgram(program[0..]);
    try cpu.runProgram();
    try std.testing.expect(true);
}

test "lw" {
    var mem = [_]u8{0} ** 32;
    var cpu = try CPU.init(&mem);
    cpu.memory[10] = 0x11;
    cpu.memory[11] = 0x23;
    cpu.register[2] = 10;

    // 0 offset
    try cpu.lw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(cpu.register[1] == 0x2311);

    // -2 offset
    cpu.register[2] = 14;
    try cpu.lw((1 << 8) | (2 << 5) | 0x1E);
    try std.testing.expect(cpu.register[1] == 0x2311);

    // 2 offset
    cpu.register[2] = 6;
    try cpu.lw((1 << 8) | (2 << 5) | 2);
    try std.testing.expect(cpu.register[1] == 0x2311);
}

test "lw OutOfBounds, Misaligned" {
    var mem = [_]u8{0} ** 32;
    var cpu = try CPU.init(&mem);
    cpu.register[2] = 128; // make alignment checking passes
    var result = cpu.lw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(result == CPUError.OutOfBounds);

    cpu.register[2] = 61;
    result = cpu.lw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(result == CPUError.MisalignedMemory);
}

test "sw" {
    var mem = [_]u8{0} ** 32;
    var cpu = try CPU.init(&mem);
    cpu.register[2] = 10;
    cpu.register[1] = 0x2311;
    // zero offset
    try cpu.sw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(cpu.memory[10] == 0x11);
    try std.testing.expect(cpu.memory[11] == 0x23);

    // positive offset (2)
    try cpu.sw((1 << 8) | (2 << 5) | 2);
    try std.testing.expect(cpu.memory[14] == 0x11);
    try std.testing.expect(cpu.memory[15] == 0x23);

    // negative offset (-2)
    try cpu.sw((1 << 8) | (2 << 5) | 0x1E);
    try std.testing.expect(cpu.memory[6] == 0x11);
    try std.testing.expect(cpu.memory[7] == 0x23);
}

test "sw OutOfBound, MisalignedMemory" {
    var mem = [_]u8{0} ** 32;
    var cpu = try CPU.init(&mem);

    // OutOfBound
    cpu.register[1] = 0x2311;
    cpu.register[2] = 34;
    var result = cpu.sw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(result == CPUError.OutOfBounds);

    // Misaligned
    cpu.register[1] = 0x2311;
    cpu.register[2] = 31;
    result = cpu.sw((1 << 8) | (2 << 5) | 0);
    try std.testing.expect(result == CPUError.MisalignedMemory);
}

test "lui" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    try cpu.lui((1 << 8) | 0xFF);

    try std.testing.expect(cpu.register[1] == 0xFF00);
}

test "addi" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0xFF00;

    // just so you know
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x1F));
    try cpu.addi((1 << 8) | (1 << 5) | (0x7));

    try std.testing.expect(cpu.register[1] == 0xFFFF);
}

test "addi wraparound" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0xFFF2;
    try cpu.addi((1 << 8) | (1 << 5) | (0x0F));
    try std.testing.expect(cpu.register[1] == 1);
}

test "add" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 10;
    cpu.register[2] = 20;

    try cpu.add((1 << 8) | (1 << 5) | (2 << 2));

    try std.testing.expect(cpu.register[1] == 30);
}

test "add wraparound" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0xFFF2;
    cpu.register[2] = 0xF;
    try cpu.add((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 1);
}

test "sub" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 32;
    cpu.register[2] = 12;

    try cpu.sub((1 << 8) | (1 << 5) | (2 << 2));

    try std.testing.expect(cpu.register[1] == 20);
}

test "sub wraparound" {
    var mem = [_]u8{0} ** max_memory;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 10;
    cpu.register[2] = 20;
    try cpu.sub((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0xFFF6);
}

test "and" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1100;
    cpu.register[2] = 0b1011;
    try cpu.andInstr((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0b1000);
}

test "not" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1011;
    try cpu.notInstr((1 << 8) | (1 << 5));
    const result = cpu.register[1] & std.math.maxInt(u4); // only compare last 4 bit
    try std.testing.expect(result == 0b0100);
}

test "or" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1100;
    cpu.register[2] = 0b1011;
    try cpu.orInstr((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0b1111);
}

test "xor" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1100;
    cpu.register[2] = 0b1011;
    try cpu.xorInstr((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0b0111);
}

test "sll" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = @as(u16, 0b0001);
    cpu.register[2] = 2;
    try cpu.sll((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == @as(u16, 0b0100));
}

test "srl" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1000;
    cpu.register[2] = 2;
    try cpu.srl((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0b0010);
}

test "sra" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    cpu.register[1] = 0b1111111111111100; // -4 as i16
    cpu.register[2] = 2;
    try cpu.sra((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 0b1111111111111111); // -1

    cpu.register[1] = 0b100; // 4 as unsigned bit pattern (same bit representation in i16 and u16 for positive values within range)
    cpu.register[2] = 2;
    try cpu.sra((1 << 8) | (1 << 5) | (2 << 2));
    try std.testing.expect(cpu.register[1] == 1); // 1
}

test "jr adds register to PC" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    // PC starts at 100
    cpu.register[0] = 100;
    // jump register (say r3) contains +20
    cpu.register[3] = 20;
    // instr with dest = 3 in bits [10:8]
    const instr: u16 = (3 << 8);
    try cpu.jr(instr);
    try std.testing.expect(cpu.register[0] == 140);
}

test "jr backward" {
    var mem = [_]u8{0} ** 16;
    var cpu = try CPU.init(&mem);
    cpu.register[0] = 100;
    // -4 instructions = -8 bytes
    cpu.register[5] = @bitCast(@as(i16, -4));

    try cpu.jr((5 << 8));
    try std.testing.expect(cpu.register[0] == 92);
}

test "jr zero offset" {
    var mem = [_]u8{0} ** 16;
    var cpu = try CPU.init(&mem);
    cpu.register[0] = 50;
    cpu.register[1] = 0;

    try cpu.jr(1 << 8);

    try std.testing.expect(cpu.register[0] == 50);
}

test "beq" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    const pc = 20;
    cpu.register[0] = pc;
    cpu.register[1] = 4;
    cpu.register[2] = 25;
    cpu.register[3] = 25;

    // equal
    var instr: u16 = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.beq(instr);
    try std.testing.expectEqual(pc + 8, cpu.register[0]);

    // not equal
    cpu.register[0] = pc;
    cpu.register[3] = 24; // make it different
    instr = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.beq(instr);
    try std.testing.expectEqual(pc, cpu.register[0]);
}

test "beq backward" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    const pc = 20;
    cpu.register[0] = pc;
    cpu.register[1] = @bitCast(@as(i16, -4));
    cpu.register[2] = 25;
    cpu.register[3] = 25;

    // equal
    const instr: u16 = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.beq(instr);
    try std.testing.expectEqual(pc - 8, cpu.register[0]);
}

test "bne" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    const pc = 20;
    cpu.register[0] = pc;
    cpu.register[1] = 10;
    cpu.register[2] = 25;
    cpu.register[3] = 25;

    // equal
    var instr: u16 = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.bne(instr);
    try std.testing.expectEqual(pc, cpu.register[0]);

    // not equal
    cpu.register[0] = pc;
    cpu.register[3] = 24; // make it different
    instr = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.bne(instr);
    try std.testing.expectEqual(pc + 20, cpu.register[0]);
}

test "bne backward" {
    var mem = [_]u8{0} ** 10;
    var cpu = try CPU.init(&mem);
    const pc = 20;
    cpu.register[0] = pc;
    cpu.register[1] = @bitCast(@as(i16, -4));
    cpu.register[2] = 25;
    cpu.register[3] = 24;

    // equal
    const instr: u16 = (1 << 8) | (2 << 5) | (3 << 2);
    try cpu.bne(instr);
    try std.testing.expectEqual(pc - 8, cpu.register[0]);
}
