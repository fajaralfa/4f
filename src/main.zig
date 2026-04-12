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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var machine = try cpu.CPU.init(mem[0..]);
    try machine.addMMIO(allocator, uart_mmio);
    defer machine.deinitMMIO(allocator);

    // program to print ABCDEF using only general purpose register (2,3,4).
    // I want to use stack, but this is already make my head twisting.
    const program =
        // x1 = 1
        \\lui x1, #0
        \\addi x1, x1, #1
        // x2 = 6
        \\lui x2, #0
        \\addi x2, x2, #6
        // loop:
        // x1 = x1 << x2 (0x40)
        \\sll x1, x1, x2

        // x1 = x1 + 1 (0x41 / 'A')
        \\addi x1, x1, #0x01
        // mmio mem[0xFF00] = x1
        \\lui x2, #0xff
        \\sw x1, x2, #0
        // loop back to -13
        \\lui x3, #0
        \\not x3, x3
        \\lui x2, #0
        \\addi x2, x2, #0xc
        \\sub x3, x3, x2
        // store target value in x2 (0x46 for 'F')
        \\lui x2, #0
        \\addi x2, x2, #0x1f
        \\addi x2, x2, #0x1f
        \\addi x2, x2, #0x8
        // jump if x1 != r2
        \\bne x3, x1, x2

        // halt
        \\halt
    ;
    var binary = try mod.assembler.assemble(allocator, program, false);
    mod.assembler.print(binary.items);
    defer binary.deinit(allocator);
    try machine.loadProgram(binary.items);
    try machine.runProgram();
    std.debug.print("\n", .{});
}
