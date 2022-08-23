const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const gfx = @import("gfx.zig");
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

    pub fn has_item(self: Player, item: Item) bool {
        return (self.items & (@as(u8, 1) << @intCast(u3, @enumToInt(item)))) > 0;
    }

    pub fn give_item(self: *Player, item: Item) void {
        self.items |= (@as(u8, 1) << @intCast(u3, @enumToInt(item)));
        self.active_item = item;
    }

    pub fn remove_item(self: *Player, item: Item) void {
        self.items &= ~(@as(u8, 1) << @intCast(u3, @enumToInt(item)));
        if (self.active_item == item) {
            self.active_item = if (self.has_item(.sword)) .sword else .fists;
        }
    }

    pub fn get_damage(self: Player) u4 {
        return switch (self.active_item) {
            .fists => 1,
            .sword => 3,
            .small_axe => 2,
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
    // turn: u8 = 0,
    level: u8 = 0,
    camera_location: world.Location,
    action_target: u8 = 0,
    action_targets: [16]world.Location,
    action_target_count: u8 = 0,
    world_map: WorldMap,
    world_vis_map: WorldMap,
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
        // self.turn = 0;
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
        self.world_map = levels[level];

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
                switch (world.map_get_tile_kind(self.world_map, location)) {
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

        // self.turn = 0;
    }

    fn spawn_pickup(self: *@This(), location: world.Location, kind: anytype) void {
        w4.trace("spawn pickup");

        for (self.pickups) |*pickup| {
            if (pickup.entity.health == 0) {
                pickup.entity = .{
                    .location = location,
                    .health = 1,
                };
                pickup.kind = kind;
                return;
            }
        }
    }
};

fn try_move(state: *State, location: world.Location) void {
    switch (world.map_get_tile_kind(state.world_map, location)) {
        .wall => {
            // you shall not pass!
            return;
        },
        else => find_move: {
            for (state.fire) |*fire| {
                if (fire.entity.health > 0 and
                    fire.entity.location.eql(location))
                {
                    state.player.entity.health -= 1;
                    sfx.receive_damage();
                    commit_move(state);
                    break :find_move;
                }
            }

            if (try_hit_enemy(state, location)) {
                break :find_move;
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

                    sfx.pickup();

                    state.player.entity.location = location;

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

fn try_hit_enemy(state: *State, location: world.Location) bool {
    for (state.monsters) |*monster| {
        if (monster.entity.health > 0 and
            monster.entity.location.eql(location))
        {
            monster.entity.health -= state.player.get_damage();
            sfx.deal_damage();
            commit_move(state);
            return true;
        }
    }

    for (state.fire_monsters) |*fire_monster| {
        if (fire_monster.entity.health > 0 and
            fire_monster.entity.location.eql(location))
        {
            fire_monster.entity.health -= state.player.get_damage();
            sfx.deal_damage();
            commit_move(state);
            return true;
        }
    }

    return false;
}

fn try_cycle_item(state: *State) void {
    w4.trace("cycle item");

    sfx.walk();

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
                if (world.map_get_tile_kind(state.world_map, location) != .wall) {
                    for (state.monsters) |*monster| {
                        if (monster.entity.health > 0 and monster.entity.location.eql(location)) {
                            state.action_targets[state.action_target_count] = monster.entity.location;
                            state.action_target_count += 1;
                        }
                    }
                    for (state.fire_monsters) |*monster| {
                        if (monster.entity.health > 0 and monster.entity.location.eql(location)) {
                            state.action_targets[state.action_target_count] = monster.entity.location;
                            state.action_target_count += 1;
                        }
                    }
                }
            }
        },
        .small_axe => { // ranged attack
            for (state.monsters) |*monster| {
                if (monster.entity.health > 0) {
                    if (test_can_ranged_attack(state, monster.entity.location)) {
                        state.action_targets[state.action_target_count] = monster.entity.location;
                        state.action_target_count += 1;
                    }
                }
            }
            for (state.fire_monsters) |*monster| {
                if (monster.entity.health > 0) {
                    if (test_can_ranged_attack(state, monster.entity.location)) {
                        state.action_targets[state.action_target_count] = monster.entity.location;
                        state.action_target_count += 1;
                    }
                }
            }
        },
    }
}

fn test_can_ranged_attack(state: *State, location: world.Location) bool {
    const d = state.player.entity.location.manhattan_to(location);
    if (d < 11) {
        const res = world.check_line_of_sight(
            WorldMap,
            state.world_map,
            state.player.entity.location,
            location,
        );
        if (res.hit_target) {
            return true;
        }
    }
    return false;
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

        // TODO: animate response to move before state change
        state.turn_state = .complete;
    }

    if (world.map_get_tile_kind(state.world_map, state.player.entity.location) == .door) {
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

            var dx = state.player.entity.location.x - monster.entity.location.x;
            var dy = state.player.entity.location.y - monster.entity.location.y;
            const manhattan_dist = @intCast(u8, (if (dx < 0) -dx else dx) + if (dy < 0) -dy else dy);

            if (manhattan_dist == 1) {
                w4.trace("monster: hit player!");
                sfx.receive_damage();
                state.player.entity.health -= 2;
                break :find_move;
            } else if (manhattan_dist <= 3) {
                w4.trace("monster: approach player");

                var possible_location = monster.entity.location;

                if (dx == 0 or dy == 0) {
                    w4.trace("monster: orthogonal, step closer");
                    if (dx != 0) {
                        possible_location.x += @divTrunc(dx, dx);
                    } else if (dy != 0) {
                        possible_location.y += @divTrunc(dy, dy);
                    }
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
                    state.world_map,
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
                    state.world_map,
                    fire_monster.entity.location,
                    state.player.entity.location,
                );
                if (res.hit_target) {
                    w4.trace("fire_monster: spit at player");
                    spawn_fire(state, res.path);
                    fire_monster.cooldown = 1;
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
    w4.trace("test location walkable...");

    const kind = world.map_get_tile_kind(state.world_map, location);

    var walkable = switch (kind) {
        .wall, .locked_door => false,
        else => true,
    };

    if (state.player.entity.health > 0 and state.player.entity.location.eql(location)) {
        walkable = false;
    }

    for (state.monsters) |*other| {
        if (other.entity.health > 0 and other.entity.location.eql(location)) {
            walkable = false;
        }
    }
    for (state.fire_monsters) |*other| {
        if (other.entity.health > 0 and other.entity.location.eql(location)) {
            walkable = false;
        }
    }

    for (state.pickups) |*other| {
        if (other.entity.health > 0 and other.entity.location.eql(location)) {
            walkable = false;
        }
    }

    if (walkable) w4.trace("is walkable") else w4.trace("is NOT walkable");

    return walkable;
}

fn spawn_fire(state: *State, path: world.Path) void {
    w4.trace("spawn fire");

    if (state.fire_count < state.fire.len) {
        var new_fire = Enemy{
            .entity = .{
                .location = path.locations[0],
                .health = 1,
            },
        };
        new_fire.path.length = if (path.length <= 1) 0 else path.length - 1;
        if (new_fire.path.length > 0) {
            std.mem.copy(world.Location, new_fire.path.locations[0..], path.locations[1..]);
            state.fire[state.fire_count] = new_fire;
        }
        state.fire_count += 1;
    }
}

fn update_fire(state: *State, fire: *Enemy) void {
    w4.trace("update fire");

    if (fire.path.length > 1) {
        std.mem.copy(world.Location, fire.path.locations[0..], fire.path.locations[1..]);
    }
    if (fire.path.length > 0) {
        w4.trace("fire walk path");

        fire.entity.location = fire.path.locations[0];
        fire.path.length -= 1;

        if (world.map_get_tile_kind(state.world_map, fire.entity.location) != .wall) {
            if (fire.entity.location.eql(state.player.entity.location)) {
                w4.trace("fire hit player!");
                sfx.receive_damage();
                state.player.entity.health -= 1;
            }
        }

        return;
    }

    fire.entity.health = 0;
    fire.path.length = 0;
    state.fire_count -= 1;

    w4.trace("fire extinguished");
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
            if (world.map_get_tile_kind(state.world_map, location) == .door) {
                world.map_set_tile(&state.world_vis_map, location, 1);
                continue;
            }

            if (location.manhattan_to(state.player.entity.location) > 13) {
                world.map_set_tile(&state.world_vis_map, location, @as(u8, 0));
            } else {
                const res = world.check_line_of_sight(
                    WorldMap,
                    state.world_map,
                    location,
                    state.player.entity.location,
                );
                world.map_set_tile(
                    &state.world_vis_map,
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

    if (state.level == levels.len) {
        global_state.screen = .win;
        return;
    }

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
                    w4.trace("commit action");
                    const target_location = state.action_targets[state.action_target];
                    switch (state.player.active_item) {
                        .fists, .sword => try_move(state, target_location),
                        .small_axe => if (try_hit_enemy(state, target_location)) {
                            state.player.remove_item(.small_axe);
                            state.spawn_pickup(target_location, .small_axe);
                        },
                    }
                }
            } else if (pressed & w4.BUTTON_2 != 0) {
                cancel_aim(state);
            } else if (state.action_target_count > 0) {
                if (pressed & w4.BUTTON_UP > 0 or pressed & w4.BUTTON_RIGHT > 0) {
                    sfx.walk();
                    state.action_target = if (state.action_target == state.action_target_count - 1) 0 else state.action_target + 1;
                } else if (pressed & w4.BUTTON_DOWN > 0 or pressed & w4.BUTTON_LEFT > 0) {
                    sfx.walk();
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
            // state.turn += 1;
            state.turn_state = .ready;
        },
    }

    // update camera location
    state.camera_location = state.player.entity.location;
    if (state.turn_state == .aim and state.action_target_count > 0) {
        state.camera_location = state.action_targets[state.action_target];
    }

    gfx.draw_world(state);
    gfx.draw_enemies(state);
    gfx.draw_pickups(state);
    gfx.draw_player(state);
    gfx.draw_fire(state);
    gfx.draw_hud(state);
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
        1, 1, 0,  0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 0, 0, 6, 0, 0, 1,
        1, 4, 11, 0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 0,  0, 0,  0, 0, 0, 0, 0, 0,  0,  0, 0, 1, 0, 0, 0, 0, 1,
        1, 1, 1,  1, 1,  1, 1, 1, 1, 1, 0,  0,  0, 1, 1, 0, 0, 0, 0, 1,
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
        1, 1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1, 1, 3,  1, 1,  1, 1,  1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 11, 0, 0, 0, 0, 0,  0, 11, 0, 0, 1, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 1, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 1, 1, 1,  1, 0,  0, 0, 1, 1, 1,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 12, 0, 0, 0, 0, 1,  0, 11, 0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 1,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 1, 1, 1,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 11, 0, 0,  1, 1, 1, 1, 1,  1, 1,  1, 1,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 0, 0, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0,  1,
        1, 0, 0,  0, 1, 1, 1, 0,  0, 12, 0, 0, 0, 0, 0,  0, 0,  0, 11, 1,
        1, 0, 0,  0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 11, 0, 0,  0, 0,  1,
        1, 0, 10, 0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  5, 0,  1,
        1, 0, 0,  0, 0, 0, 1, 0,  0, 0,  0, 0, 0, 0, 0,  0, 0,  0, 0,  1,
        1, 1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1, 1, 1, 1,  1, 1,  1, 1,  1,
    }),

    @bitCast(WorldMap, [_]u4{
        1, 1, 1,  1,  1, 1, 1, 1,  1,  3,  1, 1,  1,  1, 1,  1, 1,  1,  1, 1,
        1, 0, 0,  0,  0, 0, 0, 1,  0,  0,  0, 1,  1,  1, 11, 0, 0,  0,  0, 1,
        1, 0, 11, 0,  0, 0, 0, 1,  12, 11, 0, 1,  1,  1, 0,  0, 0,  12, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 1,  0,  1,  0, 1,  1,  1, 0,  0, 1,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 1, 1,  0,  0,  0, 0,  0,  0, 1,  1, 1,  0,  0, 1,
        1, 0, 12, 0,  0, 0, 0, 1,  0,  0,  0, 0,  0,  0, 1,  1, 1,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 1,  1,  1,  1, 1,  1,  0, 1,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 12, 0,  12, 0, 0,  12, 0, 1,  0, 11, 0,  0, 1,
        1, 0, 0,  11, 0, 0, 0, 0,  0,  0,  0, 0,  0,  0, 1,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  0,  0, 0,  1,  1, 1,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  11, 0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  0,  0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  1, 0, 0, 11, 0,  0,  1, 1,  1,  1, 0,  0, 0,  1,  1, 1,
        1, 0, 0,  0,  1, 0, 0, 0,  0,  0,  0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  1, 0, 0, 0,  0,  0,  0, 11, 0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 11, 0,  0, 0, 0, 0,  0,  0,  0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  0,  0, 0,  0,  0, 11, 0, 0,  12, 0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  0,  0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 0, 0,  0,  0, 0, 0, 0,  0,  10, 0, 0,  0,  0, 0,  0, 0,  0,  0, 1,
        1, 1, 1,  1,  1, 1, 1, 1,  1,  1,  1, 1,  1,  1, 1,  1, 1,  1,  1, 1,
    }),
};
