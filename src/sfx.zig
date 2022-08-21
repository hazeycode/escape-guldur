const w4 = @import("wasm4.zig");

pub fn menu_bip() void {
    w4.tone(440 | (880 << 16), 2 | (4 << 8), 80, w4.TONE_PULSE1);
}

pub fn walk() void {
    w4.tone(220, 2 | (4 << 8), 70, w4.TONE_TRIANGLE);
}

pub fn pickup() void {
    w4.tone(300 | (2000 << 16), (10 << 8) | (10 << 0) | (1 << 16) | (1 << 24), 100, w4.TONE_PULSE1);
}

pub fn deal_damage() void {
    w4.tone(880 | (440 << 16), 2 | (4 << 8), 100, w4.TONE_PULSE1);
}
