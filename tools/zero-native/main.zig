const std = @import("std");
const automation_cli = @import("automation.zig");
const tooling = @import("tooling");

const version = "0.1.2";

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len <= 1) return usage();

    const command = args[1];
    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        return usage();
    } else if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "version")) {
        std.debug.print("zero-native {s}\n", .{version});
    } else if (std.mem.eql(u8, command, "init")) {
        const destination = positionalArg(args[2..]) orelse return fail("usage: zero-native init <path> --frontend <next|vite|react|svelte|vue>");
        const frontend_str = try flagValue(args, "--frontend") orelse return fail("--frontend is required: next, vite, react, svelte, vue");
        const frontend = tooling.templates.Frontend.parse(frontend_str) orelse return fail("invalid --frontend value: use next, vite, react, svelte, or vue");
        try tooling.templates.writeDefaultApp(allocator, init.io, destination, .{ .app_name = std.fs.path.basename(destination), .frontend = frontend });
        std.debug.print("created zero-native app at {s} (frontend: {s})\n", .{ destination, frontend_str });
    } else if (std.mem.eql(u8, command, "doctor")) {
        try tooling.doctor.run(allocator, init.io, init.environ_map, args[2..]);
    } else if (std.mem.eql(u8, command, "cef")) {
        tooling.cef.run(allocator, init.io, init.environ_map, args[2..]) catch |err| switch (err) {
            error.InvalidArguments,
            error.UnsupportedPlatform,
            error.MissingLayout,
            error.CommandFailed,
            error.WrapperBuildFailed,
            => std.process.exit(1),
            else => return err,
        };
    } else if (std.mem.eql(u8, command, "validate")) {
        const path = if (args.len >= 3) args[2] else "app.zon";
        const result = try tooling.manifest.validateFile(allocator, init.io, path);
        tooling.manifest.printDiagnostic(result);
        if (!result.ok) return error.InvalidManifest;
    } else if (std.mem.eql(u8, command, "bundle-assets")) {
        const manifest_path = if (args.len >= 3) args[2] else "app.zon";
        const metadata = try tooling.manifest.readMetadata(allocator, init.io, manifest_path);
        const assets_dir = if (args.len >= 4) args[3] else if (metadata.frontend) |frontend| frontend.dist else "assets";
        const output_dir = if (args.len >= 5) args[4] else "zig-out/assets";
        const stats = try tooling.assets.bundle(allocator, init.io, assets_dir, output_dir);
        std.debug.print("bundled {d} assets into {s}\n", .{ stats.asset_count, output_dir });
    } else if (std.mem.eql(u8, command, "package")) {
        const manifest_path = try flagValue(args, "--manifest") orelse "app.zon";
        const metadata = try tooling.manifest.readMetadata(allocator, init.io, manifest_path);
        const target_name = try flagValue(args, "--target") orelse "macos";
        const target = tooling.package.PackageTarget.parse(target_name) orelse return fail("invalid package target");
        const web_engine_override = if (try flagValue(args, "--web-engine")) |value|
            tooling.web_engine.Engine.parse(value) orelse return fail("invalid web engine")
        else
            null;
        const web_engine = try tooling.web_engine.resolve(.{ .web_engine = metadata.web_engine, .cef = metadata.cef }, .{
            .web_engine = web_engine_override,
            .cef_dir = try flagValue(args, "--cef-dir"),
            .cef_auto_install = if (flagBool(args, "--cef-auto-install")) true else null,
        });
        const signing_name = try flagValue(args, "--signing") orelse "none";
        const signing = tooling.package.SigningMode.parse(signing_name) orelse return fail("invalid signing mode");
        const output_dir = try flagValue(args, "--output") orelse if (args.len >= 3 and args[2].len > 0 and args[2][0] != '-') args[2] else "zig-out/package/zero-native-local.app";
        const archive = flagBool(args, "--archive");
        if (web_engine.engine == .chromium and web_engine.cef_auto_install) {
            try tooling.cef.run(allocator, init.io, init.environ_map, &.{ "install", "--dir", web_engine.cef_dir });
        }
        const stats = try tooling.package.createPackage(allocator, init.io, .{
            .metadata = metadata,
            .target = target,
            .optimize = try flagValue(args, "--optimize") orelse "Debug",
            .output_path = output_dir,
            .binary_path = try flagValue(args, "--binary"),
            .assets_dir = try flagValue(args, "--assets") orelse if (metadata.frontend) |frontend| frontend.dist else "assets",
            .frontend = metadata.frontend,
            .web_engine = web_engine.engine,
            .cef_dir = web_engine.cef_dir,
            .signing = .{ .mode = signing, .identity = try flagValue(args, "--identity"), .entitlements = try flagValue(args, "--entitlements"), .team_id = try flagValue(args, "--team-id") },
            .archive = archive,
        });
        tooling.package.printDiagnostic(stats);
    } else if (std.mem.eql(u8, command, "dev")) {
        const manifest_path = try flagValue(args, "--manifest") orelse "app.zon";
        const metadata = try tooling.manifest.readMetadata(allocator, init.io, manifest_path);
        const command_override = if (try flagValue(args, "--command")) |value| try splitCommand(allocator, value) else null;
        try tooling.dev.run(allocator, init.io, .{
            .metadata = metadata,
            .base_env = init.environ_map,
            .binary_path = try flagValue(args, "--binary"),
            .url_override = try flagValue(args, "--url"),
            .command_override = command_override,
            .timeout_ms = if (try flagValue(args, "--timeout-ms")) |value| try std.fmt.parseUnsigned(u32, value, 10) else null,
        });
    } else if (std.mem.eql(u8, command, "package-windows")) {
        try packageShortcut(allocator, init.io, args, .windows, "zig-out/package/windows");
    } else if (std.mem.eql(u8, command, "package-linux")) {
        try packageShortcut(allocator, init.io, args, .linux, "zig-out/package/linux");
    } else if (std.mem.eql(u8, command, "package-ios")) {
        const metadata = try tooling.manifest.readMetadata(allocator, init.io, try flagValue(args, "--manifest") orelse "app.zon");
        const web_engine = try tooling.web_engine.resolve(.{ .web_engine = metadata.web_engine, .cef = metadata.cef }, .{});
        const stats = try tooling.package.createPackage(allocator, init.io, .{
            .metadata = metadata,
            .target = .ios,
            .output_path = try flagValue(args, "--output") orelse if (args.len >= 3 and args[2].len > 0 and args[2][0] != '-') args[2] else "zig-out/mobile/ios",
            .binary_path = try flagValue(args, "--binary"),
            .assets_dir = try flagValue(args, "--assets") orelse if (metadata.frontend) |frontend| frontend.dist else "assets",
            .frontend = metadata.frontend,
            .web_engine = web_engine.engine,
            .cef_dir = web_engine.cef_dir,
        });
        tooling.package.printDiagnostic(stats);
    } else if (std.mem.eql(u8, command, "package-android")) {
        const metadata = try tooling.manifest.readMetadata(allocator, init.io, try flagValue(args, "--manifest") orelse "app.zon");
        const web_engine = try tooling.web_engine.resolve(.{ .web_engine = metadata.web_engine, .cef = metadata.cef }, .{});
        const stats = try tooling.package.createPackage(allocator, init.io, .{
            .metadata = metadata,
            .target = .android,
            .output_path = try flagValue(args, "--output") orelse if (args.len >= 3 and args[2].len > 0 and args[2][0] != '-') args[2] else "zig-out/mobile/android",
            .binary_path = try flagValue(args, "--binary"),
            .assets_dir = try flagValue(args, "--assets") orelse if (metadata.frontend) |frontend| frontend.dist else "assets",
            .frontend = metadata.frontend,
            .web_engine = web_engine.engine,
            .cef_dir = web_engine.cef_dir,
        });
        tooling.package.printDiagnostic(stats);
    } else if (std.mem.eql(u8, command, "automate")) {
        try automation_cli.run(allocator, init.io, args[2..]);
    } else {
        return usage();
    }
}

fn usage() void {
    std.debug.print(
        \\usage: zero-native <command>
        \\
        \\commands:
        \\  init <path> --frontend <next|vite|react|svelte|vue>
        \\  cef install|path|doctor [--dir path] [--version version] [--source prepared|official] [--force]
        \\  doctor [--strict] [--manifest app.zon] [--web-engine system|chromium] [--cef-dir path] [--cef-auto-install]
        \\  validate [app.zon]
        \\  bundle-assets [app.zon] [assets] [output]
        \\  package [--target macos] [--output path] [--binary path] [--assets path] [--web-engine system|chromium] [--cef-dir path] [--cef-auto-install] [--signing none|adhoc|identity] [--identity name] [--entitlements path] [--team-id id] [--archive]
        \\  dev [--manifest app.zon] --binary path [--url http://127.0.0.1:5173/] [--command "npm run dev"] [--timeout-ms 30000]
        \\  package-windows [--output path] [--binary path]
        \\  package-linux [--output path] [--binary path]
        \\  package-ios [--output path] [--binary path]
        \\  package-android [--output path] [--binary path]
        \\  automate <command>
        \\  version
        \\
    , .{});
}

fn fail(message: []const u8) error{InvalidArguments} {
    std.debug.print("{s}\n", .{message});
    return error.InvalidArguments;
}

fn flagValue(args: []const []const u8, name: []const u8) error{MissingFlagValue}!?[]const u8 {
    for (args, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, name)) {
            if (index + 1 < args.len) return args[index + 1];
            return error.MissingFlagValue;
        }
    }
    return null;
}

fn flagBool(args: []const []const u8, name: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, name)) return true;
    }
    return false;
}

fn positionalArg(args: []const []const u8) ?[]const u8 {
    var skip_next = false;
    for (args) |arg| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--frontend") or
                std.mem.eql(u8, arg, "--manifest") or
                std.mem.eql(u8, arg, "--target") or
                std.mem.eql(u8, arg, "--output") or
                std.mem.eql(u8, arg, "--binary") or
                std.mem.eql(u8, arg, "--assets") or
                std.mem.eql(u8, arg, "--web-engine") or
                std.mem.eql(u8, arg, "--cef-dir") or
                std.mem.eql(u8, arg, "--signing") or
                std.mem.eql(u8, arg, "--identity") or
                std.mem.eql(u8, arg, "--entitlements") or
                std.mem.eql(u8, arg, "--team-id") or
                std.mem.eql(u8, arg, "--command") or
                std.mem.eql(u8, arg, "--url") or
                std.mem.eql(u8, arg, "--timeout-ms"))
            {
                skip_next = true;
            }
            continue;
        }
        return arg;
    }
    return null;
}

fn splitCommand(allocator: std.mem.Allocator, value: []const u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer parts.deinit(allocator);
    var tokens = std.mem.tokenizeScalar(u8, value, ' ');
    while (tokens.next()) |token| {
        try parts.append(allocator, try allocator.dupe(u8, token));
    }
    return parts.toOwnedSlice(allocator);
}

fn packageShortcut(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8, target: tooling.package.PackageTarget, default_output: []const u8) !void {
    const metadata = try tooling.manifest.readMetadata(allocator, io, try flagValue(args, "--manifest") orelse "app.zon");
    const web_engine = try tooling.web_engine.resolve(.{ .web_engine = metadata.web_engine, .cef = metadata.cef }, .{});
    const stats = try tooling.package.createPackage(allocator, io, .{
        .metadata = metadata,
        .target = target,
        .output_path = try flagValue(args, "--output") orelse default_output,
        .binary_path = try flagValue(args, "--binary"),
        .assets_dir = try flagValue(args, "--assets") orelse if (metadata.frontend) |frontend| frontend.dist else "assets",
        .frontend = metadata.frontend,
        .web_engine = web_engine.engine,
        .cef_dir = web_engine.cef_dir,
    });
    tooling.package.printDiagnostic(stats);
}
