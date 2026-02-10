const std = @import("std");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const asttype = @import("ast.zig");

pub const SemanticError = error{
    WrongOperand,
    InvalidInstruction,
    ImmediateSizeExceeded,
};

const INSTR_LEN = 32;

pub const SemanticAnalyzer = struct {
    labels: std.StringHashMap(usize),
    allocator: std.mem.Allocator,
    opcode_specs: [INSTR_LEN]OperandSpec,
    program: asttype.Program,

    fn init(allocator: std.mem.Allocator, program: asttype.Program) SemanticAnalyzer {
        const opcode_specs: [INSTR_LEN]OperandSpec = getOpcodeSpec();

        return SemanticAnalyzer{
            .allocator = allocator,
            .labels = std.StringHashMap(usize).init(allocator),
            .opcode_specs = opcode_specs,
            .program = program,
        };
    }

    inline fn getOpcodeSpec() [INSTR_LEN]OperandSpec {
        var opcode_specs: [INSTR_LEN]OperandSpec = undefined;
        inline for (0..INSTR_LEN) |i| {
            opcode_specs[i] = .{
                .count = 0,
                .kinds = &.{},
                .instr_fn = invalid,
            };
        }

        opcode_specs[1] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .immediate },
            .instr_fn = lw,
        };

        opcode_specs[2] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .immediate },
            .instr_fn = sw,
        };

        opcode_specs[3] = .{
            .count = 2,
            .kinds = &.{ .register, .immediate },
            .instr_fn = lui,
        };

        opcode_specs[4] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .immediate },
            .instr_fn = addi,
        };

        opcode_specs[5] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = add,
        };

        opcode_specs[6] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = sub,
        };

        opcode_specs[7] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opAnd,
        };

        opcode_specs[8] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opNot,
        };

        opcode_specs[9] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opOr,
        };

        opcode_specs[10] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opXor,
        };

        opcode_specs[11] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opSll,
        };

        opcode_specs[12] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opSrl,
        };

        opcode_specs[13] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = opSra,
        };

        opcode_specs[14] = .{
            .count = 3,
            .kinds = &.{.register},
            .instr_fn = jr,
        };

        opcode_specs[15] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = beq,
        };

        opcode_specs[16] = .{
            .count = 3,
            .kinds = &.{ .register, .register, .register },
            .instr_fn = bne,
        };

        opcode_specs[0x1f] = .{
            .count = 3,
            .kinds = &.{},
            .instr_fn = halt,
        };

        return opcode_specs;
    }

    fn deinit(self: *SemanticAnalyzer) void {
        self.labels.deinit();
    }

    fn analyze(self: *SemanticAnalyzer) !void {
        for (self.program.items, 0..) |*block, i| {
            try self.visitBlock(block, i);
        }
    }

    fn visitBlock(self: *SemanticAnalyzer, block: *asttype.Block, index: usize) !void {
        switch (block.*) {
            .label => {
                try self.visitLabel(&block.label, index);
            },
            .instruction => {
                try self.visitInstruction(&block.instruction);
            },
        }
    }

    fn visitLabel(self: *SemanticAnalyzer, label: *asttype.Label, index: usize) !void {
        try self.labels.put(label.name, index);
    }

    fn visitInstruction(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        if (instr.opcode == .Invalid) {
            return SemanticError.InvalidInstruction;
        }

        const spec = self.opcode_specs[@intFromEnum(instr.opcode)];

        if (instr.operand.items.len != spec.count)
            return SemanticError.WrongOperand;

        for (spec.kinds, instr.operand.items) |expected, actual| {
            const actual_kind: asttype.OperandKind = actual;
            if (actual_kind != expected)
                return SemanticError.WrongOperand;
        }

        try spec.instr_fn(self, instr);
    }

    fn invalid(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {
        return SemanticError.InvalidInstruction;
    }

    fn noop(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}

    fn lw(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        _ = self;
        const items = instr.operand.items;
        const imm: asttype.Immediate = getOperand(.immediate, items[2]);
        if (imm > std.math.maxInt(u5)) {
            return SemanticError.ImmediateSizeExceeded;
        }
    }

    fn sw(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        _ = self;
        const items = instr.operand.items;
        const imm: asttype.Immediate = getOperand(.immediate, items[2]);
        if (imm > std.math.maxInt(u5)) {
            return SemanticError.ImmediateSizeExceeded;
        }
    }

    fn lui(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        _ = self;
        const items = instr.operand.items;
        const imm: asttype.Immediate = getOperand(.immediate, items[1]);
        if (imm > std.math.maxInt(u8)) {
            return SemanticError.ImmediateSizeExceeded;
        }
    }

    fn addi(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        _ = self;
        const items = instr.operand.items;
        const imm: asttype.Immediate = getOperand(.immediate, items[2]);
        if (imm > std.math.maxInt(u5)) {
            return SemanticError.ImmediateSizeExceeded;
        }
    }

    fn add(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn sub(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opAnd(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opNot(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opOr(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opXor(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opSll(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opSrl(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn opSra(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}

    fn jr(self: *SemanticAnalyzer, instr: *asttype.Instruction) !void {
        _ = self;
        _ = instr;
    }

    fn beq(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn bne(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
    fn halt(_: *SemanticAnalyzer, _: *asttype.Instruction) !void {}
};

fn OperandType(comptime kind: asttype.OperandKind) type {
    return switch (kind) {
        .register => asttype.Register,
        .immediate => asttype.Immediate,
        .label => asttype.Label,
    };
}

fn getOperand(comptime kind: asttype.OperandKind, op: asttype.Operand) OperandType(kind) {
    return switch (op) {
        kind => |v| v,
        else => unreachable,
    };
}

const OperandSpec = struct {
    count: u8,
    kinds: []const asttype.OperandKind,
    instr_fn: *const fn (*SemanticAnalyzer, *asttype.Instruction) anyerror!void,
};

fn createOperands(allocator: std.mem.Allocator, data: []asttype.Operand) !std.ArrayList(asttype.Operand) {
    var operands = std.ArrayList(asttype.Operand).empty;
    for (data) |d| {
        try operands.append(allocator, d);
    }
    return operands;
}

test "init semantic analyzer" {
    const allocator = std.testing.allocator;

    var program = try asttype.Program.initCapacity(allocator, 1);
    defer program.deinit(allocator);
    const label = asttype.Label{ .name = "start" };
    try program.append(allocator, asttype.Block{ .label = label });

    var operand = try std.ArrayList(asttype.Operand).initCapacity(allocator, 3);
    defer operand.deinit(allocator);
    try operand.append(allocator, .{ .register = .X1 });
    try operand.append(allocator, .{ .register = .X1 });
    try operand.append(allocator, .{ .immediate = 31 });
    try program.append(allocator, asttype.Block{ .instruction = asttype.Instruction{ .opcode = .Lw, .operand = operand } });

    var sema = SemanticAnalyzer.init(allocator, program);
    defer sema.deinit();
    try sema.analyze();
    for (program.items) |ins| {
        ins.print();
    }
}

test "lw" {
    const allocator = std.testing.allocator;

    var program = try asttype.Program.initCapacity(allocator, 1);
    defer program.deinit(allocator);

    var operandSource = [_]asttype.Operand{
        .{ .register = .X1 },
        .{ .register = .X1 },
        .{ .immediate = 31 },
    };
    var operands = try createOperands(allocator, operandSource[0..]);
    defer operands.deinit(allocator);
    try program.append(allocator, asttype.Block{
        .instruction = asttype.Instruction{
            .opcode = .Lw,
            .operand = operands,
        },
    });

    var sema = SemanticAnalyzer.init(allocator, program);
    defer sema.deinit();
    try sema.analyze();
    for (program.items) |ins| {
        ins.print();
    }
}

test "sw" {
    const allocator = std.testing.allocator;

    var program = try asttype.Program.initCapacity(allocator, 1);
    defer program.deinit(allocator);

    var operandSource = [_]asttype.Operand{
        .{ .register = .X1 },
        .{ .register = .X1 },
        .{ .immediate = 31 },
    };
    var operands = try createOperands(allocator, operandSource[0..]);
    defer operands.deinit(allocator);
    try program.append(allocator, asttype.Block{
        .instruction = asttype.Instruction{
            .opcode = .Sw,
            .operand = operands,
        },
    });

    var sema = SemanticAnalyzer.init(allocator, program);
    defer sema.deinit();
    try sema.analyze();
    for (program.items) |ins| {
        ins.print();
    }
}

test "lui" {
    const allocator = std.testing.allocator;

    var program = try asttype.Program.initCapacity(allocator, 1);
    defer program.deinit(allocator);

    var operandSource = [_]asttype.Operand{
        .{ .register = .X1 },
        .{ .immediate = 0xff },
    };
    var operands = try createOperands(allocator, operandSource[0..]);
    defer operands.deinit(allocator);
    try program.append(allocator, asttype.Block{
        .instruction = asttype.Instruction{
            .opcode = .Lui,
            .operand = operands,
        },
    });

    var sema = SemanticAnalyzer.init(allocator, program);
    defer sema.deinit();
    try sema.analyze();
    for (program.items) |ins| {
        ins.print();
    }
}
