const std = @import("std");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");

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

    fn analyze(self: *SemanticAnalyzer, program: parser.Program) void {
        for (program.items) |block| {
            self.visitBlock(block);
        }
    }

    fn visitBlock(self: *SemanticAnalyzer, block: parser.Block) void {
        _ = self;
        std.debug.print("block val {}\n", .{block});
    }
};

test "init semantic analyzer" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\start:
        \\lui x2, #0xfd
        \\otherfn:
        \\halt
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var prsr = parser.Parser.init(allocator, tokens.items, false);
    defer prsr.deinit();

    var sema = SemanticAnalyzer.init(allocator);
    sema.analyze(prsr.ast);
}
