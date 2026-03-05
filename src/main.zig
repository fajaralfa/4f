const std = @import("std");
const mod = @import("4f");
const cpu = mod.cpu;
const assembler = mod.assembler;
const mmio = mod.mmio;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var mem = [_]u8{0} ** cpu.max_memory;
    var uart = mmio.UART{};

    const uart_mmio = cpu.MMIODevice{
        .base = 0xFF00,
        .size = 4,
        .ctx = &uart,
        .read = mmio.uartRead,
        .write = mmio.uartWrite,
    };

    const allocator = std.heap.smp_allocator;

    var machine = try cpu.CPU.init(mem[0..]);
    try machine.addMMIO(allocator, uart_mmio);
    defer machine.deinitMMIO(allocator);

    // program to print ABCDEF. No cheating, only use general purpose register (2,3,4).
    // I want to use stack, but this is already make my head twisting.
    const program_words = [_]u16{
        // r2 = 1
        assembler.lui(2, 0),
        assembler.addi(2, 2, 0x1),

        // r3 = 6
        assembler.lui(3, 0),
        assembler.addi(3, 3, 0x6),

        // loop:
        // r2 = r2 << r3 (0x40)
        assembler.sll(2, 2, 3),

        // r2 = r2 + 1 (0x41 / 'A')
        assembler.addi(2, 2, 0x1),

        // mmio mem[0xFF00] = r2
        assembler.lui(3, 0xff),
        assembler.sw(2, 3, 0),

        // loop back to -13
        assembler.lui(4, 0),
        assembler.notInstr(4, 4),
        assembler.lui(3, 0),
        assembler.addi(3, 3, 0xc),
        assembler.sub(4, 4, 3),

        // store target value in r3 (0x46 for 'F')
        assembler.lui(3, 0),
        assembler.addi(3, 3, 0x1f),
        assembler.addi(3, 3, 0x1f),
        assembler.addi(3, 3, 0x8),

        // jump if r2 != r3
        assembler.bne(4, 2, 3),

        // halt
        assembler.halt(),
    };
    var buffer: [program_words.len * 2]u8 = undefined;
    const program = try assembler.assemble(buffer[0..], program_words[0..]);
    try machine.loadProgram(program);
    try machine.runProgram();
    std.debug.print("\n", .{});
}
