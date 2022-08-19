const w4 = @import("wasm4.zig");
const wasm4_util = @import("wasm4_util.zig");

pub fn update(pressed: u8) bool {
    w4.DRAW_COLORS.* = 0x04;

    wasm4_util.text_centered(
        "GAME NAME",
        @divTrunc(w4.SCREEN_SIZE, 3),
    );

    wasm4_util.text_centered(
        "PRESS \x80 TO START",
        @divTrunc(w4.SCREEN_SIZE, 3) * 2,
    );

    if (pressed & w4.BUTTON_1 != 0) {
        w4.tone(440 | (880 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
        return true;
    }

    return false;
}
