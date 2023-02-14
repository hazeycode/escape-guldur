const w4 = @import("wasm4.zig");

const game = @import("game.zig");

var prev_gamepad: u8 = 0;

export fn start() void {
    game.init();
}

export fn update() void {
    const gamepad = w4.GAMEPAD1.*;
    const pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    const input = game.ButtonPressEvent{
        .left = (pressed & w4.BUTTON_LEFT > 0),
        .right = (pressed & w4.BUTTON_RIGHT > 0),
        .up = (pressed & w4.BUTTON_UP > 0),
        .down = (pressed & w4.BUTTON_DOWN > 0),
        .action_1 = (pressed & w4.BUTTON_1 > 0),
        .action_2 = (pressed & w4.BUTTON_2 > 0),
    };

    game.update(input);
}
