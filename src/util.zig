const std = @import("std");

pub fn swap(values: anytype, i: usize, j: usize) void {
    const temp = values[i];
    values[i] = values[j];
    values[j] = temp;
}

pub fn quicksort(values: anytype, low: usize, high: usize) void {
    if (low < high) {
        const p = partition(values, low, high);
        quicksort(values, low, p - 1);
        quicksort(values, p + 1, high);
    }
}

fn partition(values: anytype, low: usize, high: usize) usize {
    const pivot = values[high];
    var i = @intCast(isize, low) - 1;
    var j = low;
    while (j <= high - 1) : (j += 1) {
        if (values[j] < pivot) {
            i += 1;
            swap(values, @intCast(usize, i), j);
        }
    }
    swap(values, @intCast(usize, i + 1), high);
    return @intCast(usize, i + 1);
}

const testing = std.testing;

test "quicksort" {
    var values = [_]u32{ 3, 7, 4, 234, 4, 19, 19 };
    quicksort(&values, 0, values.len - 1);

    const expected = [_]u32{ 3, 4, 4, 7, 19, 19, 234 };

    try testing.expectEqualSlices(u32, &expected, &values);
}
