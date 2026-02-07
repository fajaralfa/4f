const std = @import("std");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const asttype = @import("ast.zig");

pub const SemanticError = error{
    WrongOperand,
};

pub const SemanticAnalyzer = struct {
    labels: std.StringHashMap(usize),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) SemanticAnalyzer {
        return SemanticAnalyzer{
            .allocator = allocator,
            .labels = std.StringHashMap(usize).init(allocator),
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
            .label => |l| {
                try self.visitLabel(l, index);
            },
            .instruction => |instr| {
                try self.visitInstruction(instr, index);
            },
        }
    }

    fn visitLabel(self: *SemanticAnalyzer, label: asttype.Label, index: usize) !void {
        try self.labels.put(label.name, index);
    }

    fn visitInstruction(self: *SemanticAnalyzer, instr: asttype.Instruction, index: usize) !void {
        _ = self;
        _ = instr;
        _ = index;
    }
};

test "init semantic analyzer" {
    const allocator = std.testing.allocator;
    var program = try asttype.Program.initCapacity(allocator, 1);
    try program.append(allocator, asttype.Block{ .label = .{ .name = "start" } });
    try program.append(allocator, asttype.Block{ .instruction = .{ .opcode = .Addi, .operand = std.ArrayList(asttype.Operand).empty } });
    var sema = SemanticAnalyzer.init(allocator);
    defer program.deinit(allocator);
    defer sema.deinit();
    try sema.analyze(program);
}
