const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const weather = root.weather;
const z2d = @import("z2d");
const Image = root.Image;
const tailwind = @import("tailwind");

const lip = @import("interpolation2.zig");
const RowMajorIter = lip.RowMajorIter;
const MeteoJsonResult = weather.Minutes15Raw.MeteoJsonResult;
const Minutes15Raw = weather.Minutes15Raw;

// scaling zooms in on the center of the data
pub fn interpolate(data: []const f32, img_size: f32, scaling: f32, x: usize, y: usize) f32 {
    const N = math.sqrt(data.len);
    assert(N * N == data.len);
    const size = img_size * scaling;
    const offset = size - img_size;
    const size_i: usize = @intFromFloat(@round(size));
    const offset_i: isize = @intFromFloat(@round(offset / 2));
    const x_i: isize = @intCast(x);
    const y_i: isize = @intCast(y);
    return lip.bicubic_interpolate(data, N, N, size_i, size_i, x_i + offset_i, y_i + offset_i);
}

pub fn interpolate_angle(data: []const f32, img_size: f32, scaling: f32, x: usize, y: usize) f32 {
    const N = math.sqrt(data.len);
    assert(N * N == data.len);
    const size = img_size * scaling;
    const offset = size - img_size;
    const size_i: usize = @intFromFloat(@round(size));
    const offset_i: isize = @intFromFloat(@round(offset / 2));
    const x_i: isize = @intCast(x);
    const y_i: isize = @intCast(y);
    return lip.bicubic_angle_interpolate(data, N, N, size_i, size_i, x_i + offset_i, y_i + offset_i);
}

pub fn get_field(comptime name: []const u8) type {
    inline for (@typeInfo(Minutes15Raw).@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return @typeInfo(f.type).pointer.child;
        }
    }
}

pub fn get_row_major_data(alloc: Allocator, weather_data: []const MeteoJsonResult, comptime field_name: []const u8, conv: anytype, data_point: usize, N: usize, offset: usize) ![]const switch (@typeInfo(@TypeOf(conv))) {
    .@"fn" => |f| f.return_type.?,
    else => get_field(field_name),
} {
    const T = switch (@typeInfo(@TypeOf(conv))) {
        .@"fn" => |f| f.return_type.?,
        else => get_field(field_name),
    };
    const ret = try alloc.alloc(T, N * N);
    const rit = RowMajorIter(T).init(ret, N, N);
    const wdata_len_sq = math.sqrt(weather_data.len);
    assert(wdata_len_sq * wdata_len_sq == weather_data.len);
    assert(offset + N <= wdata_len_sq);
    const wit = RowMajorIter(MeteoJsonResult).init(@constCast(weather_data), wdata_len_sq, wdata_len_sq);
    for (offset..offset + N) |y| {
        for (offset..offset + N) |x| {
            const v: *T = rit.get_row_major(x, y);
            const res: MeteoJsonResult = wit.get_row_major(x, y).*;
            const res_field = @field(res.minutely_15, field_name);
            const d = res_field[data_point];
            v.* = switch (@typeInfo(@TypeOf(conv))) {
                .@"fn" => conv(d),
                else => d,
            };
        }
    }
    return ret;
}

pub const RgbaU8Array = [4]u8;

pub fn alpha_0to1_to_u8(comptime alpha: f32) u8 {
    return @intFromFloat(alpha * math.maxInt(u8));
}
pub fn mix(a: RgbaU8Array, b: RgbaU8Array, normalized: f32) RgbaU8Array {
    assert(normalized >= 0);
    assert(normalized <= 1.0);
    var rgb_arr: [4]u8 = undefined;
    inline for (&a, &b, &rgb_arr) |xa, xb, *xx| {
        const fa: f32 = @floatFromInt(xa);
        const fb: f32 = @floatFromInt(xb);
        const inv = 1 - normalized;
        const f = inv * fa + normalized * fb;
        xx.* = @intFromFloat(f);
    }
    return rgb_arr;
}
pub fn scale(f: f32, fac: f32) f32 {
    return math.clamp(f * fac - fac / 2, 0, 1);
}

pub fn plateau_anti_alias_color(comptime T: type, xx: f32, comptime edge_factor: f32) RgbaU8Array {
    const fields = @typeInfo(T).@"struct".decls;
    if (comptime fields.len < 1) @compileLog("0 decls in the Definition T struct, are your decls pub?");
    const m = struct {
        fn val(comptime i: usize) f32 {
            return @field(T, fields[i].name).@"0";
        }
        fn alpha(comptime i: usize) u8 {
            return @field(T, fields[i].name).@"1";
        }
        fn col(comptime i: usize) RgbaU8Array {
            const xcol = tailwind.convert_hex(@field(tailwind, fields[i].name)) catch unreachable;
            const r, const g, const b = xcol.rgb();
            return .{ r, g, b, alpha(i) };
        }
        fn col_wo_alpha(comptime i: usize) RgbaU8Array {
            const xcol = tailwind.convert_hex(@field(tailwind, fields[i].name)) catch unreachable;
            const r, const g, const b = xcol.rgb();
            return .{ r, g, b, 255 };
        }
        fn cmix(i: comptime_int, x: f32) RgbaU8Array {
            const v = comptime val(i);
            const col_before = comptime col(i - 1);
            const val_before = comptime val(i - 1);
            const cl = comptime col(i);
            const abs_dif = v - val_before;
            const normalized = (x - val_before) / abs_dif;
            const sc_norm = scale(normalized, edge_factor);
            return mix(col_before, cl, sc_norm);
        }
    };
    @setEvalBranchQuota(10000);
    inline for (0..fields.len - 1) |i| {
        const val = comptime m.val(i);
        if (xx < val) {
            if (comptime i == 0) return comptime m.col(0);
            return m.cmix(i, xx);
        }
    }
    return m.cmix(fields.len - 1, @min(xx, m.val(fields.len - 1)));
}

pub fn u9_to_f32(x: u9) f32 {
    return @floatFromInt(x);
}

pub fn create_random_data(alloc: Allocator, N: usize, datapoints: usize) ![]const weather.Minutes15Raw.MeteoJsonResult {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    const s = try alloc.alloc(weather.Minutes15Raw.MeteoJsonResult, N * N);
    for (s) |*x| {
        const temperature_2m = blk: {
            const u = try alloc.alloc(f32, datapoints);
            for (u) |*t| t.* = rand.float(f32) * 35 + -5;
            break :blk u;
        };
        const wind_speed_10m = blk: {
            const u = try alloc.alloc(f32, datapoints);
            for (u) |*t| t.* = @max(0, rand.float(f32) * 160 - 40);
            break :blk u;
        };
        const wind_direction_10m = blk: {
            const u = try alloc.alloc(u9, datapoints);
            for (u) |*t| t.* = rand.intRangeAtMost(u9, 0, 359);
            break :blk u;
        };
        const m15 = weather.Minutes15Raw{
            .temperature_2m = temperature_2m,
            .apparent_temperature = blk: {
                const u = try alloc.alloc(f32, datapoints);
                for (u, temperature_2m) |*t, t2m| t.* = t2m - 5 + rand.float(f32) * 10;
                break :blk u;
            },
            // in mm
            .precipitation = blk: {
                const u = try alloc.alloc(f32, datapoints);
                for (u) |*t| t.* = @max(0, rand.float(f32) * 120 - 20) / 4;
                break :blk u;
            },
            //kmh
            .wind_speed_10m = wind_speed_10m,
            .wind_speed_80m = blk: {
                const u = try alloc.alloc(f32, datapoints);
                for (u, wind_speed_10m) |*t, t2m| t.* = t2m - 5 + rand.float(f32) * 15;
                break :blk u;
            },
            .wind_direction_10m = wind_direction_10m,
            .wind_direction_80m = blk: {
                const u = try alloc.alloc(u9, datapoints);
                for (u, wind_direction_10m) |*t, t2m| {
                    const k = (360 + @as(u16, @intCast(t2m)) + rand.intRangeAtMost(u16, 0, 50) - 25) % 360;
                    t.* = @intCast(k);
                }
                break :blk u;
            },
            .time = time: {
                const u = try alloc.alloc(i64, datapoints);
                const time_now = @divTrunc(std.time.microTimestamp(), 1000);
                for (u, 0..) |*t, i| {
                    t.* = time_now + @as(i64, @intCast(i)) * 15 * 60;
                }
                break :time u;
            },
            .weather_code = weathercode: {
                const u = try alloc.alloc(u32, datapoints);
                for (u) |*t| t.* = 0;
                break :weathercode u;
            },
        };
        x.* = weather.Minutes15Raw.MeteoJsonResult{
            .latitude = 0,
            .longitude = 0,
            .timezone = &.{},
            .utc_offset_seconds = 0,
            .minutely_15 = m15,
        };
    }
    return s;
}

/// use a general purpose allocator and free the Surface yourself
pub fn render_tile_mt(
    alloc: Allocator,
    img: *Image,
    fnc: anytype,
    args: anytype,
) !void {
    const parts = 16;
    const pool: *std.Thread.Pool = try alloc.create(std.Thread.Pool);
    defer alloc.destroy(pool);
    try std.Thread.Pool.init(pool, .{ .allocator = alloc, .n_jobs = parts });
    try render_mtex(alloc, pool, img, parts, fnc, args);
    pool.deinit();
}

pub fn render_mtex(
    alloc: Allocator,
    pool: *std.Thread.Pool,
    img: *Image,
    parts: usize,
    fnc: anytype,
    args: anytype,
) !void {
    const wg: *std.Thread.WaitGroup = try alloc.create(std.Thread.WaitGroup);
    wg.* = std.Thread.WaitGroup{};
    wg.reset();
    const sub_imgs = try alloc.alloc(Image, parts);
    const dh = img.get_height() / parts;
    for (0..parts) |xi| {
        const y_offset = dh * xi;
        var sh = dh;
        if (xi == parts - 1) sh = img.get_height() - y_offset;
        const sub_img = img.sub_img(0, img.get_width(), y_offset, sh);
        sub_imgs[xi] = sub_img;
        var vargs = args ++ .{ 0, y_offset };
        vargs[0] = &sub_imgs[xi];
        pool.spawnWg(wg, fnc, vargs);
    }
    pool.waitAndWork(wg);
    alloc.free(sub_imgs);
    alloc.destroy(wg);
}
