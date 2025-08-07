const std = @import("std");
const dvui = @import("dvui");

const Options = dvui.Options;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const ImageWidget2 = @This();
const root = @import("../root.zig");
const Image = root.Image;

wd: WidgetData = undefined,
name: []const u8 = undefined,
img_bytes: []u8 = undefined,
img_width: u32 = undefined,
img_height: u32 = undefined,

/// img_bytes are rgba pma
pub fn image(src: std.builtin.SourceLocation, name: []const u8, img_bytes: []u8, img_width: u32, img_height: u32, opts: Options) !void {
    _ = dvui.image(src, .{
        .bytes = .{
            .pixels = .{
                .bytes = dvui.RGBAPixelsPMA.cast(img_bytes),
                .width = img_width,
                .height = img_height,
            },
        },
        .name = name,
    }, opts);
}

pub fn invalidate_cache(rgba_normal: []const u8) void {
    dvui.TextureCacheEntry.invalidateCachedImage(.{ .pixels = .{ .bytes = dvui.RGBAPixelsPMA.cast(@constCast(rgba_normal)), .height = 0, .width = 0 } });
}

// const root = @import("../lib.zig");
// const musicfiles = @import("musicfiles");
// const Image = musicfiles.Image;

pub fn draw_square_image_centered_in_rect(img: *Image, rect: dvui.Rect, id: u32) !void {
    const max_wh = @max(rect.h, rect.w);
    const dx = 0.5 * (rect.w - max_wh);
    const dy = 0.5 * (rect.h - max_wh);
    const r = dvui.Rect{
        .w = max_wh,
        .h = max_wh,
        .x = rect.x + dx,
        .y = rect.y + dy,
    };
    try ImageWidget2.image(
        @src(),
        "myimage",
        @constCast(img.get_pixel_data()),
        @intCast(img.get_width()),
        @intCast(img.get_height()),
        .{
            .rect = r,
            .max_size_content = dvui.Options.MaxSize{
                .h = r.h,
                .w = r.w,
            },
            .min_size_content = dvui.Size{
                .h = r.h,
                .w = r.w,
            },
            .id_extra = id,
        },
    );
}

pub fn draw_img(src: std.builtin.SourceLocation, name: []const u8, img: *Image, rect: dvui.Rect, opts: dvui.Options) !void {
    var op = opts;
    if (op.rect == null) {
        op.rect = rect;
    }
    if (op.max_size_content == null) {
        op.max_size_content = .{
            .h = rect.h,
            .w = rect.w,
        };
    }
    if (op.min_size_content == null) {
        op.min_size_content = .{
            .h = rect.h,
            .w = rect.w,
        };
    }
    try ImageWidget2.image(
        src,
        name,
        @constCast(img.get_pixel_data()),
        @intCast(img.get_width()),
        @intCast(img.get_height()),
        op,
    );
}
