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
