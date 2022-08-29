const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const std = @import("std");

const world = @import("world.zig");

pub fn with_data(data: anytype) type {
    return struct {
        pub const tile_px_width = 10;
        pub const tile_px_height = 9;
        pub const max_sprites = 32;

        const ScreenPosition = struct { x: i32, y: i32 };

        pub fn world_to_screen(
            location: world.Location,
            camera_location: world.Location,
        ) ScreenPosition {
            return .{
                .x = (location.x - camera_location.x) * tile_px_width + w4.SCREEN_SIZE / 2,
                .y = (location.y - camera_location.y) * tile_px_height + w4.SCREEN_SIZE / 2,
            };
        }

        pub const Sprite = struct {
            texture: data.Texture,
            draw_colours: u16,
            location: world.Location,
            flip_x: bool = false,
        };

        pub const SpriteList = struct {
            entries: [max_sprites]Sprite = undefined,
            entries_count: u32 = 0,

            pub fn push_sprite(self: *@This(), sprite: Sprite) void {
                if (self.entries_count == max_sprites) {
                    w4.trace("warning: no space for sprite");
                    return;
                }

                var i = self.entries_count;
                while (i > 0) : (i -= 1) {
                    if (self.entries[i].location.y <= sprite.location.y) {
                        var j = self.entries_count - 1;
                        while (j > i) : (j -= 1) {
                            self.entries[j] = self.entries[j - 1];
                        }
                        break;
                    }
                }

                self.entries[i] = sprite;
                self.entries_count += 1;
            }

            pub fn draw_shadows(self: @This(), camera_location: world.Location) void {
                for (self.entries[0..self.entries_count]) |sprite| {
                    w4.DRAW_COLORS.* = 0x11;
                    const screen_pos = world_to_screen(sprite.location, camera_location);
                    w4.oval(
                        screen_pos.x + 2,
                        screen_pos.y + tile_px_height / 2 - 2,
                        6,
                        2,
                    );
                }
            }

            pub fn draw(self: *@This(), camera_location: world.Location) void {
                for (self.entries[0..self.entries_count]) |sprite| {
                    const screen_pos = world_to_screen(
                        sprite.location,
                        camera_location,
                    );
                    w4.DRAW_COLORS.* = sprite.draw_colours;
                    var flags = w4.BLIT_1BPP;
                    if (sprite.flip_x) flags |= w4.BLIT_FLIP_X;
                    w4.blit(
                        sprite.texture.bytes,
                        screen_pos.x + (tile_px_width - sprite.texture.width) / 2,
                        (screen_pos.y + tile_px_height / 2) - sprite.texture.height,
                        sprite.texture.width,
                        sprite.texture.height,
                        flags,
                    );
                }
            }
        };

        pub fn draw_world(state: anytype) void {
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
                                    data.Texture.door.bytes,
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

        pub fn draw_fire(state: anytype) void { // draw fire
            w4.DRAW_COLORS.* = 0x40;

            for (state.fire) |*fire| {
                if (fire.entity.health == 0) {
                    continue;
                }

                if (world.map_get_tile(state.world_vis_map, fire.entity.location) > 0) {
                    const screen_pos = world_to_screen(
                        fire.entity.location,
                        state.camera_location,
                    );
                    w4.blit(
                        data.Texture.fire_big.bytes,
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
                            data.Texture.fire_small.bytes,
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

        pub fn draw_tile_markers(state: anytype) void {
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
                    screen_pos.y + tile_px_height / 2 - 1,
                    screen_pos.x + tile_px_width / 2,
                    screen_pos.y + tile_px_height - 2,
                );
                w4.line(
                    screen_pos.x + tile_px_width / 2 - 1,
                    screen_pos.y + tile_px_height - 2,
                    screen_pos.x,
                    screen_pos.y + tile_px_height / 2 - 1,
                );
            }
        }

        pub fn draw_hud(state: anytype) void {
            if (state.turn_state == .aim) {
                w4.DRAW_COLORS.* = 0x04;

                w4.text(
                    if (state.action_target_count == 0) "NO TARGETS" else "AIM",
                    1,
                    w4.SCREEN_SIZE - (8 + 1) * 2,
                );

                if (state.action_target_count > state.action_target) {
                    const screen_pos = world_to_screen(
                        state.action_targets[state.action_target],
                        state.camera_location,
                    );
                    w4.hline(
                        screen_pos.x - 1,
                        screen_pos.y - tile_px_height / 2,
                        tile_px_width + 1,
                    );
                    w4.hline(
                        screen_pos.x - 1,
                        screen_pos.y + tile_px_height - 2,
                        tile_px_width + 1,
                    );
                    w4.vline(
                        screen_pos.x - 1,
                        screen_pos.y - tile_px_height / 2,
                        tile_px_height + tile_px_height / 2 - 1,
                    );
                    w4.vline(
                        screen_pos.x + tile_px_width,
                        screen_pos.y - tile_px_height / 2,
                        tile_px_height + tile_px_height / 2 - 1,
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
                            data.Texture.heart.bytes,
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

            const number_abs = @intCast(u16, if (number < 0) -number else number);

            const num_digits = count_digits_fast(number_abs);

            var i: u16 = num_digits;
            var n = number_abs;
            var m: u16 = 0;
            while (i > 0) : (i -= 1) {
                dx += 8;

                n = @divTrunc(number_abs - m, std.math.pow(u16, 10, i - 1));
                m += n * std.math.pow(u16, 10, i - 1);

                const digit = '0' + @truncate(u8, n);
                w4.text(&[_]u8{digit}, x + dx, y);

                if (n == 0) break;
            }

            return dx;
        }
    };
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
