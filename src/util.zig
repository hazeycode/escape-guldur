const std = @import("std");

pub fn StaticList(comptime ElementType: type, comptime max_count: usize) type {
    return struct {
        elements: [max_count]ElementType = undefined,
        count: usize = 0,

        pub fn push(self: *@This(), element: ElementType) !void {
            if (self.count >= max_count) return error.NoSpaceLeft;
            self.elements[self.count] = element;
            self.count += 1;
        }

        pub fn clear(self: *@This()) void {
            self.elements = std.mem.zeroes(@TypeOf(self.elements));
            self.count = 0;
        }

        pub inline fn get(self: *@This(), index: usize) !ElementType {
            if (index >= self.count) return error.InvalidElementAtIndex;
            return self.elements[index];
        }

        pub inline fn all(self: *@This()) []ElementType {
            return self.elements[0..self.count];
        }
    };
}

pub fn quicksort(
    values: anytype,
    low: isize,
    high: isize,
    comparitor: anytype,
) void {
    if (low >= high) return;
    const p = partition(values, low, high, comparitor);
    quicksort(values, low, p - 1, comparitor);
    quicksort(values, p + 1, high, comparitor);
}

fn partition(
    values: anytype,
    low: isize,
    high: isize,
    comparitor: anytype,
) isize {
    const pivot = values[@intCast(usize, high)];
    var i = low - 1;
    var j = @intCast(usize, low);
    while (j < high) : (j += 1) {
        if (comparitor.compare(values[j], pivot)) {
            i += 1;
            swap(values, @intCast(usize, i), j);
        }
    }
    i += 1;
    swap(values, @intCast(usize, i), @intCast(usize, high));
    return i;
}

fn swap(values: anytype, i: usize, j: usize) void {
    const temp = values[i];
    values[i] = values[j];
    values[j] = temp;
}

pub fn NumberDigitIterator(comptime T: type) type {
    return struct {
        number: T,
        n: T,
        m: T,
        i: usize,

        pub fn init(number: T) @This() {
            return .{
                .number = number,
                .n = number,
                .m = 0,
                .i = count_digits_fast(number),
            };
        }

        pub fn next(self: *@This()) ?u8 {
            if (self.i == 0) return null;
            defer self.i -= 1;

            self.n = @divTrunc(
                self.number - self.m,
                std.math.pow(T, 10, @intCast(T, self.i) - 1),
            );

            self.m += self.n * std.math.pow(T, 10, @intCast(T, self.i) - 1);

            return @truncate(u8, self.n);
        }
    };
}

pub fn count_digits_fast(number: anytype) usize {
    const n = if (number < 0) -number else number;
    return @as(usize, switch (n) {
        0...9 => 1,
        10...99 => 2,
        100...999 => 3,
        1000...9999 => 4,
        10000...99999 => 5,
        else => unreachable,
    }) + @as(usize, if (number < 0) 1 else 0);
}

//

const testing = std.testing;

test "quicksort" {
    var comparitor = struct {
        pub fn compare(_: @This(), a: u32, b: u32) bool {
            return a < b;
        }
    }{};

    {
        var values = [_]u32{ 3, 7, 4, 234, 4, 19, 19 };
        quicksort(&values, 0, values.len - 1, comparitor);

        const expected = [_]u32{ 3, 4, 4, 7, 19, 19, 234 };

        try testing.expectEqualSlices(u32, &expected, &values);
    }
    {
        var values = [_]u32{ 3, 3 };
        quicksort(&values, 0, values.len - 1, comparitor);

        const expected = [_]u32{ 3, 3 };

        try testing.expectEqualSlices(u32, &expected, &values);
    }
}

test "NumberDigitIterator" {
    var digit_iter = NumberDigitIterator(u32).init(1234);
    var i: usize = 0;
    while (digit_iter.next()) |digit| {
        switch (i) {
            0 => try testing.expectEqual(@as(u8, 1), digit),
            1 => try testing.expectEqual(@as(u8, 2), digit),
            2 => try testing.expectEqual(@as(u8, 3), digit),
            3 => try testing.expectEqual(@as(u8, 4), digit),
            else => unreachable,
        }
        i += 1;
    }
    try testing.expectEqual(@as(usize, 4), i);
}
