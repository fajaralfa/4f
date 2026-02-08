const std = @import("std");
const lexer = @import("lexer.zig");
const astmod = @import("ast.zig");
const Program = astmod.Program;
const Block = astmod.Block;
const Label = astmod.Label;
const Instruction = astmod.Instruction;
const Opcode = astmod.Opcode;
const Operand = astmod.Operand;
const Register = astmod.Register;
const Immediate = astmod.Immediate;

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

    pub fn init(allocator: std.mem.Allocator, input: []lexer.Token, debug: bool) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = input,
            .ast = Program.empty,
            .pos = 0,
            .debug = debug,
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.ast.items) |*block| {
            block.free(self.allocator);
        }
        self.ast.deinit(self.allocator);
    }

    pub fn print(self: *Parser) void {
        for (self.ast.items) |block| {
            block.print();
        }
    }

    pub fn parse(self: *Parser) !Program {
        while (self.current().type != .EOF) {
            if (self.current().type == .Newline) {
                _ = self.advance();
                continue;
            }
            try self.ast.append(self.allocator, try self.parseBlock());
        }
        return self.ast;
    }

    pub fn current(self: *Parser) lexer.Token {
        return self.tokens[self.pos];
    }

    pub fn advance(self: *Parser) lexer.Token {
        self.pos += 1;
        const tok = self.current();
        self.debugToken(tok, "advance");
        return tok;
    }

    pub fn debugToken(self: *Parser, tok: lexer.Token, method: []const u8) void {
        if (self.debug) {
            std.debug.print("place: {s} pos: {} type: {} lit: \"{s}\"\n", .{ method, self.pos, tok.type, tok.literal });
        }
    }

    pub fn expect(self: *Parser, toktype: lexer.TokenType) !lexer.Token {
        const tok = self.current();
        self.debugToken(tok, "expect");
        if (tok.type != toktype) {
            return ParseError.InvalidSyntax;
        }
        return tok;
    }

    pub fn parseBlock(self: *Parser) !Block {
        const curr = self.current();
        if (curr.type == .Identifier and self.tokens[self.pos + 1].type == .Colon) {
            const opcode = parseOpcode(curr.literal);
            const register = parseRegister(curr.literal);
            if (opcode == null and register == null) {
                const label = try self.parseLabel();
                return Block{ .label = label };
            }
        } else if (curr.type == .Identifier) {
            const instruction = try self.parseInstruction();
            return Block{ .instruction = instruction };
        }
        self.debugToken(curr, "parseBlock");
        return ParseError.InvalidSyntax;
    }

    pub fn parseLabel(self: *Parser) !Label {
        const label_tok: lexer.Token = self.current();
        _ = self.advance();
        _ = try self.expect(.Colon);
        _ = self.advance();
        return Label{ .name = label_tok.literal };
    }

    pub fn parseInstruction(self: *Parser) !Instruction {
        const opcode = parseOpcode(self.current().literal) orelse {
            return ParseError.UnknownOpcode;
        };
        var curr = self.advance();
        var operands = std.ArrayList(Operand).empty;
        if (curr.type == .Identifier or curr.type == .ImmVal) {
            while (curr.type != .EOF and curr.type != .Newline) {
                switch (curr.type) {
                    .Identifier => {
                        const op_reg = parseRegister(curr.literal);
                        const op_opcode = parseOpcode(curr.literal);
                        var operand: Operand = undefined;
                        if (op_opcode != null) {
                            return ParseError.InvalidSyntax;
                        }
                        if (op_reg != null) {
                            operand = Operand{ .register = op_reg orelse unreachable };
                        } else {
                            operand = Operand{ .label = .{ .name = curr.literal } };
                        }
                        try operands.append(self.allocator, operand);
                    },
                    .ImmVal => {
                        const value = try parseImmediate(curr.literal);
                        const operand = Operand{ .immediate = value };
                        try operands.append(self.allocator, operand);
                    },
                    .Comma => {
                        // skip comma
                    },
                    else => {
                        return ParseError.InvalidSyntax;
                    },
                }
                curr = self.advance();
            }
        }
        return Instruction{ .opcode = opcode, .operand = operands };
    }
};

fn parseImmediate(literal: []const u8) !u8 {
    const lit = literal[1..]; // ignore the hashtag
    const value = try std.fmt.parseInt(u8, lit, 0);
    return @bitCast(value);
}

fn parseOpcode(name: []const u8) ?Opcode {
    if (std.mem.eql(u8, name, "halt")) return .Halt;
    if (std.mem.eql(u8, name, "lw")) return .Lw;
    if (std.mem.eql(u8, name, "sw")) return .Sw;
    if (std.mem.eql(u8, name, "lui")) return .Lui;
    if (std.mem.eql(u8, name, "addi")) return .Addi;
    if (std.mem.eql(u8, name, "add")) return .Add;
    if (std.mem.eql(u8, name, "sub")) return .Sub;
    if (std.mem.eql(u8, name, "and")) return .And;
    if (std.mem.eql(u8, name, "not")) return .Not;
    if (std.mem.eql(u8, name, "or")) return .Or;
    if (std.mem.eql(u8, name, "xor")) return .Xor;
    if (std.mem.eql(u8, name, "sll")) return .Sll;
    if (std.mem.eql(u8, name, "srl")) return .Srl;
    if (std.mem.eql(u8, name, "sra")) return .Sra;
    if (std.mem.eql(u8, name, "jr")) return .Jr;
    if (std.mem.eql(u8, name, "beq")) return .Beq;
    if (std.mem.eql(u8, name, "bne")) return .Bne;
    return null;
}

fn parseRegister(name: []const u8) ?Register {
    if (std.mem.eql(u8, name, "pc")) return .PC;
    if (std.mem.eql(u8, name, "sp")) return .SP;
    if (std.mem.eql(u8, name, "x1")) return .X1;
    if (std.mem.eql(u8, name, "x2")) return .X2;
    if (std.mem.eql(u8, name, "x3")) return .X3;
    if (std.mem.eql(u8, name, "mepc")) return .MEPC;
    if (std.mem.eql(u8, name, "mcause")) return .MCAUSE;
    if (std.mem.eql(u8, name, "mtvec")) return .MTVEC;
    return null;
}

test "Parse label def" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
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

test "Parse instruction" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\halt
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(allocator, tokens.items, false);
    defer parser.deinit();
    const ast = try parser.parse();
    _ = ast;
    parser.print();
}

test "Parse instruction with operand" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\lui x2, #0xff
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(allocator, tokens.items, true);
    defer parser.deinit();
    const ast = try parser.parse();
    _ = ast;
    parser.print();
}

test "Parse full program" {
    const allocator = std.testing.allocator;
    var lex = lexer.Lexer.init(allocator,
        \\start:
        \\lui x2, #0xfd
        \\otherfn:
        \\halt
    );
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(allocator, tokens.items, false);
    defer parser.deinit();
    const ast = try parser.parse();
    _ = ast;
    parser.print();
}
