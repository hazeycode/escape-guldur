const std = @import("std");

/// A piece-wise implementaion of Bresenham's line algorithm (https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm)
/// `plotter` should be something defining a `plot(x, y) bool` member function that returns false if plotting should stop
pub fn line(x0: i32, y0: i32, x1: i32, y1: i32, plotter: anytype) void {
    var x = x0;
    var y = y0;
    const dx = abs(x1 - x0);
    const sx: i32 = if (x0 < x1) 1 else -1;
    const dy = -abs(y1 - y0);
    const sy: i32 = if (y0 < y1) 1 else -1;
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
