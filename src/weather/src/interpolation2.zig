const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const Image = @import("image");

inline fn get_pixel(data: []const f32, w: isize, h: isize, x: isize, y: isize) f32 {
    const clamped_x = std.math.clamp(x, 0, w - 1);
    const clamped_y = std.math.clamp(y, 0, h - 1);
    return data[@as(usize, @intCast(clamped_y)) * @as(usize, @intCast(w)) + @as(usize, @intCast(clamped_x))];
}

pub inline fn bilinear_interpolate(
    data: []const f32,
    w: usize,
    h: usize,
    n: usize,
    m: usize,
    out_x: isize,
    out_y: isize,
) f32 {
    const scale_x = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(n));
    const scale_y = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(m));
    const in_x = scale_x * (@as(f32, @floatFromInt(out_x)) + 0.5) - 0.5;
    const in_y = scale_y * (@as(f32, @floatFromInt(out_y)) + 0.5) - 0.5;

    const x0: isize = @intFromFloat(@floor(in_x));
    const y0: isize = @intFromFloat(@floor(in_y));
    const x1 = x0 + 1;
    const y1 = y0 + 1;

    const fx = in_x - @as(f32, @floatFromInt(x0));
    const fy = in_y - @as(f32, @floatFromInt(y0));

    const p00 = get_pixel(data, @intCast(w), @intCast(h), x0, y0);
    const p10 = get_pixel(data, @intCast(w), @intCast(h), x1, y0);
    const p01 = get_pixel(data, @intCast(w), @intCast(h), x0, y1);
    const p11 = get_pixel(data, @intCast(w), @intCast(h), x1, y1);

    const ix0 = p00 * (1.0 - fx) + p10 * fx;
    const ix1 = p01 * (1.0 - fx) + p11 * fx;

    return ix0 * (1.0 - fy) + ix1 * fy;
}

pub inline fn bicubic_interpolate(
    data: []const f32,
    w: usize,
    h: usize,
    n: usize,
    m: usize,
    out_x: isize,
    out_y: isize,
) f32 {
    const scale_x = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(n));
    const scale_y = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(m));
    const in_x = scale_x * (@as(f32, @floatFromInt(out_x)) + 0.5) - 0.5;
    const in_y = scale_y * (@as(f32, @floatFromInt(out_y)) + 0.5) - 0.5;

    const ix: isize = @intFromFloat(@floor(in_x));
    const iy: isize = @intFromFloat(@floor(in_y));
    const fx = in_x - @as(f32, @floatFromInt(ix));
    const fy = in_y - @as(f32, @floatFromInt(iy));

    var col: [4]f32 = undefined;

    for (0..4) |i| {
        const row_y: isize = iy - 1 + @as(isize, @intCast(i));
        var row: [4]f32 = undefined;
        for (0..4) |j| {
            const col_x: isize = ix - 1 + @as(isize, @intCast(j));
            row[j] = get_pixel(data, @intCast(w), @intCast(h), col_x, row_y);
        }
        col[i] = cubic_hermite(row[0], row[1], row[2], row[3], fx);
    }

    return cubic_hermite(col[0], col[1], col[2], col[3], fy);
}

inline fn cubic_hermite(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) f32 {
    const a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
    const b = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3;
    const c = -0.5 * p0 + 0.5 * p2;
    const d = p1;
    return ((a * t + b) * t + c) * t + d;
}

inline fn angle_to_vector(deg: f32) struct { x: f32, y: f32 } {
    const rad = math.degreesToRadians(deg);
    return .{ .x = @cos(rad), .y = @sin(rad) };
}

inline fn get_angle(data: []const f32, w: usize, h: usize, x: isize, y: isize) f32 {
    const clamped_x = math.clamp(x, 0, @as(isize, @intCast(w - 1)));
    const clamped_y = math.clamp(y, 0, @as(isize, @intCast(h - 1)));
    return data[@as(usize, @intCast(clamped_y)) * w + @as(usize, @intCast(clamped_x))];
}
pub inline fn bilinear_angle_interpolate(
    data: []const f32,
    w: usize,
    h: usize,
    n: usize,
    m: usize,
    out_x: isize,
    out_y: isize,
) f32 {
    const scale_x = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(n));
    const scale_y = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(m));
    const in_x = scale_x * (@as(f32, @floatFromInt(out_x)) + 0.5) - 0.5;
    const in_y = scale_y * (@as(f32, @floatFromInt(out_y)) + 0.5) - 0.5;

    const x0: isize = @intFromFloat(@floor(in_x));
    const y0: isize = @intFromFloat(@floor(in_y));
    const x1 = x0 + 1;
    const y1 = y0 + 1;

    const fx = in_x - @as(f32, @floatFromInt(x0));
    const fy = in_y - @as(f32, @floatFromInt(y0));

    const a00 = angle_to_vector(get_angle(data, w, h, x0, y0));
    const a10 = angle_to_vector(get_angle(data, w, h, x1, y0));
    const a01 = angle_to_vector(get_angle(data, w, h, x0, y1));
    const a11 = angle_to_vector(get_angle(data, w, h, x1, y1));

    const ix0 = a00.x * (1.0 - fx) + a10.x * fx;
    const iy0 = a00.y * (1.0 - fx) + a10.y * fx;
    const ix1 = a01.x * (1.0 - fx) + a11.x * fx;
    const iy1 = a01.y * (1.0 - fx) + a11.y * fx;

    const vx = ix0 * (1.0 - fy) + ix1 * fy;
    const vy = iy0 * (1.0 - fy) + iy1 * fy;

    const angle_rad = math.atan2(vy, vx);
    var angle_deg = math.radiansToDegrees(angle_rad);
    if (angle_deg < 0.0) angle_deg += 360.0;
    return angle_deg;
}

pub inline fn bicubic_angle_interpolate(
    data: []const f32,
    w: usize,
    h: usize,
    n: usize,
    m: usize,
    out_x: isize,
    out_y: isize,
) f32 {
    const scale_x = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(n));
    const scale_y = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(m));
    const in_x = scale_x * (@as(f32, @floatFromInt(out_x)) + 0.5) - 0.5;
    const in_y = scale_y * (@as(f32, @floatFromInt(out_y)) + 0.5) - 0.5;

    const ix: isize = @intFromFloat(@floor(in_x));
    const iy: isize = @intFromFloat(@floor(in_y));
    const fx = in_x - @as(f32, @floatFromInt(ix));
    const fy = in_y - @as(f32, @floatFromInt(iy));

    var col_x: [4]f32 = undefined;
    var col_y: [4]f32 = undefined;
    for (0..4) |i| {
        const row_y: isize = iy - 1 + @as(isize, @intCast(i));
        var row_x: [4]f32 = undefined;
        var row_y_vec: [4]f32 = undefined;

        for (0..4) |j| {
            const col_x_index: isize = ix - 1 + @as(isize, @intCast(j));
            const deg = get_angle(data, w, h, col_x_index, row_y);
            const vec = angle_to_vector(deg);
            row_x[j] = vec.x;
            row_y_vec[j] = vec.y;
        }
        col_x[i] = cubic_hermite(row_x[0], row_x[1], row_x[2], row_x[3], fx);
        col_y[i] = cubic_hermite(row_y_vec[0], row_y_vec[1], row_y_vec[2], row_y_vec[3], fx);
    }

    const interp_x = cubic_hermite(col_x[0], col_x[1], col_x[2], col_x[3], fy);
    const interp_y = cubic_hermite(col_y[0], col_y[1], col_y[2], col_y[3], fy);

    const angle_rad = math.atan2(interp_y, interp_x);
    var angle_deg = math.radiansToDegrees(angle_rad);

    angle_deg = @mod(angle_deg, 360);
    return @floatCast(angle_deg);
}

fn test_bicubic_interpolation() !void {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const n: usize = 2;
    const multiplier = 200;
    const m: usize = n * multiplier;

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var in_data: [n * n]f32 = undefined;
    for (&in_data) |*d| {
        d.* = rand.float(f32) * 359;
    }

    const Iter = RowMajorIter(f32);
    const it_og = Iter.init(&in_data, n, n);
    const max_og = std.mem.max(f32, &in_data);
    assert(max_og != 0);
    const fnc = draw_hue;

    var img_original = try Image.init(alloc, m, m);
    for (0..m) |x| {
        for (0..m) |y| {
            const f = it_og.get_row_major(x / multiplier, y / multiplier).*;
            const normalized = f / max_og;
            const pixel = fnc(normalized);
            img_original.set_pixel(x, y, pixel);
        }
    }
    try img_original.write_ppm_to_file("test/original.ppm");

    var img_interpolated = try Image.init(alloc, m, m);
    for (0..m) |x| {
        for (0..m) |y| {
            const f = bicubic_interpolate(&in_data, n, n, m, m, @intCast(x), @intCast(y));
            const normalized = math.clamp(f / max_og, 0, 1);
            const pixel = fnc(normalized);
            img_interpolated.set_pixel(x, y, pixel);
        }
    }

    try img_interpolated.write_ppm_to_file("test/bicubic.ppm");
    for (0..m) |x| {
        for (0..m) |y| {
            const f = bicubic_angle_interpolate(&in_data, n, n, m, m, @intCast(x), @intCast(y));
            const normalized = math.clamp(f / max_og, 0, 1);
            const pixel = fnc(normalized);
            img_interpolated.set_pixel(x, y, pixel);
        }
    }
    try img_interpolated.write_ppm_to_file("test/bicubic-angles.ppm");
    for (0..m) |x| {
        for (0..m) |y| {
            const f = bilinear_interpolate(&in_data, n, n, m, m, @intCast(x), @intCast(y));
            const normalized = math.clamp(f / max_og, 0, 1);
            const pixel = fnc(normalized);
            img_interpolated.set_pixel(x, y, pixel);
        }
    }
    try img_interpolated.write_ppm_to_file("test/bilinear.ppm");
    for (0..m) |x| {
        for (0..m) |y| {
            const f = bilinear_angle_interpolate(&in_data, n, n, m, m, @intCast(x), @intCast(y));
            const normalized = math.clamp(f / max_og, 0, 1);
            const pixel = fnc(normalized);
            img_interpolated.set_pixel(x, y, pixel);
        }
    }
    try img_interpolated.write_ppm_to_file("test/bilinear-angles.ppm");
}
test "test bicubic" {
    if (true) return;
    try test_bicubic_interpolation();
}

fn draw_hue(normalized: f32) Image.Pixel {
    return Image.Pixel.init_hsv(normalized, 0.7, 0.7);
}
fn draw_luminosity(normalized: f32) Image.Pixel {
    return Image.Pixel.init_hsv(0.4, 0.7, normalized);
}

test "bicubic angle interpolation edge cases" {
    const w = 4;
    const h = 4;
    const n = 2;
    const m = 2;

    // Construct a 4x4 patch with wraparound values around 0°
    const wrapped_patch = [_]f32{
        350, 355, 0, 5,
        350, 355, 0, 5,
        350, 355, 0, 5,
        350, 355, 0, 5,
    };

    const angle = bicubic_angle_interpolate(&wrapped_patch, w, h, n, m, 1, 1);
    // Expect something close to 0° — not 180°
    try expect(angle <= 10 or angle >= 350);

    // Uniform angles: interpolation should return the same value
    const uniform_patch = [_]f32{
        90, 90, 90, 90,
        90, 90, 90, 90,
        90, 90, 90, 90,
        90, 90, 90, 90,
    };

    const uniform_result = bicubic_angle_interpolate(&uniform_patch, w, h, n, m, 0, 0);
    try expect(90 == uniform_result);

    const my_patch = [_]f32{
        0,   180,
        270, 0,
    };
    const my_result = bicubic_angle_interpolate(&my_patch, 2, 2, 3, 3, 0, 1);
    try expect(my_result == 315);
}

pub fn RowMajorIter(T: type) type {
    return struct {
        slc: []T,
        width: usize,
        height: usize,
        pub fn init(slc: []T, width: usize, height: usize) @This() {
            assert(width * height == slc.len);
            return @This(){
                .slc = slc,
                .width = width,
                .height = height,
            };
        }
        pub fn get_row_major(self: *const @This(), x: usize, y: usize) *T {
            const idx = row_major_index(x, y, self.width);
            return &self.slc[idx];
        }
        pub fn row_major_index(x: usize, y: usize, width: usize) usize {
            return y * width + x;
        }
    };
}
