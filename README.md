# Escape Guldur

A minimalistic "retro action RPG" for the [WASM-4](https://wasm4.org/) fantasy console.

Originally made for [WASM-4 Jam #2](https://itch.io/jam/wasm4-v2).

[Play on itch.io!](https://hazeycode.itch.io/escape-guldur)

<p float="left">
<img src="https://img.itch.zone/aW1nLzk5NzcxOTgucG5n/original/YTwG%2FT.png" alt="screenshot" width="240"/>
<img src="https://img.itch.zone/aW1hZ2UvMTY3Mjc1OC85OTc2OTU0LnBuZw==/250x600/gOUx0S.png" alt="screenshot" width="240"/>
</p>

## Building

To start a dev shell using [Nix](https://nixos.org), just type:
```shell
nix develop
```

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
w4 run ./zig-out/bin/cart_opt.wasm
```

## Distribution
Bundle into an HTML file for publishing:
```shell
w4 bundle ./zig-out/bin/cart_opt.wasm --title "Escape Guldur" --html ./escape_guldur.html
```

To publish to wasmer.io, first update wapm.toml. Then remember your username and password and use `wapm`:
```shell
wapm login
wapm publish
```
