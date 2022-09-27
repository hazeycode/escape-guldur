const std = @import("std");

const util = @import("util.zig");
const StaticList = util.StaticList;

const bresenham_line = @import("bresenham.zig").line;

pub const map_columns = 20;
pub const map_rows = 20;
const max_map_distance = map_columns + map_rows;

pub const map_world_scale = 10;

pub const Position = struct {
    x: i32,
    y: i32,
    z: i32,

    pub inline fn add(self: @This(), other: @This()) @This() {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub inline fn sub(self: @This(), other: @This()) @This() {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn from_map_location(map_location: MapLocation, z: i32) @This() {
        return .{
            .x = map_location.x * map_world_scale + map_world_scale / 2,
            .y = map_location.y * map_world_scale + map_world_scale / 2,
            .z = z,
        };
    }

    pub fn to_map_location(self: @This()) MapLocation {
        return .{
            .x = @intCast(i16, @divTrunc(self.x, map_world_scale)),
            .y = @intCast(i16, @divTrunc(self.y, map_world_scale)),
        };
    }

    pub fn lerp_to(self: @This(), to: @This(), frame: usize, total_frames: usize) @This() {
        var res = self;
        const dt = @intToFloat(f32, frame) / @intToFloat(f32, total_frames);
        res.x += @floatToInt(i32, @intToFloat(f32, to.x - self.x) * dt);
        res.y += @floatToInt(i32, @intToFloat(f32, to.y - self.y) * dt);
        res.z += @floatToInt(i32, @intToFloat(f32, to.z - self.z) * dt);
        return res;
    }
};

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

pub const Path = StaticList(MapLocation, max_map_distance);

pub const MapLocation = struct {
    x: i16,
    y: i16,

    pub fn walk(self: @This(), direction: Direction, distance: u8) MapLocation {
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

    pub fn manhattan_to(self: MapLocation, other: MapLocation) u8 {
        var dx = @intCast(i32, other.x) - @intCast(i32, self.x);
        var dy = @intCast(i32, other.y) - @intCast(i32, self.y);

        if (dx < 0) dx = -dx;
        if (dy < 0) dy = -dy;

        return @intCast(u8, dx + dy);
    }

    pub inline fn north(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x, .y = self.y - distance };
    }

    pub inline fn north_east(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x + distance, .y = self.y - distance };
    }

    pub inline fn east(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x + distance, .y = self.y };
    }

    pub inline fn south_east(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x + distance, .y = self.y + distance };
    }

    pub inline fn south(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x, .y = self.y + distance };
    }

    pub inline fn south_west(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x - distance, .y = self.y + distance };
    }

    pub inline fn west(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x - distance, .y = self.y };
    }

    pub inline fn north_west(self: MapLocation, distance: u8) MapLocation {
        return MapLocation{ .x = self.x - distance, .y = self.y - distance };
    }
};

pub const LineOfSightResult = struct {
    path: Path = .{},
    hit_target: bool = false,
};

pub fn check_line_of_sight(
    comptime MapType: type,
    world_map: MapType,
    origin: MapLocation,
    target: MapLocation,
) LineOfSightResult {
    var plotter = struct {
        world_map: MapType,
        target: MapLocation,
        result: LineOfSightResult = .{},

        pub fn plot(self: *@This(), x: i32, y: i32) bool {
            const location = MapLocation{ .x = @intCast(u8, x), .y = @intCast(u8, y) };

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

pub fn map_set_tile(world: anytype, location: MapLocation, value: u4) void {
    if (location.x < 0 or location.x > map_columns or location.y < 0 or location.y > map_rows) {
        return;
    }
    world[@intCast(usize, location.y)][@intCast(usize, location.x)] = value;
}

pub fn map_get_tile(world: anytype, location: MapLocation) u4 {
    if (location.x < 0 or location.x > map_columns or location.y < 0 or location.y > map_rows) {
        return 0;
    }
    return world[@intCast(usize, location.y)][@intCast(usize, location.x)];
}

pub fn map_get_tile_kind(world: anytype, location: MapLocation) MapTileKind {
    if (location.x < 0 or location.x > map_columns or location.y < 0 or location.y > map_rows) {
        return .wall;
    }
    return @intToEnum(
        MapTileKind,
        world[@intCast(usize, location.y)][@intCast(usize, location.x)],
    );
}

const testing = std.testing;

test {
    _ = testing.refAllDecls(@This());
}

test "world.MapLocation.manhattan_to" {
    {
        const a = MapLocation{ .x = 5, .y = 16 };
        const b = MapLocation{ .x = 11, .y = 10 };
        try testing.expectEqual(@as(i16, 12), a.manhattan_to(b));
    }
    {
        const a = MapLocation{ .x = 25, .y = 11 };
        const b = MapLocation{ .x = 13, .y = 5 };
        try testing.expectEqual(@as(i16, 18), a.manhattan_to(b));
    }
    {
        const a = MapLocation{ .x = 9, .y = 9 };
        const b = MapLocation{ .x = 3, .y = 18 };
        try testing.expectEqual(@as(i16, 15), a.manhattan_to(b));
    }
    {
        const a = MapLocation{ .x = 0, .y = 10 };
        const b = MapLocation{ .x = 12, .y = 17 };
        try testing.expectEqual(@as(i16, 19), a.manhattan_to(b));
    }
}
