pub fn Menus(gfx: anytype, sfx: anytype) type {
    return struct {
        pub fn title(gfx: anytype, sfx: anytype) void {
            gfx.draw_title_menu();

            if (input.pressed.action_1 > 0) {
                sfx.walk();
                global_state.screen = .game;
                global_state.game_state.reset();
                global_state.game_state.load_level(0);
            } else if (input.pressed.action_2 > 0) {
                sfx.walk();
                global_state.menu_state = .controls;
            }
        }

        pub fn controls(gfx: anytype, sfx) void {
            gfx.draw_controls();

            if (input.pressed.action_1 + input.pressed.action_2 > 0) {
                sfx.walk();
                global_state.menu_state = .main;
            }
        }

        pub fn simple_screen(
            text_str: []const u8,
            pressed: u8,
            advance_screen: Screen,
            maybe_retreat_screen: ?Screen,
        ) void {
            w4.DRAW_COLORS.* = 0x04;

            w4_util.text_centered(text_str, w4.SCREEN_SIZE / 2);

            if (pressed & w4.BUTTON_1 != 0) {
                w4.tone(440 | (880 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
                state.screen = advance_screen;
                return;
            }

            if (maybe_retreat_screen) |retreat_screen| {
                if (pressed & w4.BUTTON_2 != 0) {
                    w4.tone(440 | (220 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
                    state.screen = retreat_screen;
                }
            }
        }
    };
}
