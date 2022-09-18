const w4 = @import("wasm4.zig");

pub const gfx = @import("gfx_wasm4.zig");
pub const sfx = @import("sfx_wasm4.zig");

pub inline fn trace(str: []const u8) void {
    w4.trace(str);
}

pub inline fn tracef(template: [*:0]const u8, args: anytype) void {
    w4.tracef(template, args);
}
