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

pub fn rgba_u8_slice_to_img_source(img_bytes: []u8, img_width: u32, img_height: u32) dvui.ImageSource {
    return .{
        .pixelsPMA = .{
            .rgba = dvui.Color.PMA.sliceFromRGBA(img_bytes),
            .width = img_width,
            .height = img_height,
        },
    };
}

pub fn invalidate_cache(img_source: dvui.ImageSource) void {
    const key = img_source.hash();
    dvui.textureInvalidateCache(key);
}
pub fn invalidate(img: *Image) void {
    const key = image_to_img_src(img).hash();
    dvui.textureInvalidateCache(key);
}

// const root = @import("../lib.zig");
// const musicfiles = @import("musicfiles");
// const Image = musicfiles.Image;
pub fn image_to_img_src(img: *Image) dvui.ImageSource {
    return rgba_u8_slice_to_img_source(
        @constCast(img.get_pixel_data()),
        @intCast(img.get_width()),
        @intCast(img.get_height()),
    );
}

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
    _ = dvui.image(
        @src(),
        .{ .source = image_to_img_src(img) },
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

pub fn draw_img(src: std.builtin.SourceLocation, img: *Image, rect: dvui.Rect, opts: dvui.Options) !void {
    const imsrc = ImageWidget2.image_to_img_src(img);
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
    _ = dvui.image(src, .{ .source = imsrc }, op);
}
