const std = @import("std");

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
pub const Immediate = u8;
