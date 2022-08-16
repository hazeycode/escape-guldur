const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const std = @import("std");
var rng = std.rand.DefaultPrng.init(42);

const sprites = @import("sprites.zig");

const world_tile_size = 8;
const world_size = w4.SCREEN_SIZE / world_tile_size;

const World = [world_size][world_size]u8;

const WorldTileEnum = enum(u8) {
    floor,
    wall,
    player_spawn,
    monster_spawn,
};

const WorldPosition = struct { x: u8, y: u8 };

const Direction = enum(u8) {
    left,
    up,
    right,
    down,
};

const Entity = struct {
    position: WorldPosition,
    health: i8,
};

pub const State = struct {
    world: World,
    player: Entity,
    monsters: [8]Entity,
    monster_count: u8,
    turn: u8,
};

const ScreenPosition = struct { x: i32, y: i32 };

fn world_to_screen(world_pos: WorldPosition) ScreenPosition {
    return .{
        .x = world_pos.x * world_tile_size,
        .y = world_pos.y * world_tile_size,
    };
}

pub fn reset(state: *State) void {
    state.world = @bitCast(World, [_]u8{
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
        .position = .{
            .x = 0,
            .y = 0,
        },
        .health = 0,
    };

    state.monster_count = 0;

    var pos: WorldPosition = .{ .x = 0, .y = 0 };
    while (pos.x < world_size) : (pos.x += 1) {
        while (pos.y < world_size) : (pos.y += 1) {
            switch (get_world_tile(state.world, pos)) {
                .player_spawn => {
                    state.player = .{
                        .position = pos,
                        .health = 3,
                    };
                },
                .monster_spawn => {
                    state.monsters[state.monster_count] = .{
                        .position = pos,
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

fn get_world_tile(world: World, pos: WorldPosition) WorldTileEnum {
    return @intToEnum(
        WorldTileEnum,
        world[@intCast(usize, pos.x)][@intCast(usize, pos.y)],
    );
}

fn try_move(state: *State, pos: WorldPosition) void {
    switch (get_world_tile(state.world, pos)) {
        .wall => {}, // you shall not pass!
        else => {
            var monster_killed = false;
            for (state.monsters) |*monster| {
                if (monster.health > 0 and
                    monster.position.x == pos.x and
                    monster.position.y == pos.y)
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
                state.player.position = pos;
                w4.tone(220, 2 | (4 << 8), 80, w4.TONE_TRIANGLE);
            }

            end_move(state);
        },
    }
}

fn end_move(state: *State) void {
    for (state.monsters) |*monster| {
        if (monster.health > 0) {
            var valid_move = false;
            while (valid_move == false) {
                const dx = @intCast(i32, monster.position.x) - state.player.position.x;
                const dy = @intCast(i32, monster.position.y) - state.player.position.y;
                if ((monster.position.x == state.player.position.x and
                    (dy == 1 or dy == -1)) or
                    (monster.position.y == state.player.position.y and
                    (dx == 1 or dx == -1)))
                {
                    w4.tone(300, 2 | (4 << 8), 100, w4.TONE_NOISE);
                    state.player.health -= 1;
                    valid_move = true;
                } else {
                    const new_pos = switch (@intToEnum(
                        Direction,
                        @mod(rng.random().int(u8), 4),
                    )) {
                        .left => WorldPosition{
                            .x = monster.position.x - 1,
                            .y = monster.position.y,
                        },
                        .right => WorldPosition{
                            .x = monster.position.x + 1,
                            .y = monster.position.y,
                        },
                        .up => WorldPosition{
                            .x = monster.position.x,
                            .y = monster.position.y - 1,
                        },
                        .down => WorldPosition{
                            .x = monster.position.x,
                            .y = monster.position.y + 1,
                        },
                    };
                    if (new_pos.x > 0 and
                        new_pos.x < world_size - 1 and
                        new_pos.y > 0 and
                        new_pos.y < world_size - 1 and
                        get_world_tile(state.world, new_pos) != .wall)
                    {
                        monster.position = new_pos;
                        valid_move = true;
                    }
                }
            }
        }
    }
}

pub fn update(pressed: u8, state: *State) bool {
    if (state.player.health <= 0) return true;

    if (pressed & w4.BUTTON_LEFT != 0) {
        if (state.player.position.x > 0) {
            const new_pos = WorldPosition{
                .x = state.player.position.x - 1,
                .y = state.player.position.y,
            };
            try_move(state, new_pos);
        }
    } else if (pressed & w4.BUTTON_RIGHT != 0) {
        if (state.player.position.x < world_size - 1) {
            const new_pos = WorldPosition{
                .x = state.player.position.x + 1,
                .y = state.player.position.y,
            };
            try_move(state, new_pos);
        }
    } else if (pressed & w4.BUTTON_UP != 0) {
        if (state.player.position.y > 0) {
            const new_pos = WorldPosition{
                .x = state.player.position.x,
                .y = state.player.position.y - 1,
            };
            try_move(state, new_pos);
        }
    } else if (pressed & w4.BUTTON_DOWN != 0) {
        if (state.player.position.y < world_size - 1) {
            const new_pos = WorldPosition{
                .x = state.player.position.x,
                .y = state.player.position.y + 1,
            };
            try_move(state, new_pos);
        }
    }

    { // draw world
        var pos: WorldPosition = .{ .x = 0, .y = 0 };
        while (pos.x < world_size) : (pos.x += 1) {
            pos.y = 0;
            while (pos.y < world_size) : (pos.y += 1) {
                const screen_pos = world_to_screen(pos);
                switch (get_world_tile(state.world, pos)) {
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
            const screen_pos = world_to_screen(monster.position);
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
        const screen_pos = world_to_screen(state.player.position);
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
