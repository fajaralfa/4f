pub const assembler = @import("asm/asm.zig");
pub const cpu = @import("cpu.zig");
pub const mmio = @import("mmio.zig");

test {
    // This ensures tests in imported files are discovered
    _ = @import("assembler.zig");
    _ = @import("cpu.zig");
    _ = @import("mmio.zig");
    _ = @import("asm/lexer.zig");
    _ = @import("asm/parser.zig");
    _ = @import("asm/semantic.zig");
    _ = @import("asm/codegen.zig");
}
