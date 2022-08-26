# Escape Guldur

A retro action-RPG written in [Zig](https://ziglang.org/) for [WASM-4 Jam #2](https://itch.io/jam/wasm4-v2).

## Building

### System requirements
- [Zig 0.9.1](https://github.com/ziglang/zig/releases/tag/0.9.1)
- [wasm-opt](https://www.npmjs.com/package/wasm-opt)
- [wasm-4](https://wasm4.org/)

Build the cart (debug) by running:

```shell
zig build
```

Then run it with:

```shell
w4 run zig-out/lib/cart.wasm
```

or

```shell
w4 watch zig-out/lib/cart.wasm
```

Produce a size-optimised release build by running:

```shell
zig build release
```

And remember to test it!
