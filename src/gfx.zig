const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const world = @import("world.zig");

const tile_px_width = 10;
const tile_px_height = 10;

const ScreenPosition = struct { x: i32, y: i32 };

fn world_to_screen(location: world.Location, camera_location: world.Location) ScreenPosition {
    return .{
        .x = (location.x - camera_location.x) * tile_px_width + w4.SCREEN_SIZE / 2,
        .y = (location.y - camera_location.y) * tile_px_height + w4.SCREEN_SIZE / 2,
    };
}

pub fn draw_world(state: anytype, data: anytype) void {
    var location: world.Location = .{ .x = 0, .y = 0 };
    while (location.x < world.size_x) : (location.x += 1) {
        defer location.y = 0;
        while (location.y < world.size_y) : (location.y += 1) {
            if (world.map_get_tile(state.world_vis_map, location) > 0) {
                switch (world.map_get_tile_kind(state.world_map, location)) {
                    .wall, .locked_door => {},
                    .door => {
                        w4.DRAW_COLORS.* = 0x30;
                        const screen_pos = world_to_screen(location, state.camera_location);
                        w4.blit(
                            &data.Sprites.door,
                            screen_pos.x + 1,
                            screen_pos.y + 2,
                            8,
                            8,
                            w4.BLIT_1BPP,
                        );
                    },
                    else => {
                        // TODO(hazeycode): optimise floor drawing by deferring and rendering contiguous blocks
                        w4.DRAW_COLORS.* = 0x33;
                        const screen_pos = world_to_screen(location, state.camera_location);
                        w4.rect(screen_pos.x, screen_pos.y, tile_px_width, tile_px_height);
                    },
                }
            }
        }
    }
}

pub fn draw_enemies(state: anytype, data: anytype) void {
    w4.DRAW_COLORS.* = 0x02;

    for (state.monsters) |*monster| {
        if (monster.entity.health > 0 and
            world.map_get_tile(state.world_vis_map, monster.entity.location) > 0)
        {
            const screen_pos = world_to_screen(monster.entity.location, state.camera_location);
            w4.blit(
                &data.Sprites.monster,
                screen_pos.x + 1,
                screen_pos.y + 1,
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
                &data.Sprites.fire_monster,
                screen_pos.x + 1,
                screen_pos.y + 1,
                8,
                8,
                w4.BLIT_1BPP,
            );
        }
    }
}

pub fn draw_pickups(state: anytype, data: anytype) void {
    w4.DRAW_COLORS.* = 0x40;

    for (state.pickups) |*pickup| {
        if (pickup.entity.health > 0 and world.map_get_tile(
            state.world_vis_map,
            pickup.entity.location,
        ) > 0) {
            const screen_pos = world_to_screen(pickup.entity.location, state.camera_location);
            w4.blit(
                switch (pickup.kind) {
                    .health => &data.Sprites.heart,
                    .sword => &data.Sprites.sword,
                    .small_axe => &data.Sprites.small_axe,
                },
                screen_pos.x + 1,
                screen_pos.y + 1,
                8,
                8,
                w4.BLIT_1BPP,
            );
        }
    }
}

pub fn draw_player(state: anytype, data: anytype) void {
    w4.DRAW_COLORS.* = 0x20;

    const screen_pos = world_to_screen(state.player.entity.location, state.camera_location);
    w4.blit(
        &data.Sprites.player,
        screen_pos.x + 1,
        screen_pos.y + 1,
        8,
        8,
        w4.BLIT_1BPP,
    );
}

pub fn draw_fire(state: anytype, data: anytype) void { // draw fire
    w4.DRAW_COLORS.* = 0x40;

    for (state.fire) |*fire| {
        if (fire.entity.health == 0) {
            continue;
        }

        if (world.map_get_tile(state.world_vis_map, fire.entity.location) > 0) {
            const screen_pos = world_to_screen(fire.entity.location, state.camera_location);
            w4.blit(
                &data.Sprites.fire_big,
                screen_pos.x + 1,
                screen_pos.y + 1,
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
                    &data.Sprites.fire_small,
                    screen_pos.x + 1,
                    screen_pos.y + 1,
                    8,
                    8,
                    w4.BLIT_1BPP,
                );
            }
        }
    }
}

pub fn draw_hud(state: anytype, data: anytype) void {
    if (state.turn_state == .aim) {
        w4.DRAW_COLORS.* = 0x04;

        w4.text(if (state.action_target_count == 0) "NO TARGETS" else "AIM", 1, w4.SCREEN_SIZE - (8 + 1) * 2);

        var i: usize = 0;
        while (i < state.action_target_count) : (i += 1) {
            w4.DRAW_COLORS.* = 0x4444;
            const screen_pos = world_to_screen(state.action_targets[i], state.camera_location);
            w4.line(
                screen_pos.x,
                screen_pos.y + tile_px_height / 2 - 1,
                screen_pos.x + tile_px_width / 2 - 1,
                screen_pos.y,
            );
            w4.line(
                screen_pos.x + tile_px_width / 2,
                screen_pos.y,
                screen_pos.x + tile_px_width - 1,
                screen_pos.y + tile_px_height / 2 - 1,
            );
            w4.line(
                screen_pos.x + tile_px_width - 1,
                screen_pos.y + tile_px_height / 2,
                screen_pos.x + tile_px_width / 2,
                screen_pos.y + tile_px_height - 1,
            );
            w4.line(
                screen_pos.x + tile_px_width / 2 - 1,
                screen_pos.y + tile_px_height - 1,
                screen_pos.x,
                screen_pos.y + tile_px_height / 2,
            );
            if (i == state.action_target) {
                w4.hline(screen_pos.x, screen_pos.y, tile_px_width);
                w4.hline(screen_pos.x, screen_pos.y + tile_px_height - 1, tile_px_width);
                w4.vline(screen_pos.x, screen_pos.y, tile_px_width);
                w4.vline(screen_pos.x + tile_px_width - 1, screen_pos.y, tile_px_width);
            }
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
                    &data.Sprites.heart,
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

pub fn draw_screen_title(title_text: []const u8) void {
    w4.DRAW_COLORS.* = 0x04;
    w4_util.text_centered(title_text, @divTrunc(w4.SCREEN_SIZE, 4));
}

pub fn draw_stats(stats: anytype) void {
    w4.DRAW_COLORS.* = 0x03;

    {
        const postfix = " turns taken";
        const y = w4.SCREEN_SIZE / 3 * 2;
        const w = 8 * (count_digits_fast(stats.turns_taken) + 1 + postfix.len);
        var x = @intCast(i32, w4.SCREEN_SIZE / 2 - w / 2);
        x += draw_text_number(stats.turns_taken, x, y);
        x += 8;
        w4.text(postfix, x, y);
    }

    // {
    //     const y = w4.SCREEN_SIZE / 2 + 1;
    //     var x: i32 = 10;

    //     if (stats.elapsed_m > 99) {
    //         w4.text("> 99 minutes elapsed !?", x, y);
    //     } else {
    //         x += draw_text_number(@intCast(i32, stats.elapsed_m), x, y);
    //         w4.text(":", x, y);
    //         x += 8;
    //         x += draw_text_number(@intCast(i32, stats.elapsed_s), x, y);
    //         w4.text(" elapsed", x, y);
    //     }
    // }
}

pub fn draw_title_menu() void {
    w4.DRAW_COLORS.* = 0x04;
    w4_util.text_centered("Escape Guldur", @divTrunc(w4.SCREEN_SIZE, 3));
    w4.text("\x80 START", 16, w4.SCREEN_SIZE - (8 + 4) * 2);
    w4.text("\x81 CONTROLS", 16, w4.SCREEN_SIZE - (8 + 4));
}

pub fn draw_controls() void {
    w4.DRAW_COLORS.* = 0x04;
    w4_util.text_centered("CONTROLS", 2);
    w4.text("\x84\x85\x86\x87 MOVE /", 10, 40 + (8 + 1) * 0);
    w4.text("     CHANGE TARGET", 10, 40 + (8 + 1) * 1);
    w4.text("\x80 AIM ITEM /", 10, 40 + (8 + 1) * 4);
    w4.text("  USE ITEM", 10, 40 + (8 + 1) * 5);
    w4.text("\x81 CYCLE ITEM /", 10, 40 + (8 + 1) * 8);
    w4.text("  CANCEL AIM", 10, 40 + (8 + 1) * 9);
}

pub fn draw_text_number(number: i32, x: i32, y: i32) u16 {
    var dx: u16 = 0;

    if (number < 0) {
        w4.text("-", x + dx, y);
    }

    var n = @intCast(u16, if (number < 0) -number else number);
    while (true) {
        dx += 8;

        n = @divTrunc(n, 10);
        w4.text(&[_]u8{'0' + @truncate(u8, @mod(n, 10))}, x + dx, y);

        if (n == 0) break;
    }

    return dx;
}

fn count_digits_fast(number: i32) u16 {
    const n = if (number < 0) -number else number;
    return @as(u16, switch (n) {
        0...9 => 1,
        10...99 => 2,
        100...999 => 3,
        1000...9999 => 4,
        10000...99999 => 5,
        else => unreachable,
    }) + @as(u16, if (number < 0) 1 else 0);
}
