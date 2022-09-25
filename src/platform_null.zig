const std = @import("std");

pub const screen_width = 0;
pub const screen_height = 0;

pub inline fn trace(str: []const u8) void {
    std.log.debug(str, .{});
}

pub inline fn tracef(template: [*:0]const u8, args: anytype) void {
    std.log.debug(template, args);
}

pub inline fn set_palette(palette: anytype) void {
    _ = palette;
}

pub inline fn set_draw_colours(colours: anytype) void {
    _ = colours;
}

pub inline fn text(str: []const u8, x: anytype, y: anytype) void {
    _ = str;
    _ = x;
    _ = y;
}

pub inline fn line(x0: anytype, y0: anytype, x1: anytype, y1: anytype) void {
    _ = x0;
    _ = y0;
    _ = x1;
    _ = y1;
}

pub inline fn rect(x: anytype, y: anytype, width: anytype, height: anytype) void {
    _ = x;
    _ = y;
    _ = width;
    _ = height;
}

pub inline fn blit(
    texture_bytes: []const u8,
    x: anytype,
    y: anytype,
    width: anytype,
    height: anytype,
    bpp: u8,
    flip_x: bool,
) void {
    _ = texture_bytes;
    _ = x;
    _ = y;
    _ = width;
    _ = height;
    _ = bpp;
    _ = flip_x;
}
