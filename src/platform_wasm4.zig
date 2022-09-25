const std = @import("std");
const w4 = @import("wasm4.zig");

pub const screen_width = w4.SCREEN_SIZE;
pub const screen_height = w4.SCREEN_SIZE;

pub inline fn trace(str: []const u8) void {
    w4.trace(str);
}

pub inline fn tracef(template: [*:0]const u8, args: anytype) void {
    w4.tracef(template, args);
}

pub inline fn set_palette(palette: anytype) void {
    w4.PALETTE.* = palette;
}

pub inline fn set_draw_colours(colours: anytype) void {
    w4.DRAW_COLORS.* = colours;
}

pub inline fn text(str: []const u8, x: anytype, y: anytype) void {
    w4.text(str, x, y);
}

pub inline fn line(x0: anytype, y0: anytype, x1: anytype, y1: anytype) void {
    w4.line(x0, y0, x1, y1);
}

pub inline fn hline(x: anytype, y: anytype, len: anytype) void {
    w4.hline(x, y, len);
}

pub inline fn vline(x: anytype, y: anytype, len: anytype) void {
    w4.vline(x, y, len);
}

pub inline fn rect(x: anytype, y: anytype, width: anytype, height: anytype) void {
    w4.rect(x, y, width, height);
}

pub inline fn oval(x: anytype, y: anytype, width: anytype, height: anytype) void {
    w4.oval(x, y, width, height);
}

pub fn blit(
    texture_bytes: []const u8,
    x: anytype,
    y: anytype,
    width: anytype,
    height: anytype,
    bpp: u8,
    flip_x: bool,
) void {
    var flags: u32 = 0;
    switch (bpp) {
        1 => {
            flags |= w4.BLIT_1BPP;
        },
        2 => {
            flags |= w4.BLIT_2BPP;
        },
        else => {
            std.debug.assert(false);
        },
    }
    if (flip_x) flags |= w4.BLIT_FLIP_X;
    w4.blit(@ptrCast([*]const u8, texture_bytes), x, y, width, height, flags);
}
