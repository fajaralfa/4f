const std = @import("std");
const reportermod = @import("reporter.zig");

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
    pos: Position,
    pub fn print(self: *Token) void {
        std.debug.print("{}\n", .{self.type});
    }
};

pub const TokenType = enum {
    Identifier,
    ImmVal,
    Comma,
    Colon,
    Newline,
    EOF,
};

pub const LexerError = error{
    InvalidToken,
};

pub const Position = struct {
    line: u32,
    col: u32,
};

pub const Lexer = struct {
    start: usize,
    current: usize,
    pos: Position,
    allocator: std.mem.Allocator,
    input: []const u8,
    tokens: std.ArrayList(Token),
    reporter: reportermod.Reporter,

    pub fn init(allocator: std.mem.Allocator, input: []const u8, reporter: reportermod.Reporter) Lexer {
        return Lexer{
            .allocator = allocator,
            .start = 0,
            .current = 0,
            .pos = .{
                .line = 1,
                .col = 0,
            },
            .input = input,
            .tokens = std.ArrayList(Token).empty,
            .reporter = reporter,
        };
    }

    pub fn deinit(self: *Lexer) void {
        for (self.tokens.items) |item| {
            self.allocator.free(item.literal);
        }
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) !std.ArrayList(Token) {
        while (!self.isAtEnd()) {
            self.start = self.current;
            self.scanToken() catch {};
        }
        // set position at the end of input
        self.start = self.input.len - 1;
        self.current = self.start;
        try self.addToken(.EOF);

        return self.tokens;
    }

    pub fn print(self: *Lexer) void {
        for (self.tokens.items) |token| {
            std.debug.print("token: {}\n", .{token});
        }
    }

    fn scanToken(self: *Lexer) !void {
        const c = self.next();
        switch (c) {
            ' ', '\t', '/' => {},
            '\n' => {
                try self.newline();
                self.pos.line += 1;
                self.pos.col = 0;
            },
            'A'...'Z', 'a'...'z', '_' => try self.identifier(),
            '#' => try self.number(),
            ',' => try self.addToken(.Comma),
            ':' => try self.addToken(.Colon),
            else => {
                try self.reporter.add(.Err, "Error at {c} {}\n", .{ c, self.pos });
                return LexerError.InvalidToken;
            },
        }
    }

    fn next(self: *Lexer) u8 {
        const c = self.input[self.current];
        self.current += 1;
        self.pos.col += 1;
        return c;
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.current >= self.input.len;
    }

    fn peek(self: *Lexer) u8 {
        if (self.isAtEnd()) {
            return 0;
        }
        return self.input[self.current];
    }

    fn addToken(self: *Lexer, typ: TokenType) !void {
        const literal = try self.captureLiteral();
        const token = Token{
            .type = typ,
            .literal = literal,
            .pos = self.pos,
        };
        try self.tokens.append(self.allocator, token);
    }

    fn identifier(self: *Lexer) !void {
        while (std.ascii.isAlphanumeric(self.peek())) {
            _ = self.next();
        }
        try self.addToken(.Identifier);
    }

    fn newline(self: *Lexer) !void {
        try self.addToken(.Newline);
    }

    fn captureLiteral(self: *Lexer) ![]const u8 {
        const literal = try self.allocator.alloc(u8, self.current - self.start);
        const text = self.input[self.start..self.current];
        @memcpy(literal, text);
        return literal;
    }

    fn number(self: *Lexer) !void {
        var base: u8 = 10; // default decimal

        // Handle optional leading 0 + base prefix
        if (self.peek() == '0') {
            _ = self.next();

            const c = self.peek();
            switch (c) {
                'x', 'X' => {
                    _ = self.next();
                    base = 16;
                },
                'b', 'B' => {
                    _ = self.next();
                    base = 2;
                },
                'o', 'O' => {
                    _ = self.next();
                    base = 8;
                },
                else => {
                    // leading 0 with no prefix is decimal 0
                    base = 10;
                },
            }
        }

        // At least one digit is required
        if (!isDigitForBase(self.peek(), base)) {
            return LexerError.InvalidToken;
        }

        // Consume all digits valid for this base
        while (isDigitForBase(self.peek(), base)) {
            _ = self.next();
        }

        // If any letters/underscores are left, it's invalid (e.g., #23someword)
        if (std.ascii.isAlphabetic(self.peek()) or self.peek() == '_') {
            return LexerError.InvalidToken;
        }

        try self.addToken(.ImmVal);
    }

    fn isDigitForBase(c: u8, base: u8) bool {
        switch (base) {
            2 => return c == '0' or c == '1',
            8 => return c >= '0' and c <= '7',
            10 => return std.ascii.isDigit(c),
            16 => return std.ascii.isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'),
            else => return false,
        }
    }
};

test "Scan ignore position" {
    const str: []const u8 = ", x1 _start:";
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, str);
    const tokens = try lex.tokenize();
    defer lex.deinit();

    const expected = [_]Token{
        .{ .type = .Comma, .literal = ",", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .Identifier, .literal = "x1", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .Identifier, .literal = "_start", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .Colon, .literal = ":", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .EOF, .literal = "", .pos = .{ .line = 1, .col = 1 } },
    };
    for (expected, tokens.items) |exp, act| {
        try std.testing.expectEqual(exp.type, act.type);
        try std.testing.expectEqualSlices(u8, exp.literal, act.literal);
    }
}

test "Scan immediate ignore position" {
    const str: []const u8 = "#123 #0xFA #0o12 #0b101";
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, str);
    const tokens = try lex.tokenize();
    defer lex.deinit();

    const expected = [_]Token{
        .{ .type = .ImmVal, .literal = "#123", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .ImmVal, .literal = "#0xFA", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .ImmVal, .literal = "#0o12", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .ImmVal, .literal = "#0b101", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .EOF, .literal = "", .pos = .{ .line = 1, .col = 1 } },
    };
    for (expected, tokens.items) |exp, act| {
        try std.testing.expectEqual(exp.type, act.type);
        try std.testing.expectEqualSlices(u8, exp.literal, act.literal);
    }
}

fn expectInvalidToken(str: []const u8) !void {
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, str);
    const tokens = lex.tokenize();
    defer lex.deinit();

    try std.testing.expectError(LexerError.InvalidToken, tokens);
}

test "Scan invalid immediates" {
    try expectInvalidToken("#wrong");
    try expectInvalidToken("#0wrong");
    try expectInvalidToken("#23wrong");
}

test "Scan invalid tokens" {
    // just random
    try expectInvalidToken("#;");
    try expectInvalidToken("@");
}

test "Scan identifier ignore position" {
    const str = "lw sw halt";
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, str);
    const tokens = try lex.tokenize();
    defer lex.deinit();

    const expected = [_]Token{
        .{ .type = .Identifier, .literal = "lw", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .Identifier, .literal = "sw", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .Identifier, .literal = "halt", .pos = .{ .line = 1, .col = 1 } },
        .{ .type = .EOF, .literal = "", .pos = .{ .line = 1, .col = 1 } },
    };
    for (expected, tokens.items) |exp, act| {
        try std.testing.expectEqual(exp.type, act.type);
        try std.testing.expectEqualSlices(u8, exp.literal, act.literal);
    }
}

test "Scan newline" {
    const str = "lw sw\nlw\n";
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, str);
    const tokens = try lex.tokenize();
    defer lex.deinit();

    const expected = [_]Token{
        .{ .type = .Identifier, .literal = "lw", .pos = .{ .line = 1, .col = 2 } },
        .{ .type = .Identifier, .literal = "sw", .pos = .{ .line = 1, .col = 5 } },
        .{ .type = .Newline, .literal = "\n", .pos = .{ .line = 1, .col = 6 } },
        .{ .type = .Identifier, .literal = "lw", .pos = .{ .line = 2, .col = 2 } },
        .{ .type = .Newline, .literal = "\n", .pos = .{ .line = 2, .col = 3 } },
        .{ .type = .EOF, .literal = "", .pos = .{ .line = 3, .col = 0 } },
    };
    for (expected, tokens.items) |exp, act| {
        try std.testing.expectEqual(exp.type, act.type);
        try std.testing.expectEqual(exp.pos.line, act.pos.line);
        try std.testing.expectEqual(exp.pos.col, act.pos.col);
        try std.testing.expectEqualSlices(u8, exp.literal, act.literal);
    }
}

test "Scan immediate zero" {
    const str = "#1";
    const allocator = std.testing.allocator;
    var reporter = reportermod.Reporter.init(allocator, true);
    defer reporter.deinit();
    var lex = Lexer.init(allocator, str, reporter);
    const tokens = try lex.tokenize();
    _ = tokens;
    defer lex.deinit();
}
