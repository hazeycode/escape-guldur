const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const world_tile_size = 8;
const world_size = w4.SCREEN_SIZE / world_tile_size;

const World = [world_size][world_size]u8;

const WorldTileEnum = enum(u8) {
    floor,
    wall,
};

const WorldPosition = struct { x: u8, y: u8 };

pub const State = struct {
    world: World,
    player_pos: WorldPosition,
    turn: u8,
};

const ScreenPosition = struct { x: i32, y: i32 };

const player_sprite = [8]u8{
    0b11000011,
    0b10000001,
    0b00100100,
    0b00100100,
    0b00000000,
    0b00100100,
    0b10011001,
    0b11000011,
};

const wall_sprite = [8]u8{
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
};

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
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    });

    state.player_pos = .{ .x = 3, .y = 3 };

    state.turn = 0;
}

fn get_world_tile(world: *World, pos: WorldPosition) WorldTileEnum {
    return @intToEnum(
        WorldTileEnum,
        world[@intCast(usize, pos.x)][@intCast(usize, pos.y)],
    );
}

fn try_move(state: *State, pos: WorldPosition) void {
    switch (get_world_tile(&state.world, pos)) {
        .floor => state.player_pos = pos,
        else => {},
    }
}

var prev_gamepad: u8 = 0;

pub fn update(state: *State) void {
    const gamepad = w4.GAMEPAD1.*;
    const pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    if (pressed & w4.BUTTON_LEFT != 0) {
        if (state.player_pos.x > 0) {
            const new_pos = WorldPosition{
                .x = state.player_pos.x - 1,
                .y = state.player_pos.y,
            };
            try_move(state, new_pos);
        }
    }

    if (pressed & w4.BUTTON_RIGHT != 0) {
        if (state.player_pos.x < world_size - 1) {
            const new_pos = WorldPosition{
                .x = state.player_pos.x + 1,
                .y = state.player_pos.y,
            };
            try_move(state, new_pos);
        }
    }

    if (pressed & w4.BUTTON_UP != 0) {
        if (state.player_pos.y > 0) {
            const new_pos = WorldPosition{
                .x = state.player_pos.x,
                .y = state.player_pos.y - 1,
            };
            try_move(state, new_pos);
        }
    }

    if (pressed & w4.BUTTON_DOWN != 0) {
        if (state.player_pos.y < world_size - 1) {
            const new_pos = WorldPosition{
                .x = state.player_pos.x,
                .y = state.player_pos.y + 1,
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
                switch (get_world_tile(&state.world, pos)) {
                    .wall => w4.blit(
                        &wall_sprite,
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

    { // draw player sprite
        const player_screen_pos = world_to_screen(state.player_pos);
        w4.blit(
            &player_sprite,
            player_screen_pos.x,
            player_screen_pos.y,
            8,
            8,
            w4.BLIT_1BPP,
        );
    }
}
