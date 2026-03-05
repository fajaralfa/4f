const std = @import("std");
const ast = @import("ast.zig");
const builder = @import("builder.zig");

pub const Codegen = struct {
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

    pub fn gen(self: *Codegen) !std.ArrayList(u8) {
        var result = std.ArrayList(u8).empty;
        for (self.program.items) |p| {
            const instructionBits = visitBlock(p);
            const lo: u8 = @intCast(instructionBits & std.math.maxInt(u8));
            const hi: u8 = @intCast((instructionBits >> 8) & std.math.maxInt(u8));
            try result.append(self.allocator, lo);
            try result.append(self.allocator, hi);
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
            .Lw => OpR2Imm5(instr, builder.lw),
            .Sw => OpR2Imm5(instr, builder.sw),
            .Lui => OpR1ImmU8(instr, builder.lui),
            .Addi => OpR2Imm5(instr, builder.addi),
            .Add => OpR3(instr, builder.add),
            .Sub => OpR3(instr, builder.sub),
            .And => OpR3(instr, builder.andInstr),
            .Not => OpR2(instr, builder.notInstr),
            .Or => OpR3(instr, builder.orInstr),
            .Xor => OpR3(instr, builder.xorInstr),
            .Sll => OpR3(instr, builder.sll),
            .Srl => OpR3(instr, builder.srl),
            .Sra => OpR3(instr, builder.sra),
            .Jr => OpR1(instr, builder.jr),
            .Beq => OpR3(instr, builder.beq),
            .Bne => OpR3(instr, builder.bne),
            .Halt => builder.halt(),
        };

        return instructionBit;
    }

    pub fn OpNo(builderFn: fn () u16) u16 {
        return builderFn();
    }

    pub fn OpR1(instr: ast.Instruction, builderFn: fn (u3) u16) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const instrBit = builderFn(r1);
        return instrBit;
    }

    pub fn OpR2(instr: ast.Instruction, builderFn: fn (u3, u3) u16) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const r2 = getReg(operands[1]);
        const instrBit = builderFn(r1, r2);
        return instrBit;
    }

    pub fn OpR3(instr: ast.Instruction, builderFn: fn (u3, u3, u3) u16) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const r2 = getReg(operands[1]);
        const r3 = getReg(operands[2]);
        const instrBit = builderFn(r1, r2, r3);
        return instrBit;
    }

    pub fn OpR2Imm5(instr: ast.Instruction, builderFn: fn (u3, u3, u5) u16) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const r2 = getReg(operands[1]);
        const imm = try getImmU5(operands[2]);
        const instrBit = builderFn(r1, r2, imm);
        return instrBit;
    }

    pub fn OpR1ImmU8(instr: ast.Instruction, builderFn: fn (u3, u8) u16) u16 {
        const operands = instr.operand.items;
        const r1 = getReg(operands[0]);
        const imm = getImmU8(operands[1]);
        const instrBit = builderFn(r1, imm);
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
