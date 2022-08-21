const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const sfx = @import("sfx.zig");

pub const State = enum { main, controls };

pub fn update(global_state: anytype, pressed: u8) void {
    if (@typeInfo(@TypeOf(global_state)) != .Pointer) {
        @compileError("global_state type must be a pointer");
    }

    w4.DRAW_COLORS.* = 0x04;

    switch (global_state.menu_state) {
        .main => {
            w4_util.text_centered("Escape Guldur", @divTrunc(w4.SCREEN_SIZE, 3));

            w4.text("\x80 START", 16, w4.SCREEN_SIZE - (8 + 4) * 2);

            w4.text("\x81 CONTROLS", 16, w4.SCREEN_SIZE - (8 + 4));

            if (pressed & w4.BUTTON_1 != 0) {
                sfx.menu_bip();
                global_state.screen = .game;
                global_state.game_state.reset();
                global_state.game_state.load_level(0);
            } else if (pressed & w4.BUTTON_2 != 0) {
                sfx.menu_bip();
                global_state.menu_state = .controls;
            }
        },
        .controls => {
            w4_util.text_centered("CONTROLS", 2);

            w4.text("\x84\x85\x86\x87 MOVE /", 10, 40 + (8 + 1) * 0);
            w4.text("     CHANGE TARGET", 10, 40 + (8 + 1) * 1);
            w4.text("\x80 AIM ITEM /", 10, 40 + (8 + 1) * 4);
            w4.text("  USE ITEM", 10, 40 + (8 + 1) * 5);
            w4.text("\x81 CYCLE ITEM /", 10, 40 + (8 + 1) * 8);
            w4.text("  CANCEL AIM", 10, 40 + (8 + 1) * 9);

            if (pressed & (w4.BUTTON_1 | w4.BUTTON_2) > 0) {
                sfx.menu_bip();
                global_state.menu_state = .main;
            }
        },
    }
}
