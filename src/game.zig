const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const sfx = @import("sfx.zig");
const sprites = @import("sprites.zig");
const world = @import("world.zig");

const max_player_health = 5;

const WorldMap = world.Map(world.size_x, world.size_y);

const Entity = struct {
    location: world.Location,
    health: i8,
};

const Player = struct {
    entity: Entity,
    items: u8,
    active_item: Item,

    pub const Item = enum(u8) { fists, sword, small_axe };

    pub inline fn has_item(self: Player, item: Item) bool {
        return (self.items & (@as(u8, 1) << @intCast(u3, @enumToInt(item)))) > 0;
    }

    pub inline fn give_item(self: *Player, item: Item) void {
        self.items |= (@as(u8, 1) << @intCast(u3, @enumToInt(item)));
        self.active_item = item;
    }

    pub inline fn remove_item(self: *Player, item: Item) void {
        self.items &= ~(@as(u8, 1) << @intCast(u3, @enumToInt(item)));
        if (self.active_item == item) {
            self.active_item = .fists;
        }
    }

    pub inline fn get_damage(self: Player) u4 {
        return switch (self.active_item) {
            .fists => 1,
            .sword => 2,
            .small_axe => 1,
        };
    }
};

const Enemy = struct {
    entity: Entity,
    path: world.Path = .{},
    cooldown: u8 = 0,
};

const Pickup = struct {
    entity: Entity,
    kind: enum { health, sword, small_axe },
};

pub const State = struct {
    turn_state: enum { ready, aim, response, complete } = .ready,
    turn: u8 = 0,
    level: u8 = 0,
    action_target: u8 = 0,
    action_targets: [16]world.Location,
    action_target_count: u8 = 0,
    world: WorldMap,
    world_light_map: WorldMap,
    player: Player,
    monsters: [16]Enemy,
    fire_monsters: [8]Enemy,
    fire: [16]Enemy,
    pickups: [8]Pickup,
    monster_count: u8 = 0,
    fire_monster_count: u8 = 0,
    fire_count: u8 = 0,
    pickup_count: u8 = 0,

    pub fn reset(self: *@This()) void {
        w4.trace("reset");
        self.turn_state = .ready;
        self.turn = 0;
        self.player.entity.health = max_player_health;
        self.player.active_item = .fists;
        self.player.items = 0b1;
        self.action_target_count = 0;
    }

    pub fn load_level(self: *@This(), level: u8) void {
        w4.trace("load_level");

        self.turn_state = .ready;
        self.action_target_count = 0;

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
        while (location.x < world.size_x) : (location.x += 1) {
            defer location.y = 0;
            while (location.y < world.size_y) : (location.y += 1) {
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
    var cam_offset = state.player.entity.location;
    if (state.turn_state == .aim and state.action_target_count > 0) {
        cam_offset = state.action_targets[state.action_target];
    }
    return .{
        .x = (location.x - cam_offset.x) * 8 + w4.SCREEN_SIZE / 2,
        .y = (location.y - cam_offset.y) * 8 + w4.SCREEN_SIZE / 2,
    };
}

fn try_move(state: *State, location: world.Location) void {
    switch (world.map_get_tile_kind(state.world, location)) {
        .wall => {
            // you shall not pass!
            return;
        },
        else => find_move: {
            for (state.monsters) |*monster| {
                if (monster.entity.health > 0 and
                    monster.entity.location.eql(location))
                {
                    monster.entity.health -= state.player.get_damage();
                    sfx.deal_damage();
                    commit_move(state);
                    break :find_move;
                }
            }

            for (state.fire_monsters) |*fire_monster| {
                if (fire_monster.entity.health > 0 and
                    fire_monster.entity.location.eql(location))
                {
                    fire_monster.entity.health -= state.player.get_damage();
                    sfx.deal_damage();
                    commit_move(state);
                    break :find_move;
                }
            }

            for (state.pickups) |*pickup| {
                if (pickup.entity.health > 0 and
                    pickup.entity.location.eql(location))
                {
                    switch (pickup.kind) {
                        .health => state.player.entity.health += 2,
                        .sword => state.player.give_item(.sword),
                        .small_axe => state.player.give_item(.small_axe),
                    }
                    pickup.entity.health = 0;

                    commit_move(state);
                    break :find_move;
                }
            }

            state.player.entity.location = location;
            sfx.walk();
            commit_move(state);
        },
    }
}

fn try_cycle_item(state: *State) void {
    w4.trace("cycle item");

    const T = @TypeOf(state.player.items);
    const max = std.meta.fields(Player.Item).len;
    var item = @enumToInt(state.player.active_item);
    var i: T = 0;
    while (i < max) : (i += 1) {
        item = @mod(item + 1, @as(u8, max));
        if (state.player.has_item(@intToEnum(Player.Item, item))) {
            state.player.active_item = @intToEnum(Player.Item, item);
            break;
        }
        w4.trace("dont possess item");
    }
}

fn find_action_targets(state: *State) void {
    state.action_target_count = 0;

    switch (state.player.active_item) {
        .fists, .sword => { // melee
            for ([_]world.Location{
                state.player.entity.location.north(),
                state.player.entity.location.east(),
                state.player.entity.location.south(),
                state.player.entity.location.west(),
            }) |location| {
                if (world.map_get_tile_kind(state.world, location) != .wall) {
                    state.action_targets[state.action_target_count] = location;
                    state.action_target_count += 1;
                }
            }
        },
        .small_axe => { // ranged attack
        },
    }
}

fn commit_move(state: *State) void {
    w4.trace("commit move");

    // TODO: animate move before state change
    state.turn_state = .response;
}

fn respond_to_move(state: *State) void {
    w4.trace("responding to move...");

    defer {
        if (state.player.entity.health < 0) state.player.entity.health = 0;

        // TODO: animate reponse to move before state change
        state.turn_state = .complete;
    }

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
            update_fire(state, fire);
        }
    }

    for (state.monsters) |*monster| {
        if (monster.entity.health > 0) find_move: {
            w4.trace("monster: begin move...");
            defer w4.trace("monster: move complete");

            var dx = @intCast(i16, state.player.entity.location.x) - @intCast(i16, monster.entity.location.x);
            var dy = @intCast(i16, state.player.entity.location.y) - @intCast(i16, monster.entity.location.y);
            const manhattan_dist = @intCast(u8, (if (dx < 0) -dx else dx) + if (dy < 0) -dy else dy);

            if (manhattan_dist == 1) {
                w4.trace("monster: hit player!");
                w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
                state.player.entity.health -= 2;
                break :find_move;
            } else if (manhattan_dist <= 3) {
                w4.trace("monster: approach player");

                var possible_location = monster.entity.location;

                if (dx == 0 or dy == 0) {
                    w4.trace("monster: orthogonal, step closer");
                    if (dx != 0) possible_location.x += @divTrunc(dx, dx) else if (dy != 0) possible_location.y += @divTrunc(dy, dy);
                } else {
                    w4.trace("monster: on diagonal (roll dice)");
                    switch (rng.random().int(u1)) {
                        0 => possible_location.x += @divTrunc(dx, dx),
                        1 => possible_location.y += @divTrunc(dy, dy),
                    }
                }

                if (test_walkable(state, possible_location)) {
                    monster.entity.location = possible_location;
                    break :find_move;
                }
            } else if (manhattan_dist < 10) {
                const res = world.check_line_of_sight(
                    WorldMap,
                    state.world,
                    monster.entity.location,
                    state.player.entity.location,
                );
                if (res.hit_target) {
                    w4.trace("monster: chase player!");

                    { // find a walkable tile that gets closer to player
                        const possible_locations: [4]world.Location = .{
                            monster.entity.location.north(),
                            monster.entity.location.east(),
                            monster.entity.location.south(),
                            monster.entity.location.west(),
                        };
                        for (&possible_locations) |new_location| {
                            if (test_walkable(state, new_location)) {
                                if (new_location.manhattan_to(state.player.entity.location) < manhattan_dist) {
                                    monster.entity.location = new_location;
                                    break;
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
                const res = world.check_line_of_sight(
                    WorldMap,
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
    w4.trace("test location walkable");

    const kind = world.map_get_tile_kind(state.world, location);
    if (kind == .wall or kind == .locked_door) {
        return false;
    }
    if (state.player.entity.health > 0 and state.player.entity.location.eql(location)) {
        return false;
    }
    for (state.monsters) |*other| {
        if (other.entity.health > 0 and other.entity.location.eql(location)) {
            return false;
        }
    }
    for (state.fire_monsters) |*other| {
        if (other.entity.health > 0 and other.entity.location.eql(location)) {
            return false;
        }
    }
    return true;
}

fn spawn_fire(state: *State, path: world.Path) void {
    w4.trace("spawn fire");
    _ = state;
    _ = path;

    // if (state.fire_count < state.fire.len) {
    //     var new_fire = Enemy{
    //         .entity = .{
    //             .location = path.locations[0],
    //             .health = 1,
    //         },
    //     };
    //     new_fire.path.length = path.length;
    //     var i: usize = 0;
    //     while (i < path.length - 1) : (i += 1) {
    //         new_fire.path.locations[i] = path.locations[i + 1];
    //     }
    //     state.fire[state.fire_count] = new_fire;
    //     update_fire(state, &state.fire[state.fire_count]);
    //     state.fire_count += 1;
    // }
}

fn update_fire(state: *State, fire: *Enemy) void {
    w4.trace("update fire");

    _ = state;
    _ = fire;

    // if (fire.path.length > 0) {
    //     var i: usize = 0;
    //     while (i < fire.path.length - 2) : (i += 1) {
    //         fire.path.locations[i] = fire.path.locations[i + 1];
    //     }
    //     fire.path.length -= 1;

    //     fire.entity.location = fire.path.locations[0];

    //     if (world.map_get_tile_kind(state.world, fire.entity.location) != .wall) {
    //         if (fire.entity.location.eql(state.player.entity.location)) {
    //             w4.trace("fire hit player!");
    //             w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
    //             state.player.entity.health -= 1;
    //         }
    //         return;
    //     }
    // }

    // fire.entity.health = 0;
    // fire.path.length = 0;
    // state.fire_count -= 1;

    // w4.trace("fire extinguished");
}

/// finds walkable adjacent tile or ramains still (random walk)
fn random_walk(state: *State, entity: *Entity) void {
    const north = entity.location.north();
    const east = entity.location.east();
    const south = entity.location.south();
    const west = entity.location.west();

    var location = switch (@intToEnum(world.Direction, rng.random().int(u2))) {
        .north => north,
        .east => east,
        .south => south,
        .west => west,
    };

    if (test_walkable(state, location)) {
        entity.location = location;
    }
}

fn update_world_lightmap(state: *State) void {
    w4.trace("update world lightmap");

    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world.size_x) : (location.x += 1) {
        defer location.y = 0;
        while (location.y < world.size_y) : (location.y += 1) {
            if (location.manhattan_to(state.player.entity.location) > 13) {
                world.map_set_tile(&state.world_light_map, location, @as(u8, 0));
            } else {
                const res = world.check_line_of_sight(
                    WorldMap,
                    state.world,
                    location,
                    state.player.entity.location,
                );
                world.map_set_tile(
                    &state.world_light_map,
                    location,
                    @as(u4, if (res.hit_target) 1 else 0),
                );
            }
        }
    }
}

fn cancel_aim(state: *State) void {
    w4.trace("cancel item");
    state.turn_state = .ready;
}

pub fn update(global_state: anytype, pressed: u8) void {
    if (@typeInfo(@TypeOf(global_state)) != .Pointer) {
        @compileError("global_state type must be a pointer");
    }

    var state = &global_state.game_state;

    switch (state.turn_state) {
        .ready => {
            if (pressed & w4.BUTTON_1 != 0) {
                w4.trace("aim item");
                find_action_targets(state);
                state.action_target = 0;
                state.turn_state = .aim;
            } else if (pressed & w4.BUTTON_2 != 0) {
                try_cycle_item(state);
            } else if (pressed & w4.BUTTON_UP != 0) {
                try_move(state, state.player.entity.location.north());
            } else if (pressed & w4.BUTTON_RIGHT != 0) {
                try_move(state, state.player.entity.location.east());
            } else if (pressed & w4.BUTTON_DOWN != 0) {
                try_move(state, state.player.entity.location.south());
            } else if (pressed & w4.BUTTON_LEFT != 0) {
                try_move(state, state.player.entity.location.west());
            }
        },
        .aim => {
            if (pressed & w4.BUTTON_1 != 0) {
                if (state.action_target_count == 0) {
                    cancel_aim(state);
                } else {
                    w4.trace("use item");
                    try_move(state, state.action_targets[state.action_target]);
                }
            } else if (pressed & w4.BUTTON_2 != 0) {
                cancel_aim(state);
            } else if (state.action_target_count > 0) {
                if (pressed & w4.BUTTON_UP > 0 or pressed & w4.BUTTON_RIGHT > 0) {
                    state.action_target = if (state.action_target == state.action_target_count - 1) 0 else state.action_target + 1;
                } else if (pressed & w4.BUTTON_DOWN > 0 or pressed & w4.BUTTON_LEFT > 0) {
                    state.action_target = if (state.action_target == 0) state.action_target_count - 1 else state.action_target - 1;
                }
            }
        },
        .response => {
            respond_to_move(state);
        },
        .complete => {
            if (state.player.entity.health <= 0) {
                global_state.screen = .dead;
            }
            state.turn += 1;
            state.turn_state = .ready;
        },
    }

    { // draw world

        var location: world.Location = .{ .x = 0, .y = 0 };
        while (location.x < world.size_x) : (location.x += 1) {
            defer location.y = 0;
            while (location.y < world.size_y) : (location.y += 1) {
                if (world.map_get_tile(state.world_light_map, location) > 0) {
                    switch (world.map_get_tile_kind(state.world, location)) {
                        .wall, .locked_door => {},
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
                        .health => &sprites.heart,
                        .sword => &sprites.sword,
                        .small_axe => &sprites.small_axe,
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

    { // draw player
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

    { // draw HUD
        if (state.turn_state == .aim) {
            w4.DRAW_COLORS.* = 0x04;

            w4.text("AIM", 1, w4.SCREEN_SIZE - (8 + 1) * 2);

            var i: usize = 0;
            while (i < state.action_target_count) : (i += 1) {
                w4.DRAW_COLORS.* = 0x40;
                const screen_pos = world_to_screen(state, state.action_targets[i]);
                w4.blit(
                    if (i == state.action_target) &sprites.tile_reticule_active else &sprites.tile_reticule_inactive,
                    screen_pos.x,
                    screen_pos.y,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }

        { // draw health bar
            w4.DRAW_COLORS.* = 0x40;

            const piece_width: u16 = 8;
            const piece_height: u16 = 8;
            if (state.player.entity.health > 0) {
                const width: u16 = @bitCast(u8, state.player.entity.health) * piece_width;
                const y = @intCast(i32, w4.SCREEN_SIZE) - piece_height - 1;
                var x: i32 = @intCast(i32, w4.SCREEN_SIZE) - width - 1;
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

        { // draw active item
            w4.DRAW_COLORS.* = 0x04;
            const str = switch (state.player.active_item) {
                .fists => "FISTS",
                .sword => "SWORD",
                .small_axe => "THROWING AXE",
            };
            w4.text(str, 1, w4.SCREEN_SIZE - 8 - 1);
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
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,  0, 0, 7, 0, 1, 1, 1, 1,
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
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 0, 0, 0, 6, 1,
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
        1, 0, 10, 0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  5, 0, 1,
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
