const std = @import("std");

pub fn swap(values: anytype, i: usize, j: usize) void {
    const temp = values[i];
    values[i] = values[j];
    values[j] = temp;
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
