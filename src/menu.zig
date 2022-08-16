const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

pub fn update(state: anytype) void {
    wasm4_util.text_centered(
        "GAME NAME",
        @divTrunc(w4.SCREEN_SIZE, 3),
    );

    wasm4_util.text_centered(
        "PRESS \x80 TO START",
        @divTrunc(w4.SCREEN_SIZE, 3) * 2,
    );

    const gamepad = w4.GAMEPAD1.*;
    if (gamepad & w4.BUTTON_1 != 0) {
        w4.tone(440 | (880 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
        state.mode = .game;
    }
}
