const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const print = std.log.warn;
const Request = std.http.Client.Request;
const fmt = std.fmt;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;

pub const MAX_ALLOCATION_1MB = 1024 * 1024;
/// NOTE: does not track memory allocations
pub fn http_json_api_to_T_leaky(T: type, alloc: Allocator, uri: std.Uri, max_allocation: usize) !T {
    var client = std.http.Client{ .allocator = alloc };
    const server_header_buffer: []u8 = try alloc.alloc(u8, 1024 * 8);
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = server_header_buffer,
    });
    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        std.log.warn("trying to parse into {} status {} was returned", .{ T, req.response.status });
    }

    const body = try req.reader().readAllAlloc(alloc, max_allocation);
    const res = std.json.parseFromSliceLeaky(T, alloc, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| {
        std.log.warn("body: {s}", .{body});
        std.log.warn("{}", .{e});
        return e;
    };
    return res;
}

fn print_request_header_status_and_body(req: *Request) !void {
    print("Response status: {d}\n\n", .{req.response.status});
    var it = req.response.iterateHeaders();
    while (it.next()) |header| {
        print("{s}: {s}\n", .{ header.name, header.value });
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alc = gpa.allocator();
    defer _ = gpa.deinit();
    const body = try req.reader().readAllAlloc(alc, 1024 * 64);
    defer alc.free(body);
    print("\nBODY \n\n{s}", .{body});
}

pub fn into_multi_array_list(T: type, allocator: Allocator, slice: []const T) !std.MultiArrayList(T) {
    var arrl = std.MultiArrayList(T){};
    try arrl.ensureTotalCapacity(allocator, slice.len);
    for (slice) |k| {
        arrl.appendAssumeCapacity(k);
    }
    return arrl;
}

const json = std.json;

fn write_serialized_T(T: type, allocator: Allocator, path_from_cwd: []const u8, data: T) !void {
    var list = std.ArrayList(u8).init(allocator);
    try std.json.stringify(data, .{}, list.writer());
    const path = std.fs.cwd();
    try path.writeFile(.{ .data = list.items[0..list.items.len], .sub_path = path_from_cwd });
}

pub fn print_any_leaky(t: anytype, alloc: Allocator) ![]const u8 {
    var slist = std.ArrayList(u8).init(alloc);
    const aprint = std.fmt.allocPrint;
    const T = @TypeOf(t);
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            try slist.appendSlice(try aprint(alloc, "struct {}\n", .{T}));
            inline for (s.fields) |field| {
                const field_rek = try print_any_leaky(@field(t, field.name), alloc);
                try slist.appendSlice(try aprint(alloc, "{s} :{} = {s}\n", .{
                    field.name,
                    field.type,
                    field_rek,
                }));
            }
        },
        .pointer => |p| {
            if (comptime p.size == .one) {
                try slist.appendSlice(try print_any_leaky(t.*, alloc));
            } else if (comptime p.is_const and p.child == u8) {
                try slist.appendSlice(try aprint(alloc, "{s}", .{t}));
            } else {
                try slist.appendSlice(try aprint(alloc, "{any}\n", .{t}));
            }
        },
        else => {
            try slist.appendSlice(try aprint(alloc, "{any}\n", .{t}));
        },
    }
    return slist.items;
}

pub fn ip_leaky(alc: Allocator) ![]const u8 {
    const uri = try std.Uri.parse("https://api.ipify.org?format=json");
    const PublicIp = struct {
        ip: []const u8,
    };
    const ip = try http_json_api_to_T_leaky(PublicIp, alc, uri, 1024);
    return ip.ip;
}

pub const Location = struct {
    countryCode: []const u8,
    city: []const u8,
    zip: u32,
    lat: f32,
    lon: f32,
    timezone: []const u8,
    offset: i64,
};
pub fn geo_location_leaky(alloc: Allocator) !Location {
    const pub_ip = try ip_leaky(alloc);

    const ip_api_fmt = "http://ip-api.com/json/{s}?fields=status,message,countryCode,city,zip,lat,lon,timezone,offset";
    const append_pub_id = try std.fmt.allocPrint(alloc, ip_api_fmt, .{pub_ip});

    const uri = try std.Uri.parse(append_pub_id);

    const data: Location = try http_json_api_to_T_leaky(Location, alloc, uri, 1024 * 16);
    return data;
}
test "test geo location" {
    // if (true) return;
    const gp_alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gp_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = try geo_location_leaky(alloc);
    std.log.warn("latitude: {d:.2} longitude {d:.2}, city: {s}, utc_offset: {}", .{ loc.lat, loc.lon, loc.city, loc.offset });
}

// NOTE: does not track allocations
pub fn join2048(T: type, alloc: Allocator, slc: []const T, fmtfn: fn (Allocator, T) anyerror![]const u8, sep: []const u8) ![]const u8 {
    var buffer: [2048]u8 = undefined;
    var arena = std.heap.FixedBufferAllocator.init(&buffer);
    var list = std.ArrayList(u8).init(alloc);
    for (slc, 0..) |x, i| {
        try list.appendSlice(try fmtfn(arena.allocator(), x));
        arena.reset();
        if (i + 1 < slc.len) {
            try list.appendSlice(sep);
        }
    }
    return list.items;
}
test "join sep" {
    const gp_alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gp_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();
    try expect(streql("foo,bar", try join2048([]const u8, alloc, &.{ "foo", "bar" }, fmt_string, ",")));
    try expect(streql("2,3", try join2048(u64, alloc, &.{ 2, 3 }, fmt_u64, ",")));
    try expect(streql("2", try join2048(u64, alloc, &.{2}, fmt_u64, ",")));
}
fn streql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn fmt_string(_: Allocator, x: []const u8) ![]const u8 {
    return x;
}
pub fn fmt_u64(alloc: Allocator, x: u64) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{}", .{x});
}
pub fn fmt_coordinate(alloc: Allocator, x: f32) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{d:.5}", .{x});
}

pub fn comma_seperated_from(comptime fields: []const Type.StructField) []const u8 {
    comptime var s: []const u8 = "";
    if (fields.len == 0) return s;
    s = fields[0].name;
    inline for (fields[1..]) |f| {
        s = s ++ "," ++ f.name;
    }
    return s;
}
test "comptime str" {
    const WeatherData1 = struct {
        latitude: f32,
        longitude: f32,
        timezone: []const u8,
        utc_offset_seconds: u64,
    };
    const str = comma_seperated_from(@typeInfo(WeatherData1).@"struct".fields[0..2]);
    try expect(std.mem.eql(u8, str, "latitude,longitude"));
}
