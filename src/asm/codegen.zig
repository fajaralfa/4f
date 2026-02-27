const std = @import("std");
const ast = @import("ast.zig");
const builder = @import("builder.zig");

const Codegen = struct {
    allocator: std.mem.Allocator,
    program: ast.Program,

    pub fn init(allocator: std.mem.Allocator, program: ast.Program) Codegen {
        return Codegen{
            .allocator = allocator,
            .program = program,
        };
    }

    pub fn deinit(self: *Codegen) void {
        _ = self;
    }

    pub fn gen(self: *Codegen) !std.ArrayList(u16) {
        var result = std.ArrayList(u16).empty;
        for (self.program.items) |p| {
            try result.append(self.allocator, visitBlock(p));
        }
        return result;
    }

    pub fn visitBlock(block: ast.Block) u16 {
        switch (block) {
            .instruction => |instr| {
                return visitInstruction(instr);
            },
            .label => |_| {
                return 1 + 1;
            },
        }
    }

    pub fn visitInstruction(instr: ast.Instruction) u16 {
        const instructionBit: u16 = switch (instr.opcode) {
            .Invalid => 0x00,
            .Lw => lw(instr),
            .Sw => 0x02,
            .Lui => 0x03,
            .Addi => 0x04,
            .Add => 0x05,
            .Sub => 0x06,
            .And => 0x07,
            .Not => 0x08,
            .Or => 0x09,
            .Xor => 0x0a,
            .Sll => 0x0b,
            .Srl => 0x0c,
            .Sra => 0x0d,
            .Jr => 0x0e,
            .Beq => 0x0f,
            .Bne => 0x10,
            .Halt => 0x1f,
        };

        return instructionBit;
    }

    pub fn lw(instr: ast.Instruction) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const r2 = getReg(operands[1]);
        const imm = try getImmU5(operands[2]);
        const instrBit = builder.lw(r1, r2, imm);
        return instrBit;
    }
};

pub fn getReg(operand: ast.Operand) u3 {
    return switch (operand) {
        .register => |r| getRegBit(r),
        else => unreachable,
    };
}

pub fn getRegBit(r: ast.Register) u3 {
    return switch (r) {
        .PC => 0x00,
        .SP => 0x01,
        .X1 => 0x02,
        .X2 => 0x03,
        .X3 => 0x04,
        .MEPC => 0x05,
        .MCAUSE => 0x06,
        .MTVEC => 0x07,
    };
}

pub fn getImmU8(operand: ast.Operand) u8 {
    return switch (operand) {
        .immediate => |r| r,
        else => unreachable,
    };
}

pub fn getImmU5(operand: ast.Operand) !u5 {
    return switch (operand) {
        .immediate => |r| @intCast(r),
        else => unreachable,
    };
}

test "init codegen" {
    const allocator = std.testing.allocator;
    var program = try ast.Program.initCapacity(allocator, 3);
    defer program.deinit(allocator);
    var codegen = Codegen.init(allocator, program);
    defer codegen.deinit();
}

test "emit instruction" {
    const allocator = std.testing.allocator;

    var program = try ast.Program.initCapacity(allocator, 1);
    defer program.deinit(allocator);

    var operands = try std.ArrayList(ast.Operand).initCapacity(allocator, 3);
    defer operands.deinit(allocator);
    try operands.append(allocator, .{ .register = .X1 });
    try operands.append(allocator, .{ .register = .X2 });
    try operands.append(allocator, .{ .immediate = 10 });

    try program.append(allocator, ast.Block{
        .instruction = .{ .opcode = .Lw, .operand = operands },
    });

    var codegen = Codegen.init(allocator, program);
    defer codegen.deinit();

    var result = try codegen.gen();
    defer result.deinit(allocator);
    for (result.items) |i| {
        std.debug.print("{b}\n", .{i});
    }
}
