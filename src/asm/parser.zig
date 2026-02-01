const std = @import("std");
const lexer = @import("lexer.zig");

pub const Program = std.ArrayList(Block);

pub const Block = union(enum) {
    label: Label,
    instruction: Instruction,
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
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ast: Program,
    pos: i32,

    fn init(allocator: std.mem.Allocator, input: []lexer.Token) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = input,
            .ast = Program.empty,
            .pos = 0,
        };
    }

    fn deinit(self: *Parser) void {
        self.ast.deinit(self.allocator);
    }

    fn print(self: *Parser) void {
        for (self.ast.items) |block| {
            std.log.debug("{}", block);
        }
    }

    fn parse(self: *Parser) !Program {
        while (self.current().type != .EOF) {
            self.ast.append(self.allocator, try self.parse_block());
        }
        return self.ast;
    }

    fn current(self: *Parser) *lexer.Token {
        return self.tokens[self.pos];
    }

    fn advance(self: *Parser) void {
        self.pos += 1;
    }

    fn expect(self: *Parser, toktype: lexer.TokenType) !lexer.Token {
        const tok = self.current();
        if (tok.type != toktype) {
            return ParseError.InvalidSyntax;
        }
        self.advance();
        return tok;
    }

    fn parseBlock(self: *Parser) !Block {
        if (self.current().type == .Identifier and self.tokens[self.pos + 1].type == .Colon) {
            const label = self.parseLabel();
            try self.expect(.Colon);
            return Block{ .label = label };
        } else {
            const instr = try self.parseInstr();
            return Block{ .instruction = instr };
        }
    }

    fn parseInstr(self: *Parser) !Instruction {
        const opcode = (try self.expect(.Identifier)).literal;
        var operand = std.ArrayList(Operand).empty;
        switch (self.current().type) {
            .Identifier, .ImmVal => {
                operand.append(self.allocator, try self.parseOperand());
                while (self.current().type == .Comma) {
                    self.advance();
                    operand.append(self.allocator, try self.parseOperand());
                }
            },
        }
        return Instruction{ .opcode = opcode, .operand = operand.items };
    }

    fn parseOperand(self: *Parser) !Operand {
        const tok = self.current();
        if (tok.type == .Identifier) {
            self.advance();
            return Operand{ .immediate = 20 };
        }

        return ParseError.InvalidSyntax;
    }
};

test "Init parser" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\start: end:
        \\x1 lui
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(allocator, tokens.items);
    defer parser.deinit();
    const ast = try parser.parse();
    _ = ast;
}
