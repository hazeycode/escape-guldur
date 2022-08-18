const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const sprites = @import("sprites.zig");
const world = @import("world.zig");

const bresenham_line = @import("bresenham.zig").line;

const world_tile_width_px = 8;
const world_size = w4.SCREEN_SIZE / world_tile_width_px;
const max_world_distance = sqrt(world_size * world_size + world_size * world_size);

const WorldMap = world.Map(world_size, world_size);

const debug_drawing = true;

const Entity = struct {
    location: world.Location,
    health: i8,
};

pub const State = struct {
    world: WorldMap,
    player: Entity,
    monsters: [8]Entity,
    monster_count: u8,
    turn: u8,
};

const ScreenPosition = struct { x: i32, y: i32 };

fn world_to_screen(world_pos: world.Location) ScreenPosition {
    return .{
        .x = world_pos.x * world_tile_width_px,
        .y = world_pos.y * world_tile_width_px,
    };
}

const LineOfSightResult = struct {
    path: [max_world_distance]world.Location = undefined,
    path_len: usize = 0,
    hit_target: bool = false,
};

fn check_line_of_sight(
    world_map: WorldMap,
    origin: world.Location,
    target: world.Location,
) LineOfSightResult {
    var plotter = struct {
        world_map: WorldMap,
        target: world.Location,
        result: LineOfSightResult = .{},

        pub fn plot(self: *@This(), x: i32, y: i32) bool {
            const pos = world.Location{ .x = @intCast(u8, x), .y = @intCast(u8, y) };

            self.result.path[self.result.path_len] = pos;
            self.result.path_len += 1;

            if (pos.eql(self.target)) {
                self.result.hit_target = true;
                return false;
            }

            if (world.map_get_tile(self.world_map, pos) == .wall) {
                return false;
            } else {
                return true;
            }
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

fn try_move(state: *State, pos: world.Location) void {
    switch (world.map_get_tile(state.world, pos)) {
        .wall => {}, // you shall not pass!
        else => {
            var monster_killed = false;
            for (state.monsters) |*monster| {
                if (monster.health > 0 and
                    monster.location.eql(pos))
                {
                    w4.tone(
                        880 | (440 << 16),
                        2 | (4 << 8),
                        100,
                        w4.TONE_PULSE1,
                    );
                    monster.health = 0;
                    monster_killed = true;
                }
            }
            if (monster_killed == false) {
                state.player.location = pos;
                w4.tone(220, 2 | (4 << 8), 80, w4.TONE_TRIANGLE);
            }

            end_move(state);
        },
    }
}

fn end_move(state: *State) void {
    w4.trace("end_move...");
    defer w4.trace("");

    for (state.monsters) |*monster, i| {
        if (monster.health > 0) find_move: {
            w4.trace("monster: begin move...");
            defer w4.trace("monster: move complete");

            const d = monster.location.manhattan_to(state.player.location);

            if (d == 1) {
                w4.trace("monster: hit player!");
                w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
                state.player.health -= 1;
                break :find_move;
            } else if (d < 10) {
                const res = check_line_of_sight(state.world, monster.location, state.player.location);
                if (res.hit_target) {
                    std.debug.assert(res.path.len > 1);

                    w4.trace("monster: chase player!");

                    { // find best tile to get closer to player
                        var min_dist = d;
                        const possible: [4]world.Location = .{
                            monster.location.north(),
                            monster.location.east(),
                            monster.location.south(),
                            monster.location.west(),
                        };
                        for (&possible) |new_location| {
                            if (world.map_get_tile(state.world, new_location) != .wall and
                                check_occupied: {
                                for (state.monsters) |*other, j| {
                                    if (i == j) continue;
                                    if (other.location.eql(new_location)) {
                                        break :check_occupied true;
                                    }
                                }
                                break :check_occupied false;
                            } == false) {
                                const dist = new_location.manhattan_to(state.player.location);
                                if (dist < min_dist) {
                                    monster.location = new_location;
                                    min_dist = dist;
                                } else if (dist == min_dist) {
                                    if (state.player.location.x != new_location.x) {
                                        monster.location = new_location;
                                    }
                                }
                            }
                        }
                    }
                    break :find_move;
                }
            }

            while (true) { // find walkable adjacent tile (random walk)
                w4.trace("monster: walk around randomly");
                const new_location = switch (@intToEnum(
                    world.Direction,
                    @mod(rng.random().int(u8), 4),
                )) {
                    .north => monster.location.north(),
                    .east => monster.location.east(),
                    .south => monster.location.south(),
                    .west => monster.location.west(),
                };
                if (world.map_get_tile(state.world, new_location) != .wall and
                    check_occupied: {
                    for (state.monsters) |*other, j| {
                        if (i == j) continue;
                        if (other.location.eql(new_location)) {
                            break :check_occupied true;
                        }
                    }
                    break :check_occupied false;
                } == false) {
                    monster.location = new_location;
                    break :find_move;
                }
            }
        }
    }
}

pub fn reset(state: *State) void {
    w4.trace("reset");

    state.world = @bitCast(WorldMap, [_]u8{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 3, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    });

    for (state.monsters) |*monster| monster.* = .{
        .location = .{
            .x = 0,
            .y = 0,
        },
        .health = 0,
    };

    state.monster_count = 0;

    var pos: world.Location = .{ .x = 0, .y = 0 };
    while (pos.x < world_size) : (pos.x += 1) {
        while (pos.y < world_size) : (pos.y += 1) {
            switch (world.map_get_tile(state.world, pos)) {
                .player_spawn => {
                    state.player = .{
                        .location = pos,
                        .health = 3,
                    };
                },
                .monster_spawn => {
                    state.monsters[state.monster_count] = .{
                        .location = pos,
                        .health = 1,
                    };
                    state.monster_count += 1;
                },
                else => {},
            }
        }
        pos.y = 0;
    }

    state.turn = 0;
}

pub fn update(pressed: u8, state: *State) bool {
    if (state.player.health <= 0) return true;

    if (pressed & w4.BUTTON_UP != 0) {
        try_move(state, state.player.location.north());
    } else if (pressed & w4.BUTTON_RIGHT != 0) {
        try_move(state, state.player.location.east());
    } else if (pressed & w4.BUTTON_DOWN != 0) {
        try_move(state, state.player.location.south());
    } else if (pressed & w4.BUTTON_LEFT != 0) {
        try_move(state, state.player.location.west());
    }

    { // draw world
        var pos: world.Location = .{ .x = 0, .y = 0 };
        while (pos.x < world_size) : (pos.x += 1) {
            pos.y = 0;
            while (pos.y < world_size) : (pos.y += 1) {
                const screen_pos = world_to_screen(pos);
                switch (world.map_get_tile(state.world, pos)) {
                    .wall => w4.blit(
                        &sprites.wall,
                        screen_pos.x,
                        screen_pos.y,
                        8,
                        8,
                        w4.BLIT_1BPP,
                    ),
                    else => {},
                }
            }
        }
    }

    { // draw monsters
        for (state.monsters) |*monster| {
            const screen_pos = world_to_screen(monster.location);
            if (monster.health > 0) {
                w4.blit(
                    &sprites.monster,
                    screen_pos.x,
                    screen_pos.y,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }
    }

    { // draw player sprite
        const screen_pos = world_to_screen(state.player.location);
        w4.blit(
            &sprites.player,
            screen_pos.x,
            screen_pos.y,
            8,
            8,
            w4.BLIT_1BPP,
        );
    }

    return false;
}
