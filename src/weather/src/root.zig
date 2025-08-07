const std = @import("std");

pub const util = @import("http-request.zig");
pub const weather = @import("open-meteo.zig");
pub const render = @import("render.zig");
pub const Image = @import("image");
pub const z2d = @import("../../root.zig").z2d;
pub const interpolation2 = @import("interpolation2.zig");

test "all" {
    _ = .{
        // weather,
        render,
        // util,
        // interpolation2,
    };
}
