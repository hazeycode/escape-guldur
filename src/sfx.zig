const play_tone = @import("platform").AudioPlayback.play_tone;

pub fn walk() void {
    play_tone(.{
        .channel = .triangle,
        .freq1 = 100,
        .freq2 = 230,
        .sustain = 2,
        .release = 4,
        .volume_sustain = 90,
        .volume_peak = 90,
    });
}

pub fn pickup() void {
    play_tone(.{
        .channel = .pulse1,
        .duty_cycle = .half,
        .freq1 = 200,
        .freq2 = 4400,
        .attack = 2,
        .decay = 1,
        .sustain = 8,
        .release = 4,
        .volume_sustain = 50,
        .volume_peak = 90,
    });
}

pub fn deal_damage() void {
    play_tone(.{
        .channel = .pulse1,
        .freq1 = 600,
        .freq2 = 220,
        .sustain = 2,
        .release = 4,
    });
    play_tone(.{
        .channel = .noise,
        .freq1 = 200,
        .freq2 = 200,
        .sustain = 2,
        .volume_sustain = 70,
        .volume_peak = 70,
    });
}

pub fn receive_damage() void {
    play_tone(.{
        .channel = .noise,
        .freq1 = 300,
        .freq2 = 300,
        .sustain = 2,
        .release = 4,
        .volume_sustain = 80,
        .volume_peak = 80,
    });
    play_tone(.{
        .channel = .triangle,
        .freq1 = 300,
        .freq2 = 100,
        .sustain = 2,
        .release = 4,
    });
}

pub fn destroy_wall() void {
    play_tone(.{
        .channel = .pulse2,
        .duty_cycle = .quarter,
        .freq1 = 70,
        .freq2 = 70,
        .sustain = 8,
        .release = 4,
        .volume_sustain = 50,
        .volume_peak = 50,
    });
    play_tone(.{
        .channel = .noise,
        .freq1 = 200,
        .freq2 = 200,
        .sustain = 8,
        .release = 4,
        .volume_sustain = 80,
        .volume_peak = 80,
    });
    play_tone(.{
        .channel = .pulse1,
        .freq1 = 90,
        .freq2 = 90,
        .sustain = 8,
        .release = 4,
        .volume_sustain = 70,
        .volume_peak = 70,
    });
}
