const std = @import("std");
const asttype = @import("ast.zig");
const codegenmod = @import("codegen.zig");
const lexermod = @import("lexer.zig");
const parsermod = @import("parser.zig");
const reportermod = @import("reporter.zig");
const semantic = @import("semantic.zig");

pub fn assemble(allocator: std.mem.Allocator, input: []const u8) !std.ArrayList(u8) {
    // error reporter
    var reporter = reportermod.Reporter.init(std.heap.smp_allocator, true);
    defer reporter.deinit();

    // lexing
    var lex = lexermod.Lexer.init(allocator, input, reporter);
    defer lex.deinit();
    const tokens = try lex.tokenize();

    // parsing
    var parser = parsermod.Parser.init(allocator, tokens.items, false);
    defer parser.deinit();
    const ast = try parser.parse();

    // semantic analysis
    var sema = semantic.SemanticAnalyzer.init(allocator, ast, reporter);
    defer sema.deinit();
    try sema.analyze();

    // codegen
    var codegen = codegenmod.Codegen.init(allocator, ast);
    defer codegen.deinit();
    const binary = try codegen.gen();
    return binary;
}
