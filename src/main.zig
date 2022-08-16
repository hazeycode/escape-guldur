const w4 = @import("wasm4.zig");

const menu = @import("menu.zig");
const game = @import("game.zig");

var state = struct {
    mode: enum { menu, game } = .menu,
    game_state: game.State = undefined,
}{};

export fn start() void {
    game.reset(&state.game_state);
}

export fn update() void {
    switch (state.mode) {
        .menu => menu.update(&state),
        .game => game.update(&state.game_state),
    }
}
