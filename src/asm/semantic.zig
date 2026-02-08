const std = @import("std");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const asttype = @import("ast.zig");

pub const SemanticError = error{
    WrongOperand,
    InvalidInstruction,
};

const INSTR_LEN = 32;

pub const SemanticAnalyzer = struct {
    labels: std.StringHashMap(usize),
    allocator: std.mem.Allocator,
    opcode_specs: [INSTR_LEN]OperandSpec,
    program: asttype.Program,

    fn init(allocator: std.mem.Allocator, program: asttype.Program) SemanticAnalyzer {
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

        return SemanticAnalyzer{
            .allocator = allocator,
            .labels = std.StringHashMap(usize).init(allocator),
            .opcode_specs = opcode_specs,
            .program = program,
        };
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
        switch (block) {
            .label => |l| {
                try self.visitLabel(l, index);
            },
            .instruction => |instr| {
                try self.visitInstruction(instr);
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
        // _ = instr;
        instr.opcode = .And;
        // const items = instr.operand.items;
        // const x1: asttype.Register = getOperand(.register, items[0]);
        // const x2: asttype.Register = getOperand(.register, items[1]);
        // const imm: asttype.Immediate = getOperand(.immediate, items[2]);
    }
};

fn OperandType(comptime kind: asttype.OperandKind) type {
    return switch (kind) {
        .register => asttype.Register,
        .immediate => asttype.Immediate,
        .label => asttype.Label,
    };
}

fn getOperand(
    comptime kind: asttype.OperandKind,
    op: asttype.Operand,
) OperandType(kind) {
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
    try operand.append(allocator, .{ .immediate = 10 });
    const instruction = asttype.Instruction{ .opcode = .Lw, .operand = operand };
    try program.append(allocator, asttype.Block{ .instruction = instruction });

    var sema = SemanticAnalyzer.init(allocator, program);
    defer sema.deinit();
    try sema.analyze();
    std.debug.print("program: {}\n", .{program});
}
