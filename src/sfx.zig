const w4 = @import("wasm4.zig");

pub fn walk() void {
    w4.tone(100 | (230 << 16), 2 | (4 << 8), 90, w4.TONE_TRIANGLE);
}

pub fn pickup() void {
    w4.tone(300 | (1600 << 16), (4 << 8) | (8 << 0) | (1 << 16) | (2 << 24), 100, w4.TONE_PULSE1);
}

pub fn deal_damage() void {
    w4.tone(600 | (220 << 16), 2 | (4 << 8), 100, w4.TONE_PULSE1);
    w4.tone(200, 2, 70, w4.TONE_NOISE);
}

pub fn receive_damage() void {
    w4.tone(300, 2 | (4 << 8), 80, w4.TONE_NOISE);
    w4.tone(300 | (100 << 16), 2 | (4 << 8), 100, w4.TONE_TRIANGLE);
}
