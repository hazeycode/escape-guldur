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

const Path = struct {
    locations: [max_world_distance]world.Location = undefined,
    len: usize = 0,
};

const Entity = struct {
    location: world.Location,
    path: Path = .{},
    health: i8,
};

pub const State = struct {
    world: WorldMap,
    world_light_map: WorldMap,
    player: Entity,
    monsters: [8]Entity,
    spit_monsters: [8]Entity,
    projectiles: [8]Entity,
    monster_count: u8,
    spit_monster_count: u8,
    projectile_count: u8,
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
    path: Path = .{},
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
            const location = world.Location{ .x = @intCast(u8, x), .y = @intCast(u8, y) };

            self.result.path.locations[self.result.path.len] = location;
            self.result.path.len += 1;

            if (location.eql(self.target)) {
                self.result.hit_target = true;
                return false;
            }

            if (world.map_get_tile_kind(self.world_map, location) == .wall) {
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
    switch (world.map_get_tile_kind(state.world, pos)) {
        .wall => {}, // you shall not pass!
        else => {
            var monster_killed = false;
            for (state.monsters) |*monster| {
                if (monster.health > 0 and
                    monster.location.eql(pos))
                {
                    monster.health -= 1;
                    monster_killed = true;
                }
            }
            for (state.spit_monsters) |*spit_monster| {
                if (spit_monster.health > 0 and
                    spit_monster.location.eql(pos))
                {
                    spit_monster.health -= 1;
                    monster_killed = true;
                }
            }

            if (monster_killed) {
                w4.tone(
                    880 | (440 << 16),
                    2 | (4 << 8),
                    100,
                    w4.TONE_PULSE1,
                );
            } else {
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

    for (state.projectiles) |*projectile| {
        if (projectile.health > 0) {
            if (projectile.path.len > 0) {
                projectile.location = projectile.path.locations[0];

                if (projectile.location.eql(state.player.location)) {
                    w4.trace("projectile hit player!");
                    w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
                    state.player.health -= 1;
                }

                projectile.path.len -= 1;
                var i: usize = 0;
                while (i < projectile.path.len) : (i += 1) {
                    projectile.path.locations[i] = projectile.path.locations[i + 1];
                }
            } else {
                projectile.health = 0;
                projectile.path.len = 0;
                state.projectile_count -= 1;
            }
        }
    }

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
                            if (world.map_get_tile_kind(state.world, new_location) != .wall and
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

            w4.trace("monster: walk around randomly");
            random_walk(state, monster);
        }
    }

    for (state.spit_monsters) |*spit_monster| {
        if (spit_monster.health > 0) find_move: {
            w4.trace("spit_monster: begin move...");
            defer w4.trace("spit_monster: move complete");

            const d = spit_monster.location.manhattan_to(state.player.location);

            if (d > 3 and d < 20) {
                const res = check_line_of_sight(state.world, spit_monster.location, state.player.location);
                if (res.hit_target) {
                    w4.trace("spit_monster: spit at player");
                    fire_projectile(state, res.path);
                    break :find_move;
                }
            }

            w4.trace("spit_monster: walk around randomly");
            random_walk(state, spit_monster);
        }
    }

    update_world_lightmap(state);
}

/// finds walkable adjacent tile (random walk), remains still if there are none walkable
fn random_walk(state: *State, entity: *Entity) void {
    const north = entity.location.north();
    const east = entity.location.east();
    const south = entity.location.south();
    const west = entity.location.west();

    var random_dir = @intToEnum(world.Direction, @mod(rng.random().int(u8), 4));

    var possible_location = switch (random_dir) {
        .north => north,
        .east => east,
        .south => south,
        .west => west,
    };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (walkable: {
            if (world.map_get_tile_kind(state.world, possible_location) == .wall) {
                break :walkable false;
            }
            if (&state.player != entity and state.player.location.eql(possible_location)) {
                break :walkable false;
            }
            for (state.monsters) |*other| {
                if (other == entity) continue;
                if (other.location.eql(possible_location)) {
                    break :walkable false;
                }
            }
            for (state.spit_monsters) |*other| {
                if (other == entity) continue;
                if (other.location.eql(possible_location)) {
                    break :walkable false;
                }
            }
            break :walkable true;
        }) {
            entity.location = possible_location;
        }

        random_dir = @intToEnum(world.Direction, @mod(@enumToInt(random_dir) + 1, 4));
    }
}

fn fire_projectile(state: *State, path: Path) void {
    std.debug.assert(path.len > 1);

    if (state.projectile_count < state.projectiles.len) {
        var new_projectile = Entity{
            .location = path.locations[0],
            .health = 1,
        };
        new_projectile.path.len = path.len - 1;
        var i: usize = 0;
        while (i < new_projectile.path.len) : (i += 1) {
            new_projectile.path.locations[i] = path.locations[i + 1];
        }
        state.projectiles[state.projectile_count] = new_projectile;
        state.projectile_count += 1;
    }
}

fn update_world_lightmap(state: *State) void {
    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world_size) : (location.x += 1) {
        location.y = 0;
        while (location.y < world_size) : (location.y += 1) {
            if (location.manhattan_to(state.player.location) > 13) {
                world.map_set_tile(&state.world_light_map, location, @as(u8, 0));
            } else {
                const res = check_line_of_sight(state.world, location, state.player.location);
                world.map_set_tile(
                    &state.world_light_map,
                    location,
                    @as(u8, if (res.hit_target) 1 else 0),
                );
            }
        }
    }
}

pub fn reset(state: *State) void {
    w4.trace("reset");

    state.world = @bitCast(WorldMap, [_]u8{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 0, 0, 0, 1, 0, 3, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 3, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1,
        1, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
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

    for (state.spit_monsters) |*spit_monster| spit_monster.* = .{
        .location = .{
            .x = 0,
            .y = 0,
        },
        .health = 0,
    };
    state.spit_monster_count = 0;

    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world_size) : (location.x += 1) {
        location.y = 0;
        while (location.y < world_size) : (location.y += 1) {
            switch (world.map_get_tile_kind(state.world, location)) {
                .player_spawn => {
                    state.player = .{
                        .location = location,
                        .health = 3,
                    };
                },
                .monster_spawn => {
                    state.monsters[state.monster_count] = .{
                        .location = location,
                        .health = 1,
                    };
                    state.monster_count += 1;
                },
                .spit_monster_spawn => {
                    state.spit_monsters[state.spit_monster_count] = .{
                        .location = location,
                        .health = 2,
                    };
                    state.spit_monster_count += 1;
                },
                else => {},
            }
        }
        location.y = 0;
    }

    update_world_lightmap(state);

    state.projectile_count = 0;

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
        w4.DRAW_COLORS.* = 0x43;

        var location: world.Location = .{ .x = 0, .y = 0 };
        while (location.x < world_size) : (location.x += 1) {
            location.y = 0;
            while (location.y < world_size) : (location.y += 1) {
                if (world.map_get_tile_kind(state.world, location) != .wall) {
                    if (world.map_get_tile(state.world_light_map, location) > 0) {
                        const screen_pos = world_to_screen(location);
                        w4.blit(
                            &sprites.floor,
                            screen_pos.x,
                            screen_pos.y,
                            8,
                            8,
                            w4.BLIT_1BPP,
                        );
                    }
                }
            }
        }
    }

    { // draw monsters
        w4.DRAW_COLORS.* = 0x02;

        for (state.monsters) |*monster| {
            if (monster.health > 0 and
                world.map_get_tile(state.world_light_map, monster.location) > 0)
            {
                const screen_pos = world_to_screen(monster.location);
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
        for (state.spit_monsters) |*spit_monster| {
            if (spit_monster.health > 0 and
                world.map_get_tile(state.world_light_map, spit_monster.location) > 0)
            {
                const screen_pos = world_to_screen(spit_monster.location);
                w4.blit(
                    &sprites.spit_monster,
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
        w4.DRAW_COLORS.* = 0x02;

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

    { // draw projectiles
        w4.DRAW_COLORS.* = 0x04;

        for (state.projectiles) |*projectile| {
            if (projectile.health > 0 and world.map_get_tile(state.world_light_map, projectile.location) > 0) {
                const screen_pos = world_to_screen(projectile.location);
                w4.blit(
                    &sprites.projectile,
                    screen_pos.x,
                    screen_pos.y,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }
    }

    return false;
}
