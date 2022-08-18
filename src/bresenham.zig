const std = @import("std");

/// A piece-wise implementaion of Bresenham's line algorithm (https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm)
/// `plotter` should be something defining a `plot(x, y) bool` member function that returns false if plotting should stop
pub fn line(x0: i32, y0: i32, x1: i32, y1: i32, plotter: anytype) void {
    std.debug.assert(@typeInfo(@TypeOf(plotter)) == .Pointer);

    var x = x0;
    var y = y0;
    var dx = abs(x1 - x0);
    var sx: i32 = if (x0 < x1) 1 else -1;
    var dy = -abs(y1 - y0);
    var sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;

    while (true) {
        if (plotter.plot(x, y) == false) {
            return;
        }

        if (x0 == x1 and y0 == y1) break;

        const e2 = 2 * err;

        if (e2 >= dy) {
            if (x == x1) break;
            err = err + dy;
            x = x + sx;
        }

        if (e2 < dx) {
            if (y == y1) break;
            err = err + dx;
            y = y + sy;
        }
    }
}

fn line_low(x0: i32, y0: i32, x1: i32, y1: i32, plotter: anytype) void {
    var dx = x1 - x0;
    var dy = y1 - y0;
    var yi: i32 = 1;

    if (dy < 0) {
        yi = -1;
        dy = -dy;
    }

    var d = (2 * dy) - dx;
    var y = y0;
    var x = x0;
    while (x <= x1) : (x += 1) {
        if (plotter.plot(x, y) == false) {
            return;
        }
        if (d > 0) {
            y = y + yi;
            d = d + (2 * (dy - dx));
        } else {
            d = d + 2 * dy;
        }
    }
}

fn line_high(x0: i32, y0: i32, x1: i32, y1: i32, plotter: anytype) void {
    var dx = x1 - x0;
    var dy = y1 - y0;
    var xi: i32 = 1;

    if (dx < 0) {
        xi = -1;
        dx = -dx;
    }

    var d = (2 * dx) - dy;
    var x = x0;
    var y = y0;
    while (y <= y1) : (y += 1) {
        if (plotter.plot(x, y) == false) {
            return;
        }
        if (d > 0) {
            x = x + xi;
            d = d + (2 * (dx - dy));
        } else {
            d = d + 2 * dx;
        }
    }
}

fn abs(x: anytype) @TypeOf(x) {
    return if (x < 0) -x else x;
}

const testing = std.testing;

test "bresenham.line" {
    const Point = struct { x: i32, y: i32 };

    var plotter = struct {
        points: std.ArrayList(Point),

        pub fn plot(self: *@This(), x: i32, y: i32) bool {
            self.points.append(.{ .x = x, .y = y }) catch @panic("out of memory");
            return true;
        }
    }{
        .points = std.ArrayList(Point).init(testing.allocator),
    };
    defer plotter.points.deinit();

    {
        line(0, 0, 2, -1, &plotter);
        defer plotter.points.clearRetainingCapacity();

        try testing.expectEqualSlices(
            Point,
            &.{
                Point{ .x = 0, .y = 0 },
                Point{ .x = 1, .y = 0 },
                Point{ .x = 2, .y = -1 },
            },
            plotter.points.items,
        );
    }

    {
        line(0, 0, -2, -2, &plotter);
        defer plotter.points.clearRetainingCapacity();

        try testing.expectEqualSlices(
            Point,
            &.{
                Point{ .x = 0, .y = 0 },
                Point{ .x = -1, .y = -1 },
                Point{ .x = -2, .y = -2 },
            },
            plotter.points.items,
        );
    }

    {
        line(0, 0, -2, 3, &plotter);
        defer plotter.points.clearRetainingCapacity();

        try testing.expectEqualSlices(
            Point,
            &.{
                Point{ .x = 0, .y = 0 },
                Point{ .x = -1, .y = 1 },
                Point{ .x = -1, .y = 2 },
                Point{ .x = -2, .y = 3 },
            },
            plotter.points.items,
        );
    }

    {
        line(0, 0, 3, 5, &plotter);
        defer plotter.points.clearRetainingCapacity();

        try testing.expectEqualSlices(
            Point,
            &.{
                Point{ .x = 0, .y = 0 },
                Point{ .x = 1, .y = 1 },
                Point{ .x = 1, .y = 2 },
                Point{ .x = 2, .y = 3 },
                Point{ .x = 2, .y = 4 },
                Point{ .x = 3, .y = 5 },
            },
            plotter.points.items,
        );
    }
}
