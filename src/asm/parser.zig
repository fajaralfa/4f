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
                std.debug.print("instr: opcode {}, operands ", .{instr.opcode});
                for (instr.operand.items) |*opr| {
                    switch (opr.*) {
                        .immediate => |imm| {
                            std.debug.print("{}", .{imm});
                        },
                        .label => |label| {
                            std.debug.print("{}", .{label});
                        },
                        .register => |reg| {
                            std.debug.print("{}", .{reg});
                        },
                    }
                    std.debug.print(", ", .{});
                }
                std.debug.print("\n", .{});
            },
        }
    }

    pub fn free(self: *Block, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .instruction => |*instr| {
                instr.operand.deinit(allocator);
            },
            else => {},
        }
    }
};

pub const Label = struct {
    name: []const u8,
    address: ?u16 = null, // absolute address from start of the program
};

pub const Instruction = struct {
    opcode: Opcode,
    operand: std.ArrayList(Operand),
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
        for (self.ast.items) |*block| {
            block.free(self.allocator);
        }
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
                _ = self.advance();
                continue;
            }
            try self.ast.append(self.allocator, try self.parseBlock());
        }
        return self.ast;
    }

    fn current(self: *Parser) lexer.Token {
        return self.tokens[self.pos];
    }

    fn advance(self: *Parser) lexer.Token {
        self.pos += 1;
        const tok = self.current();
        self.debugToken(tok, "advance");
        return tok;
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

    fn parseLabel(self: *Parser) !Label {
        const label_tok: lexer.Token = self.current();
        _ = self.advance();
        _ = try self.expect(.Colon);
        _ = self.advance();
        return Label{ .name = label_tok.literal };
    }

    fn parseInstruction(self: *Parser) !Instruction {
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
                        const value = try std.fmt.parseInt(u8, curr.literal[3..], 16);
                        const operand = Operand{ .immediate = @bitCast(value) };
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

fn parseOpcode(name: []const u8) ?Opcode {
    if (std.mem.eql(u8, name, "halt")) return .Halt;
    if (std.mem.eql(u8, name, "lui")) return .Lui;
    if (std.mem.eql(u8, name, "addi")) return .Addi;
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
