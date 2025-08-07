const std = @import("std");
const assert = std.debug.assert;
const expect = std.debug.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");

const dvui = @import("dvui");
pub const weather = root.weather;
const osmr = @import("osmr");
const fifoasync = @import("fifoasync");

const Texture = dvui.Texture;
const Image = root.Image;
const ASW = fifoasync.sched.ASNode;
const Task = fifoasync.sched.Task;
const Color = osmr.Color;
const Tailwind = osmr.Tailwind;
const latLonToTileF64 = weather.weather.latLonToTileF64;
const ImageWidget2 = @import("ImageWidget2.zig");
const latLonToTileF32 = weather.weather.latLonToTileF32;
const Cache = root.db;
pub const CACHE_NAME = "cache";

fn col(color: Color) dvui.Color {
    const r, const g, const b, const a = color.rgba();
    return dvui.Color{
        .a = a,
        .r = r,
        .g = g,
        .b = b,
    };
}

var debug_ch = true;
pub const MapContent = enum {
    basic,
    lines,
};
pub const RenderStyle = enum {
    color,
    black_and_white,
};
const debug = false;

fn tile_index(tx: f32, index: usize) i32 {
    const centered_floor: i32 = @intFromFloat(@floor(tx - 0.5));
    const ind: i32 = @intCast(index);
    return centered_floor + ind;
}
fn wrapped_tile_index(tx: f32, index: usize, z: u32) u32 {
    assert(z < 20);
    const n = std.math.pow(i32, 2.0, @intCast(z));
    const res: u32 = @intCast(tile_index(tx, index) + n);
    return @intCast(res % @as(u32, @intCast(n)));
}

/// NOTE the arena is freed in this function if you allocate anything beforehand it will also be freed
pub fn generate(pool: *std.Thread.Pool, arena: *std.heap.ArenaAllocator, db: *Cache, img: *Image, upd: UpdateParameter) !UpdateParameter {
    const alloc = arena.allocator();
    const tx, const ty = latLonToTileF32(upd.lat, upd.lon, @floatFromInt(upd.z));
    const otx, const oty = .{ tx - 0.5, ty - 0.5 };
    const image_size: f32 = @floatFromInt(img.get_width());

    const scale: f32 = @floatFromInt(img.get_width());
    const coldef = switch (upd.stil) {
        .color => osmr.Renderer.DefaultColor,
        .black_and_white => osmr.common.col_to_z2d_pixel_rgb(osmr.Color.Transparent),
    };
    for (0..2) |xi| {
        for (0..2) |yi| {
            const tile_x: f32 = @floatFromInt(tile_index(tx, xi));
            const tile_y: f32 = @floatFromInt(tile_index(ty, yi));
            const x = wrapped_tile_index(tx, xi, upd.z);
            const y = wrapped_tile_index(ty, yi, upd.z);

            const vp_rect = dvui.Rect{
                .h = image_size,
                .w = image_size,
                .x = 0,
                .y = 0,
            };
            var sw_rect = vp_rect;
            sw_rect.x += (tile_x - otx) * image_size;
            sw_rect.y += (tile_y - oty) * image_size;

            const intersection = vp_rect.intersect(sw_rect);

            const ylen: usize = @intFromFloat(intersection.h);
            const xlen: usize = @intFromFloat(intersection.w);

            const xstart: usize = @intFromFloat(intersection.x);
            const ystart: usize = @intFromFloat(intersection.y);

            const sxstartf: f32 = intersection.x - sw_rect.x;
            const systartf: f32 = intersection.y - sw_rect.y;

            const res = try db.get_or_fetch_maptile(alloc, x, y, upd.z);
            const data = res.inner.?.blob;
            const tile = try osmr.decoder2.decode(data, alloc);
            const rctx = osmr.runtime.RenderContext{
                .dat = try osmr.decoder2.parse_tile(alloc, &tile),
                .initial_px = coldef,
                .offsetx = -sxstartf,
                .offsety = -systartf,
                .render_fnc = switch (upd.stil) {
                    .color => osmr.Renderer.render_all,
                    .black_and_white => osmr.RendererTranslucent.render_all,
                },
                .scale = scale,
            };
            if (xlen < 1 or ylen < 1) continue;
            var sfc = try weather.z2d.Surface.initPixel(.{ .rgba = rctx.initial_px }, alloc, @intCast(xlen), @intCast(ylen));
            try osmr.runtime.render_mtex(
                arena.child_allocator,
                pool,
                &sfc,
                16,
                rctx,
            );
            for (xstart..xstart + xlen, 0..xlen) |toxi, fromxi| {
                for (ystart..ystart + ylen, 0..ylen) |toyi, fromyi| {
                    const og_px = sfc.getPixel(@intCast(fromxi), @intCast(fromyi)).?.rgba;
                    img.set_pixel(toxi, toyi, .{
                        .r = og_px.r,
                        .g = og_px.g,
                        .b = og_px.b,
                        .a = og_px.a,
                    });
                }
            }
        }
    }
    _ = arena.reset(.free_all);
    return upd;
}

const UpdateParameter = struct {
    lat: f32 = 0,
    lon: f32 = 0,
    z: u32 = 0,
    stil: RenderStyle = .color,
};

pub const AsyncMapGen = fifoasync.sched.ASFunction(generate);
map_gen: AsyncMapGen = .{},
img: Image,
p: ?*Image = null,
state: State = .None,
alloc: Allocator,
db: Cache,
arena: std.heap.ArenaAllocator,
params: UpdateParameter = UpdateParameter{},
const State = enum { None, Fetch };

pub fn init(alloc: Allocator, img_size: usize) !@This() {
    return @This(){
        .img = try Image.init(alloc, img_size, img_size),
        .alloc = alloc,
        .arena = std.heap.ArenaAllocator.init(alloc),
        .db = try Cache.init(CACHE_NAME),
    };
}
pub fn deinit(self: *@This()) void {
    self.map_gen.join();
    self.db.deinit();
    self.img.deinit();
    self.arena.deinit();
}
pub fn fetch(
    self: *@This(),
    pool: *std.Thread.Pool,
    async_executor: anytype,
    upd: UpdateParameter,
    force_update: bool,
) !bool {
    const state = &self.state;
    switch (state.*) {
        .None => {
            if (!std.meta.eql(upd, self.params) or force_update) {
                state.* = .Fetch;
                self.p = null;
                try self.map_gen.call(.{
                    pool,
                    &self.arena,
                    &self.db,
                    &self.img,
                    upd,
                }, async_executor);
                dvui.refresh(dvui.currentWindow(), @src(), null);
            }
        },
        .Fetch => {
            dvui.refresh(dvui.currentWindow(), @src(), null);
            if (self.map_gen.result()) |res| {
                state.* = .None;
                self.params = try res;
                self.p = &self.img;
                return true;
            }
        },
    }
    return false;
}
