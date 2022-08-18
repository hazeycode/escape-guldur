const std = @import("std");

pub fn Map(comptime columns: u16, comptime rows: u16) type {
    return [columns][rows]u8;
}

pub const MapTileKind = enum(u8) {
    floor,
    wall,
    player_spawn,
    monster_spawn,
};

pub const Direction = enum(u8) { north, east, south, west };

pub const Location = struct {
    x: u8,
    y: u8,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn manhattan_to(self: Location, other: Location) u8 {
        var dx = @intCast(i16, other.x) - @intCast(i16, self.x);
        var dy = @intCast(i16, other.y) - @intCast(i16, self.y);

        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;

        return @intCast(u8, dx + dy);
    }

    pub inline fn north(self: Location) Location {
        return Location{ .x = self.x, .y = self.y - 1 };
    }

    pub inline fn east(self: Location) Location {
        return Location{ .x = self.x + 1, .y = self.y };
    }

    pub inline fn south(self: Location) Location {
        return Location{ .x = self.x, .y = self.y + 1 };
    }

    pub inline fn west(self: Location) Location {
        return Location{ .x = self.x - 1, .y = self.y };
    }
};

pub fn map_get_tile(world: anytype, pos: Location) MapTileKind {
    const world_type_info = @typeInfo(@TypeOf(world));
    std.debug.assert(world_type_info == .Array and
        @typeInfo(world_type_info.Array.child) == .Array);

    return @intToEnum(
        MapTileKind,
        world[@intCast(usize, pos.y)][@intCast(usize, pos.x)],
    );
}

const testing = std.testing;

test "world.Location.manhattan_to" {
    {
        const a = Location{ .x = 5, .y = 16 };
        const b = Location{ .x = 11, .y = 10 };
        try testing.expectEqual(@as(u8, 12), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 25, .y = 11 };
        const b = Location{ .x = 13, .y = 5 };
        try testing.expectEqual(@as(u8, 18), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 9, .y = 9 };
        const b = Location{ .x = 3, .y = 18 };
        try testing.expectEqual(@as(u8, 15), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 0, .y = 10 };
        const b = Location{ .x = 12, .y = 17 };
        try testing.expectEqual(@as(u8, 19), a.manhattan_to(b));
    }
}
