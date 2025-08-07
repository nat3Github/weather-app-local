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

const ASW = fifoasync.sched.ASNode;
const Task = fifoasync.sched.Task;
const latLonToTileF64 = weather.weather.latLonToTileF64;
const ImageWidget2 = @import("ImageWidget2.zig");
const latLonToTileF32 = weather.weather.latLonToTileF32;
const Cache = root.db;
pub const CACHE_NAME = "cache";

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
pub const City = struct {
    name: []const u8,
    x: f32,
    y: f32,
    rank: u32,
};
pub fn generate_cities(gpa: Allocator, db: *Cache, upd: UpdateParameter) !struct { UpdateParameter, []const City } {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    var arr_list = std.ArrayList(City).init(alloc);
    var hashmap = std.StringArrayHashMap(void).init(alloc);

    const tx, const ty = latLonToTileF32(upd.lat, upd.lon, @floatFromInt(upd.z));
    const otx, const oty = .{ tx - 0.5, ty - 0.5 };
    for (0..2) |xi| {
        for (0..2) |yi| {
            const tile_x: f32 = @floatFromInt(tile_index(tx, xi));
            const tile_y: f32 = @floatFromInt(tile_index(ty, yi));
            const x = wrapped_tile_index(tx, xi, upd.z);
            const y = wrapped_tile_index(ty, yi, upd.z);

            const dx = (tile_x - otx);
            const dy = (tile_y - oty);

            const res = try db.get_or_fetch_maptile(alloc, x, y, upd.z);
            const data = res.inner.?.blob;
            const tile = try osmr.decoder2.decode(data, alloc);
            const ptile = try osmr.decoder2.parse_tile(alloc, &tile);
            for (ptile.place) |place| {
                if (hashmap.get(place.meta.name) == null) {
                    try hashmap.put(place.meta.name, {});
                    const cx, const cy = place.draw.points[0];
                    const mx, const my = .{ cx + dx, cy + dy };
                    const rank: u32 = @intCast(std.math.clamp(place.meta.rank orelse 10000, 0, 10000));
                    if (mx >= 0 and mx <= 1 and my >= 0 and my <= 1) {
                        try arr_list.append(.{
                            .x = mx,
                            .y = my,
                            .rank = rank,
                            .name = place.meta.name,
                        });
                    }
                }
            }
        }
    }
    std.mem.sort(City, arr_list.items, {}, lessThan);

    const cit = try gpa.alloc(City, arr_list.items.len);
    for (cit, arr_list.items) |*c, d| {
        c.* = d;
        c.name = try gpa.dupe(u8, d.name);
    }
    return .{ upd, cit };
}
fn lessThan(_: void, a: City, b: City) bool {
    return a.rank < b.rank;
}

pub const AsyncMapGen = fifoasync.sched.ASFunction(generate_cities);

const def_scale = 1024;
const UpdateParameter = struct {
    lat: f32 = 0,
    lon: f32 = 0,
    z: u32 = 0,
};

map_gen: *AsyncMapGen,

state: State = .None,
alloc: Allocator,
db: Cache,
upd: UpdateParameter = UpdateParameter{},
cities: ?[]const City = null,

const State = enum { None, Fetch };

pub fn init(alloc: Allocator) !@This() {
    const map_gen = try AsyncMapGen.init(alloc);
    return @This(){
        .map_gen = map_gen,
        .alloc = alloc,
        .db = try Cache.init(CACHE_NAME),
    };
}
pub fn deinit(self: *@This()) void {
    const alloc = self.alloc;
    self.map_gen.deinit(alloc);
    self.free();
}
pub fn free(self: *@This()) void {
    const alloc = self.alloc;
    if (self.cities) |c| {
        for (c) |d| {
            alloc.free(d.name);
        }
        alloc.free(c);
    }
    self.cities = null;
}
pub fn fetch(
    self: *@This(),
    async_executor: anytype,
    upd: UpdateParameter,
) !bool {
    const state = &self.state;
    switch (state.*) {
        .None => {
            if (!std.meta.eql(upd, self.upd)) {
                state.* = .Fetch;
                try self.map_gen.call(.{
                    self.alloc,
                    &self.db,
                    upd,
                }, async_executor);
                dvui.refresh(dvui.currentWindow(), @src(), null);
            }
        },
        .Fetch => {
            dvui.refresh(dvui.currentWindow(), @src(), null);
            if (self.map_gen.result_ready()) {
                state.* = .None;
                const xupd, const cit = try self.map_gen.result();
                self.upd = xupd;
                self.free();
                self.cities = cit;
                return true;
            }
        },
    }
    return false;
}
