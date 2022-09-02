const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const util = @import("util.zig");
const quicksort = util.quicksort;
const StaticList = util.StaticList;

const world = @import("world.zig");
const WorldMap = world.Map(world.size_x, world.size_y);

pub fn Game(gfx: anytype, sfx: anytype, platform: anytype, data: anytype) type {
    return struct {
        const starting_player_health = 5;

        var screen: Screen = .title;
        var flip_player_sprite = false;
        var anim_start_frame: usize = 0;
        var camera_location: world.Location = undefined;
        var camera_screen_pos: gfx.ScreenPosition = undefined;

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
                const sum = self.left + self.right + self.up + self.down + self.action_1 + self.action_2;
                return (sum > 0);
            }
        };

        pub const Screen = enum { title, controls, game, dead, win };

        const Entity = struct {
            location: world.Location = world.Location{ .x = 0, .y = 0 },
            target_location: world.Location = world.Location{ .x = 0, .y = 0 },
            health: i8,
            pending_damage: u4 = 0,
            did_receive_damage: bool = false,
            state: enum { idle, walk, melee_attack } = .idle,

            pub fn set_location(self: *@This(), location: world.Location) void {
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
            cooldown: u8 = 0,
        };

        const Pickup = struct {
            entity: Entity,
            kind: enum { health, sword, small_axe },
        };

        pub const State = struct {
            // timer: std.time.Timer = undefined,
            game_elapsed_ns: u64 = 0,
            turn_state: enum { ready, aim, commit, response } = .ready,
            turn: u32 = 0,
            level: u8 = 0,
            action_target: u8 = 0,
            action_targets: StaticList(world.Location, 16) = .{},
            world_map: WorldMap = undefined,
            world_vis_map: WorldMap = undefined,
            player: Player = undefined,
            monsters: [16]Enemy = undefined,
            fire_monsters: [8]Enemy = undefined,
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

                self.turn_state = .ready;
                self.action_targets.clear();

                self.level = level;
                self.world_map = @bitCast(WorldMap, data.levels[level]);

                // reset entity pools
                for (self.monsters) |*monster| monster.entity.health = 0;
                for (self.fire_monsters) |*fire_monster| fire_monster.entity.health = 0;
                for (self.fire) |*fire| fire.entity.health = 0;
                for (self.pickups) |*pickup| pickup.entity.health = 0;

                // find spawners on level map and spawn things at those locations
                var location: world.Location = .{ .x = 0, .y = 0 };
                while (location.x < world.size_x) : (location.x += 1) {
                    defer location.y = 0;
                    while (location.y < world.size_y) : (location.y += 1) {
                        switch (world.map_get_tile_kind(self.world_map, location)) {
                            .player_spawn => {
                                self.player.entity.set_location(location);
                            },
                            .monster_spawn => spawn_enemy(&self.monsters, location, 2),
                            .fire_monster_spawn => spawn_enemy(&self.fire_monsters, location, 3),
                            .health_pickup => spawn_pickup(self, location, .health),
                            .sword_pickup => spawn_pickup(self, location, .sword),
                            .small_axe_pickup => spawn_pickup(self, location, .small_axe),
                            else => {},
                        }
                    }
                }

                update_world_lightmap(self);
            }
        };

        fn spawn_enemy(pool: anytype, location: world.Location, health: u4) void {
            for (pool) |*enemy| {
                if (enemy.entity.health <= 0) {
                    enemy.entity.set_location(location);
                    enemy.entity.health = health;
                    platform.trace("spawned enemy");
                    return;
                }
            }
            platform.trace("warning: enemy not spawned. no free space");
        }

        fn spawn_pickup(state: *State, location: world.Location, kind: anytype) void {
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

        fn spawn_fire(state: *State, path: world.Path) void {
            for (state.fire) |*fire| {
                if (fire.entity.health <= 0) {
                    fire.entity = .{
                        .location = path.locations[0],
                        .target_location = path.locations[0],
                        .health = 1,
                    };
                    fire.path.length = if (path.length <= 1) 0 else path.length - 1;
                    if (fire.path.length > 0) {
                        std.mem.copy(world.Location, fire.path.locations[0..], path.locations[1..]);
                    }
                    platform.trace("spawned fire");
                    return;
                }
            }
            platform.trace("warning: fire not spawned. no free space");
        }

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

        fn try_hit_enemy(state: *State, location: world.Location) bool {
            if (entities_try_hit(&state.monsters, location) orelse
                entities_try_hit(&state.fire_monsters, location)) |entity|
            {
                state.player.entity.target_location = entity.location;
                entity.pending_damage += state.player.get_damage();
                return true;
            }
            return false;
        }

        fn entities_try_hit(entities: anytype, location: world.Location) ?*Entity {
            for (entities) |*e| {
                if (e.entity.health > 0 and
                    e.entity.location.eql(location))
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
                .fists => try find_melee_targets(state, [_]world.Direction{
                    world.Direction.north,
                    world.Direction.east,
                    world.Direction.south,
                    world.Direction.west,
                }),
                .sword => try find_melee_targets(state, [_]world.Direction{
                    world.Direction.north,
                    world.Direction.north_east,
                    world.Direction.east,
                    world.Direction.south_east,
                    world.Direction.south,
                    world.Direction.south_west,
                    world.Direction.west,
                    world.Direction.north_west,
                }),
                .small_axe => { // ranged attack
                    try find_ranged_targets(state, state.monsters);
                    try find_ranged_targets(state, state.fire_monsters);

                    if (state.action_targets.count > 1) {
                        const targets = state.action_targets.all();
                        var distance_comparitor = struct {
                            state: *State,
                            pub fn compare(self: @This(), a: world.Location, b: world.Location) bool {
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
                const location = state.player.entity.location.walk(dir);
                if (world.map_get_tile_kind(state.world_map, location) != .wall) {
                    for (state.monsters) |*monster| {
                        if (monster.entity.health > 0 and monster.entity.location.eql(location)) {
                            try state.action_targets.push(monster.entity.location);
                        }
                    }
                    for (state.fire_monsters) |*monster| {
                        if (monster.entity.health > 0 and monster.entity.location.eql(location)) {
                            try state.action_targets.push(monster.entity.location);
                        }
                    }
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

        fn test_can_ranged_attack(state: *State, location: world.Location) bool {
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

            anim_start_frame = gfx.frame_counter;
            state.turn_state = .commit;
        }

        fn respond_to_move(state: *State) void {
            platform.trace("responding to move...");

            defer {
                update_world_lightmap(state);
            }

            if (world.map_get_tile_kind(state.world_map, state.player.entity.location) == .door) {
                state.level += 1;
                if (state.level < data.levels.len) {
                    platform.trace("load next level");
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
                    platform.trace("monster: begin move...");
                    defer platform.trace("monster: move complete");

                    var dx = state.player.entity.location.x - monster.entity.location.x;
                    var dy = state.player.entity.location.y - monster.entity.location.y;
                    const manhattan_dist = @intCast(u8, (if (dx < 0) -dx else dx) + if (dy < 0) -dy else dy);

                    if (manhattan_dist == 1) {
                        platform.trace("monster: hit player!");
                        state.player.entity.pending_damage += 2;
                        monster.entity.target_location = state.player.entity.location;
                        monster.entity.state = .melee_attack;
                        break :find_move;
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
                            platform.trace("monster: on diagonal (roll dice)");
                            switch (rng.random().int(u1)) {
                                0 => possible_location.x += @divTrunc(dx, dx),
                                1 => possible_location.y += @divTrunc(dy, dy),
                            }
                        }

                        if (test_walkable(state, possible_location)) {
                            monster.entity.target_location = possible_location;
                            monster.entity.state = .walk;
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
                            platform.trace("monster: chase player!");

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
                                            monster.entity.target_location = new_location;
                                            monster.entity.state = .walk;
                                            break;
                                        }
                                    }
                                }
                            }
                            break :find_move;
                        }
                    }

                    platform.trace("monster: random walk");
                    random_walk(state, &monster.entity);
                }
            }

            for (state.fire_monsters) |*fire_monster| {
                if (fire_monster.cooldown > 0) {
                    fire_monster.cooldown -= 1;
                } else if (fire_monster.entity.health > 0) find_move: {
                    platform.trace("fire_monster: begin move...");
                    defer platform.trace("fire_monster: move complete");

                    const d = fire_monster.entity.location.manhattan_to(state.player.entity.location);

                    if (d > 3 and d < 20) {
                        const res = world.check_line_of_sight(
                            WorldMap,
                            state.world_map,
                            fire_monster.entity.location,
                            state.player.entity.location,
                        );
                        if (res.hit_target) {
                            platform.trace("fire_monster: spit at player");
                            spawn_fire(state, res.path);
                            fire_monster.cooldown = 2;
                            break :find_move;
                        }
                    }

                    platform.trace("fire_monster: random walk");
                    random_walk(state, &fire_monster.entity);
                }
            }
        }

        /// Returns true if the location is not occupied by a blocking tile or blocking entity
        fn test_walkable(state: *State, location: world.Location) bool {
            platform.trace("test location walkable...");

            const kind = world.map_get_tile_kind(state.world_map, location);

            var walkable = switch (kind) {
                .wall, .locked_door => false,
                else => true,
            };

            if (state.player.entity.health > 0 and state.player.entity.location.eql(location)) {
                walkable = false;
            }

            for (state.monsters) |*other| {
                if (other.entity.health > 0 and other.entity.target_location.eql(location)) {
                    walkable = false;
                }
            }
            for (state.fire_monsters) |*other| {
                if (other.entity.health > 0 and other.entity.target_location.eql(location)) {
                    walkable = false;
                }
            }

            for (state.pickups) |*other| {
                if (other.entity.health > 0 and other.entity.target_location.eql(location)) {
                    walkable = false;
                }
            }

            if (walkable) platform.trace("is walkable") else platform.trace("is NOT walkable");

            return walkable;
        }

        fn update_fire(state: *State, fire: *Enemy) void {
            platform.trace("update fire");

            if (fire.path.length > 1) {
                std.mem.copy(world.Location, fire.path.locations[0..], fire.path.locations[1..]);
            }

            fire.path.length -= 1;

            if (fire.path.length > 0) {
                platform.trace("fire walk path");

                fire.entity.target_location = fire.path.locations[0];

                if (world.map_get_tile_kind(state.world_map, fire.entity.location) != .wall) {
                    if (fire.entity.target_location.eql(state.player.entity.location)) {
                        platform.trace("fire hit player!");
                        state.player.entity.pending_damage += 1;
                    }
                }

                return;
            }

            fire.entity.health = 0;
            fire.path.length = 0;

            platform.trace("fire extinguished");
        }

        /// finds walkable adjacent tile or ramains still (random walk)
        fn random_walk(state: *State, entity: *Entity) void {
            const ortho_locations = [_]world.Location{
                entity.location.north(),
                entity.location.east(),
                entity.location.south(),
                entity.location.west(),
            };
            const random_index = @mod(rng.random().int(usize), 4);
            const location = ortho_locations[random_index];
            if (test_walkable(state, location)) {
                entity.target_location = location;
                entity.state = .walk;
            }
        }

        fn update_world_lightmap(state: *State) void {
            platform.trace("update world lightmap");
            defer platform.trace("lightmap updated");

            var location: world.Location = .{ .x = 0, .y = 0 };
            while (location.x < world.size_x) : (location.x += 1) {
                defer location.y = 0;
                while (location.y < world.size_y) : (location.y += 1) {
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

        fn entities_apply_pending_damage(pool: anytype) void {
            for (pool) |*e| {
                if (e.entity.pending_damage > 0) {
                    e.entity.health -= e.entity.pending_damage;
                    e.entity.pending_damage = 0;
                    e.entity.did_receive_damage = true;
                    sfx.deal_damage();
                }
            }
        }

        pub fn update(state: anytype, input: anytype) void {
            switch (screen) {
                .title => title_screen(state, input),
                .controls => controls_screen(input),
                .game => update_and_render_game(state, input),
                .dead => stats_screen(state, input, "YOU DIED", .title, null),
                .win => stats_screen(state, input, "YOU ESCAPED", .title, null),
            }
        }

        fn update_and_render_game(state: anytype, newest_input: anytype) void {
            if (state.level == data.levels.len) {
                screen = .win;
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
                            anim_start_frame = gfx.frame_counter;
                        } else if (input.action_2 > 0) {
                            try_cycle_item(state);
                        } else if (input.up > 0) {
                            try_move(state, state.player.entity.location.walk(.north));
                        } else if (input.right > 0) {
                            flip_player_sprite = false;
                            try_move(state, state.player.entity.location.walk(.east));
                        } else if (input.down > 0) {
                            try_move(state, state.player.entity.location.walk(.south));
                        } else if (input.left > 0) {
                            flip_player_sprite = true;
                            try_move(state, state.player.entity.location.walk(.west));
                        }
                    }
                },
                .aim => {
                    if (input_queue.pop()) |input| {
                        if (input.action_1 > 0) {
                            if (state.action_targets.count == 0) {
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
                                            flip_player_sprite = true;
                                        } else if (target_location.x > state.player.entity.location.x) {
                                            flip_player_sprite = false;
                                        }
                                        commit_move(state);
                                    },
                                }
                            }
                        } else if (input.action_2 > 0) {
                            cancel_aim(state);
                        } else if (state.action_targets.count > 0) {
                            if (input.up > 0 or input.right > 0) {
                                sfx.walk();
                                state.action_target = @intCast(
                                    u8,
                                    if (state.action_target == state.action_targets.count - 1) 0 else state.action_target + 1,
                                );
                                anim_start_frame = gfx.frame_counter;
                            } else if (input.down > 0 or input.left > 0) {
                                sfx.walk();
                                state.action_target = @intCast(
                                    u8,
                                    if (state.action_target == 0) state.action_targets.count - 1 else state.action_target - 1,
                                );
                                anim_start_frame = gfx.frame_counter;
                            }
                        }
                    }
                },
                .commit => {
                    const animation_frame = gfx.frame_counter - anim_start_frame;
                    if (animation_frame > gfx.move_animation_frames) {
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

                        respond_to_move(state);
                        state.player.entity.state = .idle;
                        anim_start_frame = gfx.frame_counter;
                        state.turn_state = .response;
                    }
                },
                .response => {
                    const animation_frame = gfx.frame_counter - anim_start_frame;
                    if (animation_frame > gfx.move_animation_frames) {
                        for (state.monsters) |*monster| {
                            switch (monster.entity.state) {
                                .walk => {
                                    monster.entity.location = monster.entity.target_location;
                                },
                                else => {
                                    monster.entity.target_location = monster.entity.location;
                                },
                            }
                            monster.entity.state = .idle;
                        }
                        for (state.fire_monsters) |*fire_monster| {
                            switch (fire_monster.entity.state) {
                                .walk => {
                                    fire_monster.entity.location = fire_monster.entity.target_location;
                                },
                                else => {
                                    fire_monster.entity.target_location = fire_monster.entity.location;
                                },
                            }
                            fire_monster.entity.state = .idle;
                        }
                        for (state.fire) |*fire| {
                            fire.entity.location = fire.entity.target_location;
                        }

                        if (state.player.entity.pending_damage > 0) {
                            state.player.entity.health -= state.player.entity.pending_damage;
                            state.player.entity.pending_damage = 0;
                            state.player.entity.did_receive_damage = true;
                            sfx.receive_damage();
                        }

                        if (state.player.entity.health <= 0) {
                            platform.trace("player died");
                            screen = .dead;
                            // state.game_elapsed_ns = state.timer.read();
                        }
                        state.turn += 1;
                        state.turn_state = .ready;
                    }
                },
            }

            const animation_frame = switch (state.turn_state) {
                .aim, .commit, .response => gfx.frame_counter - anim_start_frame,
                else => 0,
            };

            // update camera location
            if (state.turn_state == .aim and state.action_targets.count > 0) {
                // move to aim target
                if (animation_frame <= gfx.move_animation_frames) {
                    camera_screen_pos = gfx.lerp(
                        camera_location,
                        state.action_targets.get(state.action_target) catch {
                            platform.trace("error: failed to get action target");
                            unreachable;
                        },
                        animation_frame,
                        gfx.move_animation_frames,
                    ).sub(.{
                        .x = gfx.screen_px_width / 2,
                        .y = gfx.screen_px_height / 2,
                    });
                } else {
                    camera_location = state.action_targets.get(state.action_target) catch {
                        platform.trace("error: failed to get action target");
                        unreachable;
                    };
                }
            } else {
                // follow player
                camera_location = state.player.entity.location;
                camera_screen_pos = gfx.lerp(
                    camera_location,
                    state.player.entity.target_location,
                    animation_frame,
                    gfx.move_animation_frames,
                ).sub(.{
                    .x = gfx.screen_px_width / 2,
                    .y = gfx.screen_px_height / 2,
                });
            }

            var sprite_list = gfx.SpriteList{};

            { // draw enemies
                for (state.monsters) |*monster| {
                    if (monster.entity.health > 0 and
                        world.map_get_tile(state.world_vis_map, monster.entity.location) > 0)
                    {
                        sprite_list.push(.{
                            .texture = data.Texture.monster,
                            .draw_colours = if (monster.entity.did_receive_damage) 0x40 else 0x20,
                            .location = monster.entity.location,
                            .target_location = monster.entity.target_location,
                            .casts_shadow = true,
                        });
                    }
                }

                for (state.fire_monsters) |*fire_monster| {
                    if (fire_monster.entity.health > 0 and
                        world.map_get_tile(state.world_vis_map, fire_monster.entity.location) > 0)
                    {
                        sprite_list.push(.{
                            .texture = data.Texture.fire_monster,
                            .draw_colours = if (fire_monster.entity.did_receive_damage) 0x40 else 0x20,
                            .location = fire_monster.entity.location,
                            .target_location = fire_monster.entity.target_location,
                            .casts_shadow = true,
                        });
                    }
                }
            }

            // draw pickups
            for (state.pickups) |*pickup| {
                if (pickup.entity.health > 0 and world.map_get_tile(
                    state.world_vis_map,
                    pickup.entity.location,
                ) > 0) {
                    sprite_list.push(.{
                        .texture = switch (pickup.kind) {
                            .health => data.Texture.heart,
                            .sword => data.Texture.sword,
                            .small_axe => data.Texture.small_axe,
                        },
                        .draw_colours = 0x40,
                        .location = pickup.entity.location,
                        .target_location = pickup.entity.target_location,
                        .casts_shadow = true,
                    });
                }
            }

            { // draw player
                sprite_list.push(.{
                    .texture = data.Texture.player,
                    .draw_colours = if (state.player.entity.did_receive_damage) 0x40 else 0x20,
                    .location = state.player.entity.location,
                    .target_location = state.player.entity.target_location,
                    .flip_x = flip_player_sprite,
                    .casts_shadow = true,
                });
            }

            for (state.fire) |*fire| {
                if (fire.entity.health <= 0) {
                    continue;
                }

                if (world.map_get_tile(state.world_vis_map, fire.entity.location) > 0) {
                    sprite_list.push(.{
                        .texture = data.Texture.fire_big,
                        .draw_colours = 0x40,
                        .location = fire.entity.location,
                        .target_location = fire.entity.target_location,
                    });
                }

                if (fire.path.length > 1) {
                    const location = fire.path.locations[1];
                    if (world.map_get_tile(state.world_vis_map, location) > 0) {
                        sprite_list.push(.{
                            .texture = data.Texture.fire_small,
                            .draw_colours = 0x40,
                            .location = location,
                            .target_location = location,
                        });
                    }
                }
            }

            gfx.draw_world(state, camera_screen_pos);

            gfx.draw_shadows(sprite_list, camera_screen_pos, animation_frame);

            if (state.turn_state == .aim) {
                gfx.draw_tile_markers(state, camera_screen_pos);
            }

            sprite_list.draw(camera_screen_pos, animation_frame);

            gfx.draw_hud(state, camera_screen_pos);

            {
                state.player.entity.did_receive_damage = false;
                for (state.monsters) |*monster| {
                    monster.entity.did_receive_damage = false;
                }
                for (state.fire_monsters) |*monster| {
                    monster.entity.did_receive_damage = false;
                }
            }
        }

        fn title_screen(state: anytype, input: anytype) void {
            gfx.draw_title_menu();

            if (input.action_1 > 0) {
                sfx.walk();
                screen = .game;
                state.reset();
                state.load_level(0);
                platform.trace("start game");
            } else if (input.action_2 > 0) {
                sfx.walk();
                screen = .controls;
                platform.trace("show controls");
            }
        }

        fn controls_screen(input: anytype) void {
            gfx.draw_controls();

            if (input.action_1 + input.action_2 > 0) {
                sfx.walk();
                screen = .title;
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
    };
}
