const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const menu = @import("menu.zig");
const game = @import("game.zig");

const Screen = enum { menu, game, dead, win };

var state = struct {
    screen: Screen = .menu,
    menu_state: menu.State = .main,
    game_state: game.State = undefined,
}{};

var prev_gamepad: u8 = 0;

export fn start() void {
    w4.PALETTE.* = .{ // 2BIT DEMICHROME PALETTE (https://lospec.com/palette-list/2bit-demichrome)
        0x211e20,
        0x555568,
        0xa0a08b,
        0xe9efec,
    };
}

export fn update() void {
    const gamepad = w4.GAMEPAD1.*;
    const pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    switch (state.screen) {
        .menu => menu.update(&state, pressed),
        .game => game.update(&state, pressed),
        .dead => simple_screen("YOU DIED", pressed, .menu, null),
        .win => simple_screen("YOU ESCAPED", pressed, .menu, null),
    }
}

fn simple_screen(
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
