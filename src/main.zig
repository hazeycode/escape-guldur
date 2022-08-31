const w4 = @import("wasm4.zig");
const w4_util = @import("wasm4_util.zig");

const data = @import("data.zig");
const gfx = @import("gfx.zig").with_data(data);
const sfx = @import("sfx.zig");

const util = struct {
    pub inline fn trace(str: []const u8) void {
        w4.trace(str);
    }

    pub inline fn tracef(template: [*:0]const u8, args: anytype) void {
        w4.tracef(template, args);
    }
};

const game = @import("game.zig").Game(gfx, sfx, util, data);

var state = game.State{};
var prev_gamepad: u8 = 0;

export fn start() void {
    gfx.init();
}

export fn update() void {
    const gamepad = w4.GAMEPAD1.*;
    const pressed = gamepad & (gamepad ^ prev_gamepad);
    prev_gamepad = gamepad;

    const input = game.ButtonPressEvent{
        .left = if (pressed & w4.BUTTON_LEFT > 0) 1 else 0,
        .right = if (pressed & w4.BUTTON_RIGHT > 0) 1 else 0,
        .up = if (pressed & w4.BUTTON_UP > 0) 1 else 0,
        .down = if (pressed & w4.BUTTON_DOWN > 0) 1 else 0,
        .action_1 = if (pressed & w4.BUTTON_1 > 0) 1 else 0,
        .action_2 = if (pressed & w4.BUTTON_2 > 0) 1 else 0,
    };

    game.update(&state, input);

    gfx.frame_counter += 1;
}
