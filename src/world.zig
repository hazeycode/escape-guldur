const std = @import("std");

pub fn Map(comptime columns: u8, comptime rows: u8) type {
    return [columns][rows]u4;
}

pub const MapTileKind = enum(u4) {
    floor = 0,
    wall = 1,
    breakable_wall = 2,
    door = 3,
    locked_door = 4,
    sword_pickup = 5,
    small_axe_pickup = 6,
    health_pickup = 7,
    player_spawn = 10,
    monster_spawn = 11,
    fire_monster_spawn = 12,
};

pub const Direction = enum(u2) { north, east, south, west };

pub const Location = struct {
    x: i16,
    y: i16,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn manhattan_to(self: Location, other: Location) i16 {
        var dx = @intCast(i16, other.x) - @intCast(i16, self.x);
        var dy = @intCast(i16, other.y) - @intCast(i16, self.y);

        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;

        return @intCast(i16, dx + dy);
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

pub fn map_set_tile(world: anytype, location: Location, value: u4) void {
    const world_type_info = @typeInfo(@TypeOf(world));
    std.debug.assert(world_type_info == .Pointer);
    const child_type_info = @typeInfo(world_type_info.Pointer.child);
    std.debug.assert(child_type_info == .Array and
        @typeInfo(child_type_info.Array.child) == .Array);

    world[@intCast(usize, location.y)][@intCast(usize, location.x)] = value;
}

pub fn map_get_tile(world: anytype, location: Location) u4 {
    const world_type_info = @typeInfo(@TypeOf(world));
    std.debug.assert(world_type_info == .Array and
        @typeInfo(world_type_info.Array.child) == .Array);

    return world[@intCast(usize, location.y)][@intCast(usize, location.x)];
}

pub fn map_get_tile_kind(world: anytype, location: Location) MapTileKind {
    const world_type_info = @typeInfo(@TypeOf(world));
    std.debug.assert(world_type_info == .Array and
        @typeInfo(world_type_info.Array.child) == .Array);

    return @intToEnum(
        MapTileKind,
        world[@intCast(usize, location.y)][@intCast(usize, location.x)],
    );
}

const testing = std.testing;

test "world.Location.manhattan_to" {
    {
        const a = Location{ .x = 5, .y = 16 };
        const b = Location{ .x = 11, .y = 10 };
        try testing.expectEqual(@as(i16, 12), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 25, .y = 11 };
        const b = Location{ .x = 13, .y = 5 };
        try testing.expectEqual(@as(i16, 18), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 9, .y = 9 };
        const b = Location{ .x = 3, .y = 18 };
        try testing.expectEqual(@as(i16, 15), a.manhattan_to(b));
    }
    {
        const a = Location{ .x = 0, .y = 10 };
        const b = Location{ .x = 12, .y = 17 };
        try testing.expectEqual(@as(i16, 19), a.manhattan_to(b));
    }
}
