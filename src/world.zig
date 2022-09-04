const std = @import("std");
const w4 = @import("wasm4.zig");

const util = @import("util.zig");
const StaticList = util.StaticList;

const bresenham_line = @import("bresenham.zig").line;

pub const size_x = 20;
pub const size_y = 20;
const max_distance = size_x + size_y;

pub fn Map(comptime columns: u8, comptime rows: u8) type {
    return [columns][rows]u4;
}

pub const MapTileKind = enum(u4) {
    floor = 0,
    wall = 1,
    breakable_wall = 2,
    door = 3,
    secret_path = 4,
    sword_pickup = 5,
    small_axe_pickup = 6,
    health_pickup = 7,
    player_spawn = 10,
    monster_spawn = 11,
    fire_monster_spawn = 12,
    charge_monster_spawn = 13,
};

pub const Direction = enum(u3) {
    north,
    north_east,
    east,
    south_east,
    south,
    south_west,
    west,
    north_west,

    pub const all = [_]@This(){
        @This().north,
        @This().north_east,
        @This().east,
        @This().south_east,
        @This().south,
        @This().south_west,
        @This().west,
        @This().north_west,
    };

    pub const all_orthogonal = [_]@This(){
        @This().north,
        @This().east,
        @This().south,
        @This().west,
    };
};

pub const Path = StaticList(Location, max_distance);

pub const Location = struct {
    x: i16,
    y: i16,

    pub fn walk(self: @This(), direction: Direction, distance: u8) Location {
        return switch (direction) {
            .north => self.north(distance),
            .north_east => self.north_east(distance),
            .east => self.east(distance),
            .south_east => self.south_east(distance),
            .south => self.south(distance),
            .south_west => self.south_west(distance),
            .west => self.west(distance),
            .north_west => self.north_west(distance),
        };
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn manhattan_to(self: Location, other: Location) u8 {
        var dx = @intCast(i32, other.x) - @intCast(i32, self.x);
        var dy = @intCast(i32, other.y) - @intCast(i32, self.y);

        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;

        return @intCast(u8, dx + dy);
    }

    pub inline fn north(self: Location, distance: u8) Location {
        return Location{ .x = self.x, .y = self.y - distance };
    }

    pub inline fn north_east(self: Location, distance: u8) Location {
        return Location{ .x = self.x + distance, .y = self.y - distance };
    }

    pub inline fn east(self: Location, distance: u8) Location {
        return Location{ .x = self.x + distance, .y = self.y };
    }

    pub inline fn south_east(self: Location, distance: u8) Location {
        return Location{ .x = self.x + distance, .y = self.y + distance };
    }

    pub inline fn south(self: Location, distance: u8) Location {
        return Location{ .x = self.x, .y = self.y + distance };
    }

    pub inline fn south_west(self: Location, distance: u8) Location {
        return Location{ .x = self.x - distance, .y = self.y + distance };
    }

    pub inline fn west(self: Location, distance: u8) Location {
        return Location{ .x = self.x - distance, .y = self.y };
    }

    pub inline fn north_west(self: Location, distance: u8) Location {
        return Location{ .x = self.x - distance, .y = self.y - distance };
    }
};

pub const LineOfSightResult = struct {
    path: Path = .{},
    hit_target: bool = false,
};

pub fn check_line_of_sight(
    comptime MapType: type,
    world_map: MapType,
    origin: Location,
    target: Location,
) LineOfSightResult {
    var plotter = struct {
        world_map: MapType,
        target: Location,
        result: LineOfSightResult = .{},

        pub fn plot(self: *@This(), x: i32, y: i32) bool {
            const location = Location{ .x = @intCast(u8, x), .y = @intCast(u8, y) };

            switch (map_get_tile_kind(self.world_map, location)) {
                .wall, .breakable_wall => return false,
                else => {},
            }

            self.result.path.push(location) catch {
                return false;
            };

            if (location.eql(self.target)) {
                self.result.hit_target = true;
                return false;
            }

            return true;
        }
    }{
        .world_map = world_map,
        .target = target,
    };

    bresenham_line(
        @intCast(i32, origin.x),
        @intCast(i32, origin.y),
        @intCast(i32, target.x),
        @intCast(i32, target.y),
        &plotter,
    );

    return plotter.result;
}

pub fn map_set_tile(world: anytype, location: Location, value: u4) void {
    //w4.trace("map_set_tile");

    if (location.x < 0 or location.x > size_x or location.y < 0 or location.y > size_y) {
        return;
    }

    world[@intCast(usize, location.y)][@intCast(usize, location.x)] = value;
}

pub fn map_get_tile(world: anytype, location: Location) u4 {
    //w4.trace("map_get_tile");

    if (location.x < 0 or location.x > size_x or location.y < 0 or location.y > size_y) {
        return 0;
    }

    return world[@intCast(usize, location.y)][@intCast(usize, location.x)];
}

pub fn map_get_tile_kind(world: anytype, location: Location) MapTileKind {
    //w4.trace("map_get_tile_kind");

    if (location.x < 0 or location.x > size_x or location.y < 0 or location.y > size_y) {
        return .wall;
    }

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
