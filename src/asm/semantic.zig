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

    fn init(allocator: std.mem.Allocator) SemanticAnalyzer {
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
            .kinds = &.{ .Register, .Register, .Immediate },
            .instr_fn = lw,
        };

        return SemanticAnalyzer{
            .allocator = allocator,
            .labels = std.StringHashMap(usize).init(allocator),
            .opcode_specs = opcode_specs,
        };
    }

    fn deinit(self: *SemanticAnalyzer) void {
        self.labels.deinit();
    }

    fn analyze(self: *SemanticAnalyzer, program: asttype.Program) !void {
        for (program.items, 0..) |*block, i| {
            try self.visitBlock(block, i);
        }
    }

    fn visitBlock(self: *SemanticAnalyzer, block: *asttype.Block, index: usize) !void {
        switch (block.*) {
            .Label => |l| {
                try self.visitLabel(l, index);
            },
            .Instruction => |instr| {
                try self.visitInstruction(instr);
            },
        }
    }

    fn visitLabel(self: *SemanticAnalyzer, label: asttype.Label, index: usize) !void {
        try self.labels.put(label.name, index);
    }

    fn visitInstruction(self: *SemanticAnalyzer, instr: asttype.Instruction) !void {
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

        _ = try spec.instr_fn(self, instr);
    }

    fn invalid(_: *SemanticAnalyzer, _: asttype.Instruction) !u16 {
        return SemanticError.InvalidInstruction;
    }

    fn lw(self: *SemanticAnalyzer, instr: asttype.Instruction) !u16 {
        _ = self;
        std.debug.print("anjau {}\n", .{instr.opcode});
        return 10;
    }
};

const OperandSpec = struct {
    count: u8,
    kinds: []const asttype.OperandKind,
    instr_fn: *const fn (*SemanticAnalyzer, asttype.Instruction) anyerror!u16,
};

test "init semantic analyzer" {
    const allocator = std.testing.allocator;
    var program = try asttype.Program.initCapacity(allocator, 1);
    try program.append(allocator, asttype.Block{ .Label = .{ .name = "start" } });
    var operand = try std.ArrayList(asttype.Operand).initCapacity(allocator, 3);
    defer operand.deinit(allocator);
    try operand.append(allocator, .{ .Register = .X1 });
    try operand.append(allocator, .{ .Register = .X1 });
    try operand.append(allocator, .{ .Immediate = 10 });
    try program.append(allocator, asttype.Block{ .Instruction = .{ .opcode = .Lw, .operand = operand } });
    var sema = SemanticAnalyzer.init(allocator);
    defer program.deinit(allocator);
    defer sema.deinit();
    try sema.analyze(program);
}
