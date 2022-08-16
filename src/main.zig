const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

const menu = @import("menu.zig");
const game = @import("game.zig");

var state = struct {
    mode: enum { menu, game, dead } = .menu,
    game_state: game.State = undefined,
}{};

var prev_gamepad: u8 = 0;

export fn update() void {
    const gamepad = w4.GAMEPAD1.*;
    const pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    switch (state.mode) {
        .menu => if (menu.update(pressed)) {
            game.reset(&state.game_state);
            state.mode = .game;
        },
        .game => {
            if (game.update(pressed, &state.game_state)) {
                state.mode = .dead;
            }
        },
        .dead => {
            wasm4_util.text_centered("YOU DIED", w4.SCREEN_SIZE / 2);
            if (pressed & w4.BUTTON_1 != 0) {
                w4.tone(440 | (880 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
                state.mode = .menu;
            }
        },
    }
}
