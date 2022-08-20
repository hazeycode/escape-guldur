const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const sprites = @import("sprites.zig");
const world = @import("world.zig");

const bresenham_line = @import("bresenham.zig").line;

const world_tile_width_px = 8;
const world_size_x = w4.SCREEN_SIZE / world_tile_width_px;
const world_size_y = w4.SCREEN_SIZE / world_tile_width_px;
const max_world_distance = 32;

const max_player_health = 5;

const WorldMap = world.Map(world_size_x, world_size_y);

const Path = struct {
    locations: [max_world_distance]world.Location = undefined,
    len: usize = 0,
};

const Entity = struct {
    location: world.Location,
    health: i8,
};

const Player = struct {
    entity: Entity,
    items: u8 = 0,
    active_item: u8 = 0,

    pub const Item = enum(u4) { sword, small_axe };

    pub inline fn has_item(self: Player, item: Item) bool {
        return self.items & (@as(u8, 1) << @intCast(u3, @enumToInt(item)));
    }

    pub inline fn give_item(self: *Player, item: Item) void {
        self.items |= (@as(u8, 1) << @intCast(u3, @enumToInt(item)));
    }

    pub inline fn remove_item(self: *Player, item: Item) void {
        self.items &= ~(@as(u8, 1) << @intCast(u3, @enumToInt(item)));
    }
};

const Enemy = struct {
    entity: Entity,
    path: Path = .{},
    cooldown: u8 = 0,
};

const Pickup = struct {
    entity: Entity,
    kind: enum { health, sword, small_axe },
};

pub const State = struct {
    world: WorldMap,
    world_light_map: WorldMap,
    player: Player,
    monsters: [16]Enemy,
    fire_monsters: [8]Enemy,
    fire: [16]Enemy,
    pickups: [8]Pickup,
    monster_count: u8,
    fire_monster_count: u8,
    fire_count: u8,
    pickup_count: u8,
    turn: u8 = 0,
    level: u8 = 0,

    pub fn reset(self: *@This()) void {
        w4.trace("reset");
        self.player.entity.health = max_player_health;
    }

    pub fn load_level(self: *@This(), level: u8) void {
        w4.trace("load_level");

        self.level = level;
        self.world = levels[level];

        for (self.monsters) |*monster| monster.entity.health = 0;
        self.monster_count = 0;

        for (self.fire_monsters) |*fire_monster| fire_monster.entity.health = 0;
        self.fire_monster_count = 0;

        for (self.fire) |*fire| fire.entity.health = 0;
        self.fire_count = 0;

        for (self.pickups) |*pickup| pickup.entity.health = 0;
        self.pickup_count = 0;

        var location: world.Location = .{ .x = 0, .y = 0 };
        while (location.x < world_size_x) : (location.x += 1) {
            defer location.y = 0;
            while (location.y < world_size_y) : (location.y += 1) {
                switch (world.map_get_tile_kind(self.world, location)) {
                    .player_spawn => {
                        self.player.entity.location = location;
                    },
                    .monster_spawn => {
                        self.monsters[self.monster_count] = .{
                            .entity = .{
                                .location = location,
                                .health = 2,
                            },
                        };
                        self.monster_count += 1;
                    },
                    .fire_monster_spawn => {
                        self.fire_monsters[self.fire_monster_count] = .{
                            .entity = .{
                                .location = location,
                                .health = 3,
                            },
                        };
                        self.fire_monster_count += 1;
                    },
                    .health_pickup => self.spawn_pickup(location, .health),
                    .sword_pickup => self.spawn_pickup(location, .sword),
                    .small_axe_pickup => self.spawn_pickup(location, .small_axe),
                    else => {},
                }
            }
        }

        update_world_lightmap(self);

        self.turn = 0;
    }

    fn spawn_pickup(self: *@This(), location: world.Location, kind: anytype) void {
        self.pickups[self.pickup_count] = .{
            .entity = .{
                .location = location,
                .health = 1,
            },
            .kind = kind,
        };
        self.pickup_count += 1;
    }
};

const ScreenPosition = struct { x: i32, y: i32 };

fn world_to_screen(state: *State, location: world.Location) ScreenPosition {
    const cam_offset = state.player.entity.location;
    return .{
        .x = (location.x - cam_offset.x) * world_tile_width_px + w4.SCREEN_SIZE / 2,
        .y = (location.y - cam_offset.y) * world_tile_width_px + w4.SCREEN_SIZE / 2,
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
        .wall => {
            // you shall not pass!
            return;
        },
        else => {
            var monster_killed = false;
            for (state.monsters) |*monster| {
                if (monster.entity.health > 0 and
                    monster.entity.location.eql(pos))
                {
                    monster.entity.health -= 1;
                    monster_killed = true;
                }
            }
            for (state.fire_monsters) |*fire_monster| {
                if (fire_monster.entity.health > 0 and
                    fire_monster.entity.location.eql(pos))
                {
                    fire_monster.entity.health -= 1;
                    monster_killed = true;
                }
            }

            for (state.pickups) |*pickup| {
                if (pickup.entity.health > 0 and
                    pickup.entity.location.eql(pos))
                {
                    switch (pickup.kind) {
                        .health => state.player.entity.health += 1,
                        .sword => state.player.give_item(.sword),
                        .small_axe => state.player.give_item(.small_axe),
                    }
                    pickup.entity.health = 0;
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
                state.player.entity.location = pos;
                w4.tone(220, 2 | (4 << 8), 80, w4.TONE_TRIANGLE);
            }
        },
    }

    end_move(state);
}

fn try_use_item(_: *State) void {
    w4.trace("use item");
}

fn try_cycle_item(state: *State) void {
    w4.trace("cycle item");

    const max = std.math.maxInt(@TypeOf(state.player.active_item));
    if (state.player.active_item == max - 1) {
        state.player.active_item = max;
    } else {
        state.player.active_item += 1;
    }
}

fn end_move(state: *State) void {
    defer {
        if (state.player.entity.health < 0) state.player.entity.health = 0;
    }

    w4.trace("responding to move...");

    if (world.map_get_tile_kind(state.world, state.player.entity.location) == .door) {
        state.level += 1;
        if (state.level < levels.len) {
            w4.trace("load next level");
            state.load_level(state.level);
        }
        return;
    }

    for (state.fire) |*fire| {
        if (fire.entity.health > 0) {
            move_fire(state, fire);
        }
    }

    for (state.monsters) |*monster| {
        if (monster.entity.health > 0) find_move: {
            w4.trace("monster: begin move...");
            defer w4.trace("monster: move complete");

            const d = monster.entity.location.manhattan_to(state.player.entity.location);

            if (d == 1) {
                w4.trace("monster: hit player!");
                w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
                state.player.entity.health -= 2;
                break :find_move;
            } else if (d < 10) {
                const res = check_line_of_sight(state.world, monster.entity.location, state.player.entity.location);
                if (res.hit_target) {
                    std.debug.assert(res.path.len > 1);

                    w4.trace("monster: chase player!");

                    { // find best tile to get closer to player
                        var min_dist = d;
                        const possible: [4]world.Location = .{
                            monster.entity.location.north(),
                            monster.entity.location.east(),
                            monster.entity.location.south(),
                            monster.entity.location.west(),
                        };
                        for (&possible) |new_location| {
                            if (test_walkable(state, new_location)) {
                                const dist = new_location.manhattan_to(state.player.entity.location);
                                if (dist < min_dist) {
                                    monster.entity.location = new_location;
                                    min_dist = dist;
                                } else if (dist == min_dist) {
                                    if (state.player.entity.location.x != new_location.x) {
                                        monster.entity.location = new_location;
                                    }
                                }
                            }
                        }
                    }
                    break :find_move;
                }
            }

            w4.trace("monster: random walk");
            random_walk(state, &monster.entity);
        }
    }

    for (state.fire_monsters) |*fire_monster| {
        if (fire_monster.cooldown > 0) {
            fire_monster.cooldown -= 1;
        } else if (fire_monster.entity.health > 0) find_move: {
            w4.trace("fire_monster: begin move...");
            defer w4.trace("fire_monster: move complete");

            const d = fire_monster.entity.location.manhattan_to(state.player.entity.location);

            if (d > 3 and d < 20) {
                const res = check_line_of_sight(
                    state.world,
                    fire_monster.entity.location,
                    state.player.entity.location,
                );
                if (res.hit_target) {
                    w4.trace("fire_monster: spit at player");
                    spawn_fire(state, res.path);
                    break :find_move;
                }
            }

            w4.trace("fire_monster: random walk");
            random_walk(state, &fire_monster.entity);
        }
    }

    update_world_lightmap(state);
}

/// Returns true if the location is not occupied by a blocking tile or blocking entity
fn test_walkable(state: *State, location: world.Location) bool {
    if (world.map_get_tile_kind(state.world, location) == .wall) {
        return false;
    }
    if (state.player.entity.location.eql(location)) {
        return false;
    }
    for (state.monsters) |*other| {
        if (other.entity.location.eql(location)) {
            return false;
        }
    }
    for (state.fire_monsters) |*other| {
        if (other.entity.location.eql(location)) {
            return false;
        }
    }
    return true;
}

fn spawn_fire(state: *State, path: Path) void {
    w4.trace("spawn fire");

    if (state.fire_count < state.fire.len) {
        var new_fire = Enemy{
            .entity = .{
                .location = path.locations[0],
                .health = 1,
            },
        };
        new_fire.path.len = path.len - 1;
        var i: usize = 0;
        while (i < new_fire.path.len - 1) : (i += 1) {
            new_fire.path.locations[i] = path.locations[i + 1];
        }
        state.fire[state.fire_count] = new_fire;
        move_fire(state, &state.fire[state.fire_count]);
        state.fire_count += 1;
    }
}

fn move_fire(state: *State, fire: *Enemy) void {
    w4.trace("move fire");

    if (fire.path.len > 0) {
        var i: usize = 0;
        while (i < fire.path.len - 1) : (i += 1) {
            fire.path.locations[i] = fire.path.locations[i + 1];
        }
        fire.path.len -= 1;

        fire.entity.location = fire.path.locations[0];

        if (fire.entity.location.eql(state.player.entity.location)) {
            w4.trace("fire hit player!");
            w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
            state.player.entity.health -= 1;
        }

        if (world.map_get_tile_kind(state.world, fire.entity.location) != .wall) {
            return;
        }
    }

    fire.entity.health = 0;
    fire.path.len = 0;
    state.fire_count -= 1;
}

/// finds walkable adjacent tile (random walk), remains still if there are none walkable
fn random_walk(state: *State, entity: *Entity) void {
    const north = entity.location.north();
    const east = entity.location.east();
    const south = entity.location.south();
    const west = entity.location.west();

    var random_dir = @intToEnum(world.Direction, @mod(rng.random().int(u8), 3));

    var possible_location = switch (random_dir) {
        .north => north,
        .east => east,
        .south => south,
        .west => west,
    };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (test_walkable(state, possible_location)) {
            entity.location = possible_location;
        }

        random_dir = @intToEnum(world.Direction, @mod(@enumToInt(random_dir) + 1, 3));
    }
}

fn update_world_lightmap(state: *State) void {
    w4.trace("update world lightmap");

    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world_size_x) : (location.x += 1) {
        defer location.y = 0;
        while (location.y < world_size_y) : (location.y += 1) {
            if (location.manhattan_to(state.player.entity.location) > 13) {
                world.map_set_tile(&state.world_light_map, location, @as(u8, 0));
            } else {
                const res = check_line_of_sight(state.world, location, state.player.entity.location);
                world.map_set_tile(
                    &state.world_light_map,
                    location,
                    @as(u4, if (res.hit_target) 1 else 0),
                );
            }
        }
    }
}

pub fn update(global_state: anytype, pressed: u8) void {
    if (@typeInfo(@TypeOf(global_state)) != .Pointer) {
        @compileError("global_state type must be a pointer");
    }

    var state = &global_state.game_state;

    if (state.player.entity.health <= 0) {
        global_state.screen = .dead;
    }

    if (pressed & w4.BUTTON_UP != 0) {
        try_move(state, state.player.entity.location.north());
    } else if (pressed & w4.BUTTON_RIGHT != 0) {
        try_move(state, state.player.entity.location.east());
    } else if (pressed & w4.BUTTON_DOWN != 0) {
        try_move(state, state.player.entity.location.south());
    } else if (pressed & w4.BUTTON_LEFT != 0) {
        try_move(state, state.player.entity.location.west());
    } else if (pressed & w4.BUTTON_1 != 0) {
        try_use_item(state);
    } else if (pressed & w4.BUTTON_2 != 0) {
        try_cycle_item(state);
    }

    if (state.level == levels.len) {
        global_state.screen = .win;
    }

    { // draw world
        var location: world.Location = .{ .x = 0, .y = 0 };
        while (location.x < world_size_x) : (location.x += 1) {
            defer location.y = 0;
            while (location.y < world_size_y) : (location.y += 1) {
                if (world.map_get_tile(state.world_light_map, location) > 0) {
                    switch (world.map_get_tile_kind(state.world, location)) {
                        .wall => {},
                        .door => {
                            w4.DRAW_COLORS.* = 0x03;
                            const screen_pos = world_to_screen(state, location);
                            w4.blit(
                                &sprites.door,
                                screen_pos.x,
                                screen_pos.y,
                                8,
                                8,
                                w4.BLIT_1BPP,
                            );
                        },
                        else => {
                            w4.DRAW_COLORS.* = 0x43;
                            const screen_pos = world_to_screen(state, location);
                            w4.blit(
                                &sprites.floor,
                                screen_pos.x,
                                screen_pos.y,
                                8,
                                8,
                                w4.BLIT_1BPP,
                            );
                        },
                    }
                }
            }
        }
    }

    { // draw pickups
        w4.DRAW_COLORS.* = 0x40;

        for (state.pickups) |*pickup| {
            if (pickup.entity.health > 0 and world.map_get_tile(
                state.world_light_map,
                pickup.entity.location,
            ) > 0) {
                const screen_pos = world_to_screen(state, pickup.entity.location);
                w4.blit(
                    switch (pickup.kind) {
                        .health => unreachable,
                        .sword => &sprites.sword,
                        .small_axe => unreachable,
                    },
                    screen_pos.x,
                    screen_pos.y,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }
    }

    { // draw monsters
        w4.DRAW_COLORS.* = 0x02;

        for (state.monsters) |*monster| {
            if (monster.entity.health > 0 and
                world.map_get_tile(state.world_light_map, monster.entity.location) > 0)
            {
                const screen_pos = world_to_screen(state, monster.entity.location);
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
        for (state.fire_monsters) |*fire_monster| {
            if (fire_monster.entity.health > 0 and
                world.map_get_tile(state.world_light_map, fire_monster.entity.location) > 0)
            {
                const screen_pos = world_to_screen(state, fire_monster.entity.location);
                w4.blit(
                    &sprites.fire_monster,
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
        w4.DRAW_COLORS.* = 0x20;

        const screen_pos = world_to_screen(state, state.player.entity.location);
        w4.blit(
            &sprites.player,
            screen_pos.x,
            screen_pos.y,
            8,
            8,
            w4.BLIT_1BPP,
        );
    }

    { // draw fire
        w4.DRAW_COLORS.* = 0x40;

        for (state.fire) |*fire| {
            if (fire.entity.health > 0 and world.map_get_tile(
                state.world_light_map,
                fire.entity.location,
            ) > 0) {
                const screen_pos = world_to_screen(state, fire.entity.location);
                w4.blit(
                    &sprites.fire,
                    screen_pos.x,
                    screen_pos.y,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }
    }

    { // draw hud
        { // draw health bar
            w4.DRAW_COLORS.* = 0x40;

            std.debug.assert(state.player.entity.health >= 0);
            const health = @intCast(u16, state.player.entity.health);
            const piece_width: u16 = 8;
            const piece_height: u16 = 8;
            const width: u16 = health * piece_width;
            const y = @intCast(i32, w4.SCREEN_SIZE) - piece_height - 1;
            var x: i32 = @intCast(i32, w4.SCREEN_SIZE) / 2 - width / 2;
            var i: usize = 0;
            while (i < state.player.entity.health) : (i += 1) {
                w4.blit(
                    &sprites.heart,
                    x,
                    y,
                    piece_width,
                    piece_height,
                    w4.BLIT_1BPP,
                );
                x += piece_width;
            }
        }
    }
}

const levels: [4]WorldMap = .{
    @bitCast(WorldMap, [_]u4{
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,  0, 0, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,  0, 0, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,  0, 0, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,  0, 0, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 10, 0, 0, 0, 0, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 1, 1, 1, 1, 1,
    }),

    @bitCast(WorldMap, [_]u4{
        1, 1, 1,  1, 3,  1, 1, 1, 1, 1, 1,  1,  1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  0, 12, 0, 1, 1, 1, 1, 0,  0,  0, 1, 1, 0, 0, 0, 0, 1,
        1, 1, 0,  0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 0, 0, 0, 0, 0, 1,
        1, 4, 11, 0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 0,  0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 1, 0, 0, 0, 0, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 0, 0, 0, 5, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 0, 0, 0, 0, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 0, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 0, 0,  0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 0, 0, 0,  0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 0, 0, 0,  0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 4, 0, 0, 0,  0,  0, 0, 0, 4, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 0, 0, 11, 0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 0, 0, 0,  0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 0, 0,  0,  0, 0, 0, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  10, 0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 1,  1,  1, 1, 1, 1, 1, 1, 1, 1,
    }),

    @bitCast(WorldMap, [_]u4{
        1, 1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1, 1, 3,  1, 1,  1, 1, 1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 11, 0, 0, 0, 0, 0,  0, 11, 0, 0, 1, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 1, 1, 1,  1, 0,  0, 0, 1, 1, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 12, 0, 0, 0, 0, 1,  0, 11, 0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 1, 1, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 11, 0, 0,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 1, 1, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 11, 0, 0,  0, 0, 1,
        1, 0, 10, 0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1,
        1, 1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1,
    }),

    @bitCast(WorldMap, [_]u4{
        1, 1, 1,  1,  1, 1, 1, 1,  3, 1,  1, 1,  1,  1, 1,  1, 1,  1, 1, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 11, 0,  0, 0, 0, 0,  0, 11, 0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 1,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 1, 1,  1, 0,  0, 0,  0,  1, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 12, 0, 12, 0, 0,  12, 0, 1,  0, 11, 0, 0, 1,
        1, 0, 0,  11, 0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  1,  1, 1,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 11, 0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  1, 0, 0, 11, 0, 0,  1, 1,  1,  1, 0,  0, 0,  0, 1, 1,
        1, 0, 0,  0,  1, 0, 0, 0,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  1, 0, 0, 0,  0, 0,  0, 11, 0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 11, 0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 0,  0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0, 10, 0, 0,  0,  0, 0,  0, 0,  0, 0, 1,
        1, 1, 1,  1,  1, 1, 1, 1,  1, 1,  1, 1,  1,  1, 1,  1, 1,  1, 1, 1,
    }),
};
