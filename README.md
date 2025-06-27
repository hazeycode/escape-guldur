# Escape Guldur

A minimalistic "retro action RPG" for the [WASM-4](https://wasm4.org/) fantasy console.

Originally made for [WASM-4 Jam #2](https://itch.io/jam/wasm4-v2).

[Play on itch.io!](https://hazeycode.itch.io/escape-guldur)

<p float="left">
<img src="https://img.itch.zone/aW1nLzk5NzcxOTgucG5n/original/YTwG%2FT.png" alt="screenshot" width="240"/>
<img src="https://img.itch.zone/aW1hZ2UvMTY3Mjc1OC85OTc2OTU0LnBuZw==/250x600/gOUx0S.png" alt="screenshot" width="240"/>
</p>

## Building

#### Requirements
- [Zig](https://github.com/ziglang/zig) toolchain ([anyzig](https://github.com/marler8997/anyzig) is recommended)
- [WASM-4](https://wasm4.org/docs/getting-started/setup)
- [wasm-opt](https://www.npmjs.com/package/wasm-opt) (release builds only)

Build and run a native (debug) executable:
```shell
zig build run-native
```

Produce a size-optimised release build (zig-out/lib/opt.wasm):
```shell
zig build release -Doptimize=ReleaseSmall
```

Load and run in your browser:
```shell
w4 run zig-out/lib/opt.wasm
```

## Distribution
```shell
cp zig-out/lib.opt.wasm game.wasm
wapm login
wapm publish

w4 bundle game.wasm --title "Escape Guldur" --html escape_guldur.html
```
