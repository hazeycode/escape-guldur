const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const world = @import("world.zig");
const sprites = @import("sprites.zig");

const tile_px_width = 8;
const tile_px_height = 8;

const ScreenPosition = struct { x: i32, y: i32 };

fn world_to_screen(location: world.Location, camera_location: world.Location) ScreenPosition {
    return .{
        .x = (location.x - camera_location.x) * tile_px_width + w4.SCREEN_SIZE / 2,
        .y = (location.y - camera_location.y) * tile_px_height + w4.SCREEN_SIZE / 2,
    };
}

pub fn draw_world(state: anytype) void {
    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world.size_x) : (location.x += 1) {
        defer location.y = 0;
        while (location.y < world.size_y) : (location.y += 1) {
            if (world.map_get_tile(state.world_vis_map, location) > 0) {
                switch (world.map_get_tile_kind(state.world_map, location)) {
                    .wall, .locked_door => {},
                    .door => {
                        w4.DRAW_COLORS.* = 0x03;
                        const screen_pos = world_to_screen(location, state.camera_location);
                        w4.blit(
                            &sprites.door,
                            screen_pos.x,
                            screen_pos.y,
                            tile_px_width,
                            tile_px_height,
                            w4.BLIT_1BPP,
                        );
                    },
                    else => {
                        w4.DRAW_COLORS.* = 0x43;
                        const screen_pos = world_to_screen(location, state.camera_location);
                        w4.blit(
                            &sprites.floor,
                            screen_pos.x,
                            screen_pos.y,
                            tile_px_width,
                            tile_px_height,
                            w4.BLIT_1BPP,
                        );
                    },
                }
            }
        }
    }
}

pub fn draw_enemies(state: anytype) void {
    w4.DRAW_COLORS.* = 0x02;

    for (state.monsters) |*monster| {
        if (monster.entity.health > 0 and
            world.map_get_tile(state.world_vis_map, monster.entity.location) > 0)
        {
            const screen_pos = world_to_screen(monster.entity.location, state.camera_location);
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
            world.map_get_tile(state.world_vis_map, fire_monster.entity.location) > 0)
        {
            const screen_pos = world_to_screen(fire_monster.entity.location, state.camera_location);
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

pub fn draw_pickups(state: anytype) void {
    w4.DRAW_COLORS.* = 0x40;

    for (state.pickups) |*pickup| {
        if (pickup.entity.health > 0 and world.map_get_tile(
            state.world_vis_map,
            pickup.entity.location,
        ) > 0) {
            const screen_pos = world_to_screen(pickup.entity.location, state.camera_location);
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

pub fn draw_player(state: anytype) void {
    w4.DRAW_COLORS.* = 0x20;

    const screen_pos = world_to_screen(state.player.entity.location, state.camera_location);
    w4.blit(
        &sprites.player,
        screen_pos.x,
        screen_pos.y,
        8,
        8,
        w4.BLIT_1BPP,
    );
}

pub fn draw_fire(state: anytype) void { // draw fire
    w4.DRAW_COLORS.* = 0x40;

    for (state.fire) |*fire| {
        if (fire.entity.health > 0 and world.map_get_tile(state.world_vis_map, fire.entity.location) > 0) {
            const screen_pos = world_to_screen(fire.entity.location, state.camera_location);
            w4.blit(
                &sprites.fire_big,
                screen_pos.x,
                screen_pos.y,
                8,
                8,
                w4.BLIT_1BPP,
            );
        }
        if (fire.path.length > 1) {
            const location = fire.path.locations[1];
            if (world.map_get_tile(state.world_vis_map, location) > 0) {
                const screen_pos = world_to_screen(location, state.camera_location);
                w4.blit(
                    &sprites.fire_small,
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

pub fn draw_hud(state: anytype) void {
    if (state.turn_state == .aim) {
        w4.DRAW_COLORS.* = 0x04;

        w4.text(if (state.action_target_count == 0) "NO TARGETS" else "AIM", 1, w4.SCREEN_SIZE - (8 + 1) * 2);

        var i: usize = 0;
        while (i < state.action_target_count) : (i += 1) {
            w4.DRAW_COLORS.* = 0x40;
            const screen_pos = world_to_screen(state.action_targets[i], state.camera_location);
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
