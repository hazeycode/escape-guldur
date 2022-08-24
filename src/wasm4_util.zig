const w4 = @import("wasm4.zig");

pub fn text_centered(str: []const u8, y: i32) void {
    const glyph_width = 8;
    const text_width = str.len * glyph_width;
    w4.text(
        str,
        @intCast(i32, w4.SCREEN_SIZE / 2 - text_width / 2),
        y,
    );
}
