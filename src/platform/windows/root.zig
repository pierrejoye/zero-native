const geometry = @import("geometry");
const platform_mod = @import("../root.zig");

pub const Error = error{
    UnsupportedBackend,
};

pub const WindowsPlatform = struct {
    pub fn init(title: []const u8, size: geometry.SizeF) Error!WindowsPlatform {
        _ = title;
        _ = size;
        return error.UnsupportedBackend;
    }

    pub fn initWithEngine(title: []const u8, size: geometry.SizeF, web_engine: platform_mod.WebEngine) Error!WindowsPlatform {
        _ = web_engine;
        return init(title, size);
    }

    pub fn initWithOptions(size: geometry.SizeF, web_engine: platform_mod.WebEngine, app_info: platform_mod.AppInfo) Error!WindowsPlatform {
        _ = web_engine;
        return init(app_info.app_name, size);
    }
};

test "windows platform explicitly reports unsupported backend" {
    try @import("std").testing.expectError(error.UnsupportedBackend, WindowsPlatform.init("test", geometry.SizeF.init(640, 480)));
}
