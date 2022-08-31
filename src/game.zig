const std = @import("std");
const sqrt = std.math.sqrt;
var rng = std.rand.DefaultPrng.init(42);

const world = @import("world.zig");
const WorldMap = world.Map(world.size_x, world.size_y);

pub fn Game(gfx: anytype, sfx: anytype, util: anytype, data: anytype) type {
    return struct {
        const starting_player_health = 5;

        var screen: Screen = .title;
        var flip_player_sprite = false;
        var move_start_frame: usize = 0;

        pub var input_queue = struct {
            inputs: [8]ButtonPressEvent = undefined,
            count: usize = 0,
            read_cursor: usize = 0,
            write_cursor: usize = 0,

            pub fn push(self: *@This(), input: ButtonPressEvent) void {
                self.inputs[self.write_cursor] = input;
                self.write_cursor = @mod(self.write_cursor + 1, self.inputs.len);
                if (self.count == self.inputs.len) {
                    util.trace("warning: input queue overflow");
                    self.read_cursor = @mod(self.read_cursor + 1, self.inputs.len);
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
            turn: u8 = 0,
            level: u8 = 0,
            action_target: u8 = 0,
            action_targets: [16]world.Location = undefined,
            action_target_count: u8 = 0,
            world_map: WorldMap = undefined,
            world_vis_map: WorldMap = undefined,
            player: Player = undefined,
            monsters: [16]Enemy = undefined,
            fire_monsters: [8]Enemy = undefined,
            fire: [16]Enemy = undefined,
            pickups: [8]Pickup = undefined,
            monster_count: u8 = 0,
            fire_monster_count: u8 = 0,
            fire_count: u8 = 0,
            pickup_count: u8 = 0,

            pub fn reset(self: *@This()) void {
                util.trace("reset");
                // self.timer = std.time.Timer.start() catch @panic("Failed to start timer");
                self.turn_state = .ready;
                self.turn = 0;
                self.player.entity.health = starting_player_health;
                self.player.active_item = .fists;
                self.player.items = 0b1;
                self.action_target_count = 0;
            }

            pub fn load_level(self: *@This(), level: u8) void {
                util.trace("load_level");

                self.turn_state = .ready;
                self.action_target_count = 0;

                self.level = level;
                self.world_map = @bitCast(WorldMap, data.levels[level]);

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
                                self.player.entity.set_location(location);
                            },
                            .monster_spawn => {
                                var monster = &self.monsters[self.monster_count];
                                monster.entity.set_location(location);
                                monster.entity.health = 2;
                                self.monster_count += 1;
                            },
                            .fire_monster_spawn => {
                                var fire_monster = &self.fire_monsters[self.fire_monster_count];
                                fire_monster.entity.set_location(location);
                                fire_monster.entity.health = 3;
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
            }

            fn spawn_pickup(self: *@This(), location: world.Location, kind: anytype) void {
                util.trace("spawn pickup");

                for (self.pickups) |*pickup| {
                    if (pickup.entity.health == 0) {
                        pickup.entity.set_location(location);
                        pickup.entity.health = 1;
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
            for (state.monsters) |*monster| {
                if (monster.entity.health > 0 and
                    monster.entity.location.eql(location))
                {
                    state.player.entity.target_location = monster.entity.location;
                    monster.entity.health -= state.player.get_damage();
                    sfx.deal_damage();
                    return true;
                }
            }

            for (state.fire_monsters) |*fire_monster| {
                if (fire_monster.entity.health > 0 and
                    fire_monster.entity.location.eql(location))
                {
                    state.player.entity.target_location = fire_monster.entity.location;
                    fire_monster.entity.health -= state.player.get_damage();
                    sfx.deal_damage();
                    return true;
                }
            }

            return false;
        }

        fn try_cycle_item(state: *State) void {
            util.trace("cycle item");

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
                util.trace("dont possess item");
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
            util.trace("commit move");

            move_start_frame = gfx.frame_counter;
            state.turn_state = .commit;
        }

        fn respond_to_move(state: *State) void {
            util.trace("responding to move...");

            defer {
                update_world_lightmap(state);

                if (state.player.entity.health < 0) {
                    state.player.entity.health = 0;
                }
            }

            if (world.map_get_tile_kind(state.world_map, state.player.entity.location) == .door) {
                state.level += 1;
                if (state.level < data.levels.len) {
                    util.trace("load next level");
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
                    util.trace("monster: begin move...");
                    defer util.trace("monster: move complete");

                    var dx = state.player.entity.location.x - monster.entity.location.x;
                    var dy = state.player.entity.location.y - monster.entity.location.y;
                    const manhattan_dist = @intCast(u8, (if (dx < 0) -dx else dx) + if (dy < 0) -dy else dy);

                    if (manhattan_dist == 1) {
                        util.trace("monster: hit player!");
                        sfx.receive_damage();
                        state.player.entity.health -= 2;
                        monster.entity.target_location = state.player.entity.location;
                        monster.entity.state = .melee_attack;
                        break :find_move;
                    } else if (manhattan_dist <= 3) {
                        util.trace("monster: approach player");

                        var possible_location = monster.entity.location;

                        if (dx == 0 or dy == 0) {
                            util.trace("monster: orthogonal, step closer");
                            if (dx != 0) {
                                possible_location.x += @divTrunc(dx, dx);
                            } else if (dy != 0) {
                                possible_location.y += @divTrunc(dy, dy);
                            }
                        } else {
                            util.trace("monster: on diagonal (roll dice)");
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
                            util.trace("monster: chase player!");

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

                    util.trace("monster: random walk");
                    random_walk(state, &monster.entity);
                }
            }

            for (state.fire_monsters) |*fire_monster| {
                if (fire_monster.cooldown > 0) {
                    fire_monster.cooldown -= 1;
                } else if (fire_monster.entity.health > 0) find_move: {
                    util.trace("fire_monster: begin move...");
                    defer util.trace("fire_monster: move complete");

                    const d = fire_monster.entity.location.manhattan_to(state.player.entity.location);

                    if (d > 3 and d < 20) {
                        const res = world.check_line_of_sight(
                            WorldMap,
                            state.world_map,
                            fire_monster.entity.location,
                            state.player.entity.location,
                        );
                        if (res.hit_target) {
                            util.trace("fire_monster: spit at player");
                            spawn_fire(state, res.path);
                            fire_monster.cooldown = 1;
                            break :find_move;
                        }
                    }

                    util.trace("fire_monster: random walk");
                    random_walk(state, &fire_monster.entity);
                }
            }
        }

        /// Returns true if the location is not occupied by a blocking tile or blocking entity
        fn test_walkable(state: *State, location: world.Location) bool {
            util.trace("test location walkable...");

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

            if (walkable) util.trace("is walkable") else util.trace("is NOT walkable");

            return walkable;
        }

        fn spawn_fire(state: *State, path: world.Path) void {
            util.trace("spawn fire");

            if (state.fire_count < state.fire.len) {
                var new_fire = Enemy{
                    .entity = .{
                        .location = path.locations[0],
                        .target_location = path.locations[0],
                        .health = 1,
                    },
                };
                new_fire.path.length = if (path.length <= 1) 0 else path.length - 1;
                if (new_fire.path.length > 0) {
                    std.mem.copy(world.Location, new_fire.path.locations[0..], path.locations[1..]);
                }
                state.fire[state.fire_count] = new_fire;
                state.fire_count += 1;
            }
        }

        fn update_fire(state: *State, fire: *Enemy) void {
            util.trace("update fire");

            if (fire.path.length > 1) {
                std.mem.copy(world.Location, fire.path.locations[0..], fire.path.locations[1..]);
            }

            fire.path.length -= 1;

            if (fire.path.length > 0) {
                util.trace("fire walk path");

                fire.entity.target_location = fire.path.locations[0];

                if (world.map_get_tile_kind(state.world_map, fire.entity.location) != .wall) {
                    if (fire.entity.location.eql(state.player.entity.location)) {
                        util.trace("fire hit player!");
                        sfx.receive_damage();
                        state.player.entity.health -= 1;
                    }
                }

                return;
            }

            fire.entity.health = 0;
            fire.path.length = 0;
            state.fire_count -= 1;

            util.trace("fire extinguished");
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
                entity.target_location = location;
                entity.state = .walk;
            }
        }

        fn update_world_lightmap(state: *State) void {
            util.trace("update world lightmap");

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
            util.trace("cancel item");
            state.turn_state = .ready;
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
                            util.trace("aim item");
                            find_action_targets(state);
                            state.action_target = 0;
                            state.turn_state = .aim;
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
                            if (state.action_target_count == 0) {
                                cancel_aim(state);
                            } else {
                                util.trace("commit action");
                                const target_location = state.action_targets[state.action_target];
                                switch (state.player.active_item) {
                                    .fists, .sword => try_move(state, target_location),
                                    .small_axe => if (try_hit_enemy(state, target_location)) {
                                        state.player.remove_item(.small_axe);
                                        state.spawn_pickup(target_location, .small_axe);
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
                        } else if (state.action_target_count > 0) {
                            if (input.up > 0 or input.right > 0) {
                                sfx.walk();
                                state.action_target = if (state.action_target == state.action_target_count - 1) 0 else state.action_target + 1;
                            } else if (input.down > 0 or input.left > 0) {
                                sfx.walk();
                                state.action_target = if (state.action_target == 0) state.action_target_count - 1 else state.action_target - 1;
                            }
                        }
                    }
                },
                .commit => {
                    const animation_frame = gfx.frame_counter - move_start_frame;
                    if (animation_frame >= gfx.move_animation_frames) {
                        switch (state.player.entity.state) {
                            .walk => {
                                state.player.entity.location = state.player.entity.target_location;
                            },
                            else => {
                                state.player.entity.target_location = state.player.entity.location;
                            },
                        }
                        respond_to_move(state);
                        state.player.entity.state = .idle;
                        move_start_frame = gfx.frame_counter;
                        state.turn_state = .response;
                    }
                },
                .response => {
                    const animation_frame = gfx.frame_counter - move_start_frame;
                    if (animation_frame >= gfx.move_animation_frames) {
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

                        if (state.player.entity.health <= 0) {
                            util.trace("player died");
                            screen = .dead;
                            // state.game_elapsed_ns = state.timer.read();
                        }
                        state.turn += 1;
                        state.turn_state = .ready;
                    }
                },
            }

            const animation_frame = switch (state.turn_state) {
                .commit, .response => gfx.frame_counter - move_start_frame,
                else => 0,
            };

            // update camera location
            var camera_location = state.player.entity.location;
            var camera_screen_pos = gfx.lerp(
                camera_location,
                state.player.entity.target_location,
                animation_frame,
                gfx.move_animation_frames,
            ).sub(.{
                .x = gfx.screen_px_width / 2,
                .y = gfx.screen_px_height / 2,
            });
            if (state.turn_state == .aim and state.action_target_count > 0) {
                camera_location = state.action_targets[state.action_target];
                camera_screen_pos = gfx.world_to_screen(camera_location).sub(.{
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
                        sprite_list.push_sprite(.{
                            .texture = data.Texture.monster,
                            .draw_colours = 0x20,
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
                        sprite_list.push_sprite(.{
                            .texture = data.Texture.fire_monster,
                            .draw_colours = 0x20,
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
                    sprite_list.push_sprite(.{
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
                sprite_list.push_sprite(.{
                    .texture = data.Texture.player,
                    .draw_colours = 0x20,
                    .location = state.player.entity.location,
                    .target_location = state.player.entity.target_location,
                    .flip_x = flip_player_sprite,
                    .casts_shadow = true,
                });
            }

            for (state.fire) |*fire| {
                if (fire.entity.health == 0) {
                    continue;
                }

                if (world.map_get_tile(state.world_vis_map, fire.entity.location) > 0) {
                    sprite_list.push_sprite(.{
                        .texture = data.Texture.fire_big,
                        .draw_colours = 0x40,
                        .location = fire.entity.location,
                        .target_location = fire.entity.target_location,
                    });
                }

                if (fire.path.length > 1) {
                    const location = fire.path.locations[1];
                    if (world.map_get_tile(state.world_vis_map, location) > 0) {
                        sprite_list.push_sprite(.{
                            .texture = data.Texture.fire_small,
                            .draw_colours = 0x40,
                            .location = location,
                            .target_location = location,
                        });
                    }
                }
            }

            gfx.draw_world(state, camera_screen_pos);

            sprite_list.draw_shadows(camera_screen_pos, animation_frame);

            if (state.turn_state == .aim) {
                gfx.draw_tile_markers(state, camera_screen_pos);
            }

            sprite_list.draw(camera_screen_pos, animation_frame);

            gfx.draw_hud(state, camera_screen_pos);
        }

        fn title_screen(state: anytype, input: anytype) void {
            gfx.draw_title_menu();

            if (input.action_1 > 0) {
                sfx.walk();
                screen = .game;
                state.reset();
                state.load_level(0);
                util.trace("start game");
            } else if (input.action_2 > 0) {
                sfx.walk();
                screen = .controls;
                util.trace("show controls");
            }
        }

        fn controls_screen(input: anytype) void {
            gfx.draw_controls();

            if (input.action_1 + input.action_2 > 0) {
                sfx.walk();
                screen = .title;
                util.trace("return to title screen");
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
