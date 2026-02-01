const std = @import("std");
const lexer = @import("lexer.zig");

pub const Program = std.ArrayList(Block);

pub const Block = union(enum) {
    label: Label,
    instruction: Instruction,

    pub fn print(self: *const Block) void {
        switch (self.*) {
            .label => |label| {
                std.debug.print("{s} {?d}\n", .{
                    label.name,
                    label.address,
                });
            },
            .instruction => |instr| {
                std.debug.print("instr {}\n", .{instr});
            },
        }
    }
};

pub const Label = struct {
    name: []const u8,
    address: ?u16 = null, // absolute address from start of the program
};

pub const Instruction = struct {
    opcode: Opcode,
    operand: []Operand,
};

pub const Opcode = enum {
    Halt,
    Lui,
    Addi,
};

pub const Operand = union(enum) {
    register: Register,
    immediate: Immediate,
    label: Label,
};

pub const Register = enum { PC, SP, X1, X2, X3, MEPC, MCAUSE, MTVEC };
pub const Immediate = i8;

pub const ParseError = error{
    InvalidSyntax,
    Unimplemented,
    UnknownOpcode,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ast: Program,
    pos: usize,
    debug: bool,

    fn init(allocator: std.mem.Allocator, input: []lexer.Token, debug: bool) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = input,
            .ast = Program.empty,
            .pos = 0,
            .debug = debug,
        };
    }

    fn deinit(self: *Parser) void {
        self.ast.deinit(self.allocator);
    }

    fn print(self: *Parser) void {
        for (self.ast.items) |block| {
            block.print();
        }
    }

    fn parse(self: *Parser) !Program {
        while (self.current().type != .EOF) {
            if (self.current().type == .Newline) {
                self.advance();
                continue;
            }
            try self.ast.append(self.allocator, try self.parseBlock());
        }
        return self.ast;
    }

    fn current(self: *Parser) lexer.Token {
        return self.tokens[self.pos];
    }

    fn advance(self: *Parser) void {
        self.pos += 1;
    }

    fn debugToken(self: *Parser, tok: lexer.Token, method: []const u8) void {
        if (self.debug) {
            std.debug.print("place: {s} pos: {} type: {} lit: \"{s}\"\n", .{ method, self.pos, tok.type, tok.literal });
        }
    }

    fn expect(self: *Parser, toktype: lexer.TokenType) !lexer.Token {
        const tok = self.current();
        self.debugToken(tok, "expect");
        if (tok.type != toktype) {
            return ParseError.InvalidSyntax;
        }
        return tok;
    }

    fn parseBlock(self: *Parser) !Block {
        if (self.current().type == .Identifier and self.tokens[self.pos + 1].type == .Colon) {
            const label = try self.parseLabel();
            return Block{ .label = label };
        }
        return ParseError.InvalidSyntax;
    }

    fn parseLabel(self: *Parser) !Label {
        const label_tok: lexer.Token = self.current();
        self.advance();
        _ = try self.expect(.Colon);
        self.advance();
        return Label{ .name = label_tok.literal };
    }
};

            return Operand{ .immediate = 20 };
        }

        return ParseError.InvalidSyntax;
    }
};

test "Init parser" {
test "Parse label def" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\start:
        \\start:
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(allocator, tokens.items, false);
    defer parser.deinit();
    const ast = try parser.parse();
    _ = ast;
    parser.print();
}
