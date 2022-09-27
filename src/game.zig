const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const platform = @import("platform");
const gfx = @import("gfx");
const sfx = @import("sfx");
const data = @import("data");

const util = @import("util.zig");
const quicksort = util.quicksort;
const StaticList = util.StaticList;

const world = @import("world.zig");
const WorldMap = world.Map(world.map_columns, world.map_rows);

const bresenham_line = @import("bresenham.zig").line;

const level_debug_override: ?u8 = if (false) 3 else null;

const starting_player_health = 5;

var screen: Screen = .title;
var menu_option: u8 = 0;
var player_level_starting_health: [6]i8 = .{ starting_player_health, 0, 0, 0, 0, 0 };
var player_level_starting_items: [6]u8 = .{ 0b1, 0, 0, 0, 0, 0 };
var player_level_starting_active_item: [6]Player.Item = .{.fists} ** 6;
var game_state: State = .{};

pub var input_queue = struct {
    inputs: [8]ButtonPressEvent = undefined,
    count: usize = 0,
    read_cursor: usize = 0,
    write_cursor: usize = 0,

    pub fn push(self: *@This(), input: ButtonPressEvent) void {
        self.inputs[self.write_cursor] = input;
        self.write_cursor = @mod(
            self.write_cursor + 1,
            self.inputs.len,
        );
        if (self.count == self.inputs.len) {
            platform.trace("warning: input queue overflow");
            self.read_cursor = @mod(
                self.read_cursor + 1,
                self.inputs.len,
            );
        } else {
            self.count += 1;
        }
    }

    pub fn pop(self: *@This()) ?ButtonPressEvent {
        if (self.count == 0) {
            return null;
        }
        defer {
            self.read_cursor = @mod(self.read_cursor + 1, self.inputs.len);
            self.count -= 1;
        }
        return self.inputs[self.read_cursor];
    }

    pub fn clear(self: *@This()) void {
        self.count = 0;
        self.read_cursor = 0;
        self.write_cursor = 0;
    }
}{};

pub const ButtonPressEvent = packed struct {
    left: u1,
    right: u1,
    up: u1,
    down: u1,
    action_1: u1,
    action_2: u1,
    _: u2 = 0,

    pub fn any_pressed(self: @This()) bool {
        return (self.left > 0 or
            self.right > 0 or
            self.up > 0 or
            self.down > 0 or
            self.action_1 > 0 or
            self.action_2 > 0);
    }
};

pub const Screen = enum { title, controls, game, reload, win };

const Entity = struct {
    location: world.MapLocation = world.MapLocation{ .x = 0, .y = 0 },
    target_location: world.MapLocation = world.MapLocation{ .x = 0, .y = 0 },
    cooldown: u8 = 0,
    health: i8,
    pending_damage: u4 = 0,
    did_receive_damage: bool = false,
    state: enum { idle, walk, melee_attack, charge } = .idle,
    look_direction: world.Direction,

    pub fn set_location(self: *@This(), location: world.MapLocation) void {
        self.location = location;
        self.target_location = location;
    }
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
};

const Pickup = struct {
    entity: Entity,
    kind: enum { health, sword, small_axe },
};

pub const State = struct {
    // timer: std.time.Timer = undefined,
    game_elapsed_ns: u64 = 0,
    turn_state: enum { ready, aim, commit, response, dead } = .ready,
    turn: u32 = 0,
    level: u8 = 0,
    action_target: u8 = 0,
    action_targets: StaticList(world.MapLocation, 16) = .{},
    world_map: WorldMap = undefined,
    world_vis_map: WorldMap = undefined,
    player: Player = undefined,
    monsters: [16]Enemy = undefined,
    fire_monsters: [8]Enemy = undefined,
    charge_monsters: [4]Enemy = undefined,
    fire: [16]Enemy = undefined,
    pickups: [8]Pickup = undefined,

    pub fn reset(self: *@This()) void {
        platform.trace("reset");
        // self.timer = std.time.Timer.start() catch @panic("Failed to start timer");
        self.turn_state = .ready;
        self.turn = 0;
        self.player.entity.health = starting_player_health;
        self.player.active_item = .fists;
        self.player.items = 0b1;
        self.action_targets.clear();
    }

    pub fn load_level(self: *@This(), level: u8) void {
        platform.trace("load_level");

        input_queue.clear();

        self.turn_state = .ready;
        self.action_targets.clear();

        self.level = level_debug_override orelse level;
        self.world_map = @bitCast(WorldMap, data.levels[self.level]);

        // reset entity pools
        for (self.monsters) |*monster| monster.entity.health = 0;
        for (self.fire_monsters) |*fire_monster| fire_monster.entity.health = 0;
        for (self.charge_monsters) |*charge_monster| charge_monster.entity.health = 0;
        for (self.fire) |*fire| fire.entity.health = 0;
        for (self.pickups) |*pickup| pickup.entity.health = 0;

        // find spawners on level map and spawn things at those locations
        var location: world.MapLocation = .{ .x = 0, .y = 0 };
        while (location.x < world.map_columns) : (location.x += 1) {
            defer location.y = 0;
            while (location.y < world.map_rows) : (location.y += 1) {
                switch (world.map_get_tile_kind(self.world_map, location)) {
                    .player_spawn => {
                        self.player.entity.set_location(location);
                    },
                    .monster_spawn => spawn_enemy(&self.monsters, location, 2),
                    .fire_monster_spawn => spawn_enemy(&self.fire_monsters, location, 3),
                    .charge_monster_spawn => spawn_enemy(&self.charge_monsters, location, 7),
                    .health_pickup => spawn_pickup(self, location, .health),
                    .sword_pickup => spawn_pickup(self, location, .sword),
                    .small_axe_pickup => spawn_pickup(self, location, .small_axe),
                    else => {},
                }
            }
        }

        update_world_visibilty(self);
    }
};

fn spawn_enemy(pool: anytype, location: world.MapLocation, health: u4) void {
    for (pool) |*enemy| {
        if (enemy.entity.health <= 0) {
            enemy.entity.set_location(location);
            enemy.entity.health = health;
            enemy.entity.state = .idle;
            enemy.path.length = 0;
            platform.trace("spawned enemy");
            return;
        }
    }
    platform.trace("warning: enemy not spawned. no free space");
}

fn spawn_pickup(state: *State, location: world.MapLocation, kind: anytype) void {
    for (state.pickups) |*pickup| {
        if (pickup.entity.health <= 0) {
            pickup.entity.set_location(location);
            pickup.entity.health = 1;
            pickup.kind = kind;
            platform.trace("spawned pickup");
            return;
        }
    }
    platform.trace("warning: pickup not spawned. no free space");
}

fn spawn_fire(state: *State, path: *world.Path) void {
    if (path.pop()) |location| {
        for (state.fire) |*fire| {
            if (fire.entity.health <= 0) {
                fire.entity.health = 1;
                fire.entity.state = .walk;
                fire.entity.set_location(location);
                if (path.pop()) |next_location| {
                    fire.entity.target_location = next_location;
                    fire.path.push(next_location) catch {
                        platform.trace("error: failed to queue fire path. no space left");
                        unreachable;
                    };
                }
                while (path.pop()) |future_location| {
                    fire.path.push(future_location) catch {
                        platform.trace("error: failed to queue fire path. no space left");
                        unreachable;
                    };
                }
                platform.trace("spawned fire");
                return;
            }
        }
        platform.trace("warning: fire not spawned. no free space");
    }
    platform.trace("warning: fire not spawned. empty path");
}

fn try_move(state: *State, location: world.MapLocation) void {
    switch (world.map_get_tile_kind(state.world_map, location)) {
        .wall, .breakable_wall => {
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
                state.player.entity.state = .melee_attack;
                commit_move(state);
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
                    break;
                }
            }

            state.player.entity.target_location = location;
            state.player.entity.state = .walk;
            sfx.walk();
            commit_move(state);
        },
    }
}

fn try_hit_enemy(state: *State, location: world.MapLocation) bool {
    if (entities_try_hit(&state.monsters, location) orelse
        entities_try_hit(&state.fire_monsters, location) orelse
        entities_try_hit(&state.charge_monsters, location)) |entity|
    {
        state.player.entity.target_location = entity.location;
        entity.pending_damage += state.player.get_damage();
        return true;
    }
    return false;
}

fn entities_try_hit(entities: anytype, location: world.MapLocation) ?*Entity {
    for (entities) |*e| {
        if (e.entity.health > 0 and
            e.entity.location.eql(location))
        {
            return &e.entity;
        }
    }
    return null;
}

fn entities_test_will_collide(entities: anytype, location: world.MapLocation) ?*Entity {
    for (entities) |*e| {
        if (e.entity.health > 0 and
            e.entity.target_location.eql(location))
        {
            return &e.entity;
        }
    }
    return null;
}

fn try_cycle_item(state: *State) void {
    platform.trace("cycle item");

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
        platform.trace("dont possess item");
    }
}

fn find_action_targets(state: *State) !void {
    state.action_targets.clear();

    switch (state.player.active_item) {
        .fists => try find_melee_targets(state, world.Direction.all_orthogonal),
        .sword => try find_melee_targets(state, world.Direction.all),
        .small_axe => { // ranged attack
            try find_ranged_targets(state, state.monsters);
            try find_ranged_targets(state, state.fire_monsters);
            try find_ranged_targets(state, state.charge_monsters);

            if (state.action_targets.length > 1) {
                const targets = state.action_targets.all();
                var distance_comparitor = struct {
                    state: *State,
                    pub fn compare(
                        self: @This(),
                        a: world.MapLocation,
                        b: world.MapLocation,
                    ) bool {
                        const da = self.state.player.entity.location.manhattan_to(a);
                        const db = self.state.player.entity.location.manhattan_to(b);
                        return da < db;
                    }
                }{ .state = state };
                quicksort(
                    targets,
                    0,
                    @intCast(isize, targets.len - 1),
                    distance_comparitor,
                );
            }
        },
    }
}

fn find_melee_targets(state: *State, directions: anytype) !void {
    for (directions) |dir| {
        const location = state.player.entity.location.walk(dir, 1);
        if (entities_try_hit(&state.monsters, location) orelse
            entities_try_hit(&state.fire_monsters, location) orelse
            entities_try_hit(&state.charge_monsters, location)) |entity|
        {
            try state.action_targets.push(entity.location);
        }
    }
}

fn find_ranged_targets(state: *State, potential_targets: anytype) !void {
    for (potential_targets) |*target| {
        if (target.entity.health > 0) {
            if (test_can_ranged_attack(state, target.entity.location)) {
                try state.action_targets.push(target.entity.location);
            }
        }
    }
}

fn test_can_ranged_attack(state: *State, location: world.MapLocation) bool {
    const d = state.player.entity.location.manhattan_to(location);
    if (d < 9) {
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
    platform.trace("commit move");

    gfx.move_anim_start_frame = gfx.frame_counter;
    state.turn_state = .commit;
}

fn respond_to_move(state: *State) void {
    platform.trace("responding to move...");

    if (world.map_get_tile_kind(state.world_map, state.player.entity.location) == .door) {
        state.level += 1;
        if (state.level < data.levels.len) {
            platform.trace("load next level");
            state.load_level(state.level);
            player_level_starting_health[state.level] = state.player.entity.health;
            player_level_starting_items[state.level] = state.player.items;
            player_level_starting_active_item[state.level] = state.player.active_item;
        }
        return;
    }

    update_enemies(&state.fire, state, update_fire);
    update_enemies(&state.monsters, state, update_monster);
    update_enemies(&state.fire_monsters, state, update_fire_monster);
    update_enemies(&state.charge_monsters, state, update_charge_monster);
}

/// Returns true if the location is not occupied by a blocking tile or blocking entity
fn test_walkable(state: *State, location: world.MapLocation) bool {
    platform.trace("test location walkable...");

    const kind = world.map_get_tile_kind(state.world_map, location);

    switch (kind) {
        .wall, .breakable_wall, .secret_path => {
            return false;
        },
        else => {
            if (state.player.entity.health > 0 and state.player.entity.location.eql(location)) {
                return false;
            }

            if (entities_test_will_collide(&state.monsters, location) orelse
                entities_test_will_collide(&state.fire_monsters, location) orelse
                entities_test_will_collide(&state.charge_monsters, location) orelse
                entities_test_will_collide(&state.pickups, location)) |_|
            {
                return false;
            }
        },
    }

    return true;
}

fn update_enemies(
    enemies: anytype,
    state: *State,
    comptime update_fn: fn (*State, *Enemy) void,
) void {
    for (enemies) |*enemy| {
        if (enemy.entity.cooldown > 0) {
            enemy.entity.cooldown -= 1;
        } else if (enemy.entity.health > 0) {
            update_fn(state, enemy);
        }
    }
}

fn update_monster(state: *State, monster: *Enemy) void {
    platform.trace("monster: begin move...");
    defer platform.trace("monster: move complete");

    var dx = state.player.entity.location.x - monster.entity.location.x;
    var dy = state.player.entity.location.y - monster.entity.location.y;
    const manhattan_dist = @intCast(u8, (if (dx < 0) -dx else dx) + if (dy < 0) -dy else dy);

    if (manhattan_dist == 1) {
        platform.trace("monster: hit player!");
        state.player.entity.pending_damage += 2;
        monster.entity.state = .melee_attack;
        return;
    } else if (manhattan_dist <= 3) {
        platform.trace("monster: approach player");

        var possible_location = monster.entity.location;

        if (dx == 0 or dy == 0) {
            platform.trace("monster: orthogonal, step closer");
            if (dx != 0) {
                possible_location.x += @divTrunc(dx, dx);
            } else if (dy != 0) {
                possible_location.y += @divTrunc(dy, dy);
            }
        } else {
            platform.trace("monster: on diagonal, roll dice");
            switch (rng.random().int(u1)) {
                0 => possible_location.x += @divTrunc(dx, dx),
                1 => possible_location.y += @divTrunc(dy, dy),
            }
        }

        if (test_walkable(state, possible_location)) {
            monster.entity.target_location = possible_location;
            monster.entity.state = .walk;
            return;
        }
    } else if (manhattan_dist < 10) {
        const res = world.check_line_of_sight(
            WorldMap,
            state.world_map,
            monster.entity.location,
            state.player.entity.location,
        );
        if (res.hit_target) {
            platform.trace("monster: chase player!");

            { // find a walkable tile that gets closer to player
                for (world.Direction.all_orthogonal) |dir| {
                    const loc = monster.entity.location.walk(dir, 1);
                    if (test_walkable(state, loc)) {
                        if (loc.manhattan_to(state.player.entity.location) < manhattan_dist) {
                            monster.entity.target_location = loc;
                            monster.entity.state = .walk;
                            break;
                        }
                    }
                }
            }
            return;
        }
    }

    platform.trace("monster: random walk");
    random_walk(state, &monster.entity);
}

fn update_fire_monster(state: *State, monster: *Enemy) void {
    platform.trace("fire_monster: begin move...");
    defer platform.trace("fire_monster: move complete");

    const d = monster.entity.location.manhattan_to(state.player.entity.location);

    if (d > 3 and d < 20) {
        var res = world.check_line_of_sight(
            WorldMap,
            state.world_map,
            monster.entity.location,
            state.player.entity.location,
        );
        if (res.hit_target) {
            platform.trace("fire_monster: spit at player");
            spawn_fire(state, &res.path);
            monster.entity.cooldown = 2;
            return;
        }
    }

    platform.trace("fire_monster: random walk");
    random_walk(state, &monster.entity);
}

fn update_charge_monster(state: *State, monster: *Enemy) void {
    platform.trace("charge_monster: begin move...");
    defer platform.trace("charge_monster: move complete");

    switch (monster.entity.state) {
        .idle, .walk => {
            const vertically_aligned = monster.entity.location.x == state.player.entity.location.x;
            const horizontally_aligned = monster.entity.location.y == state.player.entity.location.y;

            if (vertically_aligned or horizontally_aligned) {
                const d = monster.entity.location.manhattan_to(state.player.entity.location);
                if (d < 13) {
                    platform.trace("charge_monster: spotted player");
                    monster.entity.cooldown = 1;
                    if (vertically_aligned) {
                        const dy = state.player.entity.location.y - monster.entity.location.y;
                        const dir: world.Direction = if (dy < 0) .north else .south;
                        charge_monster_begin_charge(monster, dir, @intCast(u16, if (dy < 0) -dy else dy) + 14);
                    } else if (horizontally_aligned) {
                        const dx = state.player.entity.location.x - monster.entity.location.x;
                        const dir: world.Direction = if (dx < 0) .west else .east;
                        charge_monster_begin_charge(monster, dir, @intCast(u16, if (dx < 0) -dx else dx) + 14);
                    }
                    return;
                }
            }
        },
        .charge => {
            platform.trace("charge_monster: charge");
            if (monster.path.pop()) |next_location| {
                var plotter = struct {
                    game_state: *State,
                    last_passable: ?world.MapLocation = null,
                    hit_impassable: bool = false,
                    player_hit: bool = false,

                    pub fn plot(self: *@This(), x: i32, y: i32) bool {
                        const location = world.MapLocation{ .x = @intCast(u8, x), .y = @intCast(u8, y) };
                        switch (world.map_get_tile_kind(self.game_state.world_map, location)) {
                            .wall => {
                                self.hit_impassable = true;
                                return false;
                            },
                            .breakable_wall => {
                                world.map_set_tile(&self.game_state.world_map, location, 0);
                                sfx.destroy_wall();
                                self.last_passable = location;
                            },
                            else => {
                                self.last_passable = location;
                            },
                        }
                        if (location.eql(self.game_state.player.entity.location) or
                            location.eql(self.game_state.player.entity.target_location))
                        {
                            self.player_hit = true;
                        }

                        return true;
                    }
                }{
                    .game_state = state,
                };

                bresenham_line(
                    @intCast(i32, monster.entity.location.x),
                    @intCast(i32, monster.entity.location.y),
                    @intCast(i32, next_location.x),
                    @intCast(i32, next_location.y),
                    &plotter,
                );

                monster.entity.target_location = plotter.last_passable orelse next_location;

                if (plotter.player_hit) {
                    const player = &state.player;
                    player.entity.pending_damage += 1;
                    // try push player
                    var new_player_location = monster.entity.target_location.walk(monster.entity.look_direction, 1);
                    switch (world.map_get_tile_kind(state.world_map, new_player_location)) {
                        .wall, .breakable_wall => {
                            player.entity.pending_damage += 1;
                            player.entity.state = .idle;
                            const location_behind_monster = monster.entity.target_location.walk(
                                switch (monster.entity.look_direction) {
                                    .north => .south,
                                    .south => .north,
                                    .east => .west,
                                    .west => .east,
                                    else => {
                                        platform.trace("error: invalid charge direction");
                                        unreachable;
                                    },
                                },
                                1,
                            );
                            // TODO(hazeycode): pick a random available location instead of trying in arbitary order?
                            // TODO(hazeycode): test collision with other enemies and push them out of the way?
                            for (world.Direction.all_orthogonal) |possible_dir| {
                                const possible_location = monster.entity.target_location.walk(possible_dir, 1);
                                if (possible_location.eql(location_behind_monster)) {
                                    continue;
                                }
                                if (test_walkable(state, possible_location)) {
                                    new_player_location = possible_location;
                                    player.entity.state = .walk;
                                    break;
                                }
                            }
                            if (player.entity.state == .idle) {
                                player.entity.pending_damage = std.math.maxInt(
                                    @TypeOf(player.entity.pending_damage),
                                );
                            }
                        },
                        else => {},
                    }
                    platform.trace("charge_monster pushed player");
                    player.entity.location = new_player_location;
                }

                if (plotter.hit_impassable) {
                    monster.path.clear();
                    monster.entity.state = .idle;
                    platform.trace("charge_monster: end charge");
                }
            } else {
                monster.path.clear();
                monster.entity.state = .idle;
                platform.trace("charge_monster: end charge");
            }
            return;
        },
        else => {},
    }

    platform.trace("charge_monster: random walk");
    random_walk(state, &monster.entity);
}

fn charge_monster_begin_charge(monster: *Enemy, dir: world.Direction, dist: u16) void {
    platform.trace("charge_monster: begin charge");
    const speed = 2;
    var next_location = monster.entity.location;
    var moved: u16 = 0;
    while (moved <= dist) : (moved += speed) {
        monster.path.push(next_location) catch {
            platform.trace("error: failed to append to path. out of space");
            unreachable;
        };
        next_location = next_location.walk(dir, speed);
    }
    monster.entity.state = .charge;
    monster.entity.look_direction = dir;
}

fn update_fire(state: *State, fire: *Enemy) void {
    if (fire.path.pop()) |next_location| {
        fire.entity.target_location = next_location;
        fire.entity.state = .walk;

        if (fire.entity.target_location.eql(state.player.entity.location)) {
            platform.trace("fire hit player!");
            state.player.entity.pending_damage += 1;
        }
    } else {
        fire.entity.state = .idle;
        fire.entity.health = 0;
        platform.trace("fire extinguished");
    }
}

/// finds walkable adjacent tile or ramains still (random walk)
fn random_walk(state: *State, entity: *Entity) void {
    const ortho_dirs = world.Direction.all_orthogonal;
    const random_index = @mod(rng.random().int(usize), 4);
    const location = entity.location.walk(ortho_dirs[random_index], 1);
    if (test_walkable(state, location)) {
        entity.target_location = location;
        entity.state = .walk;
    } else {
        entity.state = .idle;
    }
}

fn update_world_visibilty(state: *State) void {
    platform.trace("update world visibilty");
    defer platform.trace("world visibilty updated");

    var location: world.MapLocation = .{ .x = 0, .y = 0 };
    while (location.x < world.map_columns) : (location.x += 1) {
        defer location.y = 0;
        while (location.y < world.map_rows) : (location.y += 1) {
            world.map_set_tile(&state.world_vis_map, location, 0);
            if (state.player.entity.location.manhattan_to(location) < 9 and
                world.check_line_of_sight(
                WorldMap,
                state.world_map,
                state.player.entity.location,
                location,
            ).hit_target) {
                world.map_set_tile(&state.world_vis_map, location, 1);
            }
        }
    }
}

fn cancel_aim(state: *State) void {
    platform.trace("cancel item");
    state.turn_state = .ready;
    state.action_target = 0;
    state.action_targets.clear();
}

fn entities_apply_pending_damage(entities: anytype) void {
    for (entities) |*e| {
        if (e.entity.pending_damage > 0) {
            e.entity.health -= e.entity.pending_damage;
            e.entity.pending_damage = 0;
            e.entity.did_receive_damage = true;
            sfx.deal_damage();
        }
    }
}

fn entities_complete_move(entities: anytype) void {
    for (entities) |*e| {
        if (e.entity.health > 0) {
            switch (e.entity.state) {
                .melee_attack => {
                    e.entity.target_location = e.entity.location;
                },
                else => {
                    e.entity.location = e.entity.target_location;
                },
            }
        } else {
            e.entity.location = .{ .x = 0, .y = 0 };
            e.entity.target_location = e.entity.location;
            e.entity.state = .idle;
        }
    }
}

pub fn init() void {
    gfx.init();
}

pub fn update(input: anytype) void {
    switch (screen) {
        .title => title_screen(&game_state, input),
        .controls => controls_screen(input),
        .game => game_screen(&game_state, input),
        .reload => reload_screen(&game_state, input),
        .win => stats_screen(&game_state, input, "YOU ESCAPED", .title, null),
    }
    gfx.frame_counter += 1;
}

fn game_screen(state: anytype, newest_input: anytype) void {
    if (state.level == data.levels.len) {
        screen = .win;
        menu_option = 0;
        // state.game_elapsed_ns = state.timer.read();
        return;
    }

    if (newest_input.any_pressed()) {
        input_queue.push(newest_input);
    }

    switch (state.turn_state) {
        .ready => {
            if (input_queue.pop()) |input| {
                if (input.action_1 > 0) {
                    platform.trace("aim item");
                    find_action_targets(state) catch {
                        platform.trace("error: failed to find action targets");
                    };
                    state.action_target = 0;
                    state.turn_state = .aim;
                    gfx.move_anim_start_frame = gfx.frame_counter;
                } else if (input.action_2 > 0) {
                    try_cycle_item(state);
                } else if (input.up > 0) {
                    try_move(state, state.player.entity.location.walk(.north, 1));
                } else if (input.right > 0) {
                    gfx.flip_player_sprite = false;
                    try_move(state, state.player.entity.location.walk(.east, 1));
                } else if (input.down > 0) {
                    try_move(state, state.player.entity.location.walk(.south, 1));
                } else if (input.left > 0) {
                    gfx.flip_player_sprite = true;
                    try_move(state, state.player.entity.location.walk(.west, 1));
                }
            }
        },
        .aim => {
            if (input_queue.pop()) |input| {
                if (input.action_1 > 0) {
                    if (state.action_targets.length == 0) {
                        cancel_aim(state);
                    } else {
                        platform.trace("commit action");
                        const target_location = state.action_targets.get(state.action_target) catch {
                            platform.trace("error: failed to get action target");
                            unreachable;
                        };
                        switch (state.player.active_item) {
                            .fists, .sword => try_move(state, target_location),
                            .small_axe => if (try_hit_enemy(state, target_location)) {
                                state.player.remove_item(.small_axe);
                                spawn_pickup(state, target_location, .small_axe);
                                if (target_location.x < state.player.entity.location.x) {
                                    gfx.flip_player_sprite = true;
                                } else if (target_location.x > state.player.entity.location.x) {
                                    gfx.flip_player_sprite = false;
                                }
                                commit_move(state);
                            },
                        }
                    }
                } else if (input.action_2 > 0) {
                    cancel_aim(state);
                } else if (state.action_targets.length > 0) {
                    if (input.up > 0 or input.right > 0) {
                        sfx.walk();
                        state.action_target = @intCast(
                            u8,
                            if (state.action_target == state.action_targets.length - 1) 0 else state.action_target + 1,
                        );
                        gfx.move_anim_start_frame = gfx.frame_counter;
                    } else if (input.down > 0 or input.left > 0) {
                        sfx.walk();
                        state.action_target = @intCast(
                            u8,
                            if (state.action_target == 0) state.action_targets.length - 1 else state.action_target - 1,
                        );
                        gfx.move_anim_start_frame = gfx.frame_counter;
                    }
                }
            }
        },
        .commit => {
            if (gfx.frame_counter > gfx.move_anim_start_frame + gfx.move_animation_length) {
                switch (state.player.entity.state) {
                    .walk => {
                        state.player.entity.location = state.player.entity.target_location;
                    },
                    else => {
                        state.player.entity.target_location = state.player.entity.location;
                    },
                }

                entities_apply_pending_damage(&state.monsters);
                entities_apply_pending_damage(&state.fire_monsters);
                entities_apply_pending_damage(&state.charge_monsters);

                respond_to_move(state);
                update_world_visibilty(state);
                state.player.entity.state = .idle;
                gfx.move_anim_start_frame = gfx.frame_counter;
                state.turn_state = .response;
            }
        },
        .response => {
            if (gfx.frame_counter > gfx.move_anim_start_frame + gfx.move_animation_length) {
                entities_complete_move(&state.monsters);
                entities_complete_move(&state.fire_monsters);
                entities_complete_move(&state.charge_monsters);
                entities_complete_move(&state.fire);

                state.player.entity.target_location = state.player.entity.location;

                if (state.player.entity.pending_damage > 0) {
                    state.player.entity.health -= state.player.entity.pending_damage;
                    state.player.entity.pending_damage = 0;
                    state.player.entity.did_receive_damage = true;
                    sfx.receive_damage();
                }

                if (state.player.entity.health <= 0) {
                    platform.trace("player died");
                    state.turn_state = .dead;
                    // state.game_elapsed_ns = state.timer.read();
                } else {
                    state.turn_state = .ready;
                }

                state.turn += 1;
            }
        },
        .dead => {},
    }

    defer {
        state.player.entity.did_receive_damage = false;
        for (state.monsters) |*monster| {
            monster.entity.did_receive_damage = false;
        }
        for (state.fire_monsters) |*monster| {
            monster.entity.did_receive_damage = false;
        }
        for (state.charge_monsters) |*monster| {
            monster.entity.did_receive_damage = false;
        }
    }

    gfx.draw_game(state);

    if (state.turn_state == .dead) {
        gfx.draw_transparent_overlay();
        stats_screen(state, newest_input, "YOU DIED", .reload, null);
        menu_option = state.level;
    } else {
        gfx.draw_hud(state);
    }
}

fn title_screen(state: anytype, input: anytype) void {
    gfx.draw_title_menu();

    if (input.action_1 > 0) {
        sfx.walk();
        screen = .game;
        menu_option = 0;
        state.reset();
        state.load_level(0);
        platform.trace("start game");
    } else if (input.action_2 > 0) {
        sfx.walk();
        screen = .controls;
        menu_option = 0;
        platform.trace("show controls");
    }
}

fn controls_screen(input: anytype) void {
    gfx.draw_controls();

    if (input.action_1 > 0 or input.action_2 > 0) {
        sfx.walk();
        screen = .title;
        menu_option = 0;
        platform.trace("return to title screen");
    }
}

fn stats_screen(
    state: anytype,
    input: anytype,
    title_text: []const u8,
    advance_screen: Screen,
    maybe_retreat_screen: ?Screen,
) void {
    gfx.draw_screen_title(title_text);

    // const total_elasped_sec = @divTrunc(state.game_elapsed_ns, 1_000_000_000);
    // const elapsed_minutes = @divTrunc(total_elasped_sec, 60);
    // const elapsed_seconds = total_elasped_sec - (elapsed_minutes + 60);
    gfx.draw_stats(.{
        .turns_taken = state.turn,
        // .elapsed_m = elapsed_minutes,
        // .elapsed_s = elapsed_seconds,
    });

    if (input.action_1 > 0) {
        sfx.walk();
        screen = advance_screen;
        return;
    }

    if (maybe_retreat_screen) |retreat_screen| {
        if (input.action_1 > 0) {
            sfx.walk();
            screen = retreat_screen;
        }
    }
}

fn reload_screen(state: anytype, input: anytype) void {
    switch (state.level) {
        0 => {
            screen = .game;
            menu_option = 0;
            state.load_level(0);
        },
        else => {
            if (input.action_1 > 0) {
                screen = .game;
                defer menu_option = 0;
                state.load_level(menu_option);
                state.player.entity.health = player_level_starting_health[menu_option];
                state.player.items = player_level_starting_items[menu_option];
                state.player.active_item = player_level_starting_active_item[menu_option];
            }

            if (input.up > 0 or input.right > 0) {
                menu_option = if (menu_option == state.level) 0 else menu_option + 1;
            } else if (input.down > 0 or input.left > 0) {
                menu_option = if (menu_option == 0) state.level else menu_option - 1;
            }

            gfx.draw_reload_screen(state, &menu_option);
        },
    }
}

test {
    std.testing.refAllDecls(@This());
}
