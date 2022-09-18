const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const tests = b.addTest("src/tests.zig");
    tests.setBuildMode(b.standardReleaseOptions());

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&tests.step);
    
    try build_wasm4(b);
}

fn build_wasm4(b: *std.build.Builder) !void {
    const cart = b.addSharedLibrary("cart", "src/main_wasm4.zig", .unversioned);
    cart.setBuildMode(b.standardReleaseOptions());
    cart.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    cart.import_memory = true;
    cart.initial_memory = 65536;
    cart.max_memory = 65536;
    cart.stack_size = 14752;
    cart.export_symbol_names = &[_][]const u8{ "start", "update" };
    cart.install();
    
    cart.addPackage(.{
        .name = "platform",
        .source = .{ .path = thisDir() ++ "/src/platform_wasm4.zig" },
    });
    
    cart.addPackage(.{
        .name = "data",
        .source = .{ .path = thisDir() ++ "/src/data.zig" },
    });

    const prefix = b.getInstallPath(.lib, "");
    const cart_opt = b.addSystemCommand(&[_][]const u8{
        "wasm-opt",
        "-Oz",
        "--strip-debug",
        "--strip-producers",
        "--zero-filled-memory",
    });

    cart_opt.addArtifactArg(cart);
    const wasmopt_out = try std.fs.path.join(b.allocator, &.{ prefix, "cart_opt.wasm" });
    defer b.allocator.free(wasmopt_out);
    cart_opt.addArgs(&.{ "--output", wasmopt_out });

    const release_build = b.step("release", "Run wasm-opt on cart.wasm, producing opt.wasm");
    release_build.dependOn(&cart.step);
    release_build.dependOn(&cart_opt.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}