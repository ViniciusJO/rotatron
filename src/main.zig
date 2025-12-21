const std = @import("std");

const allocator = std.heap.page_allocator;

const file_path = "$HOME/.cache/sr_state";

const State = struct { auto_rotate: bool };
var state = State{ .auto_rotate = false };

const Accell = struct { x: f64, y: f64, z: f64 };

const Direction = enum {
    up,
    right,
    down,
    left,

    const Self = @This();
    fn to_string(self: Self) []const u8 {
        return switch(self) {
          .up => "up",
    			.right => "right",
    			.down => "down",
    			.left => "left",
        };
    }

    fn to_xrandr_rot_ref(self: Self) []const u8 {
        return switch(self) {
          .up => "normal",
    			.right => "left",
    			.down => "inverted",
    			.left => "right",
        };
    }
};

fn rotate_screen(direction: Direction) !void {
    const shell = struct { fn shell(cmd: []const []const u8) !void {
        var child = std.process.Child.init(cmd, allocator);
        _ = try child.spawnAndWait();
    } }.shell;

    try shell(&[_][]const u8{ "xrandr", "-o", direction.to_xrandr_rot_ref(), "-s", "1920x1080" });
    // try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "\"Coordinate Transformation Matrix\"", direction.to_xrandr_rot_ref() });

    switch(direction) {
        .up => try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "189", "1", "0", "0", "0", "1", "0", "0", "0", "1" }),
        .down => try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "189", "-1", "0", "1", "0", "-1", "1", "0", "0", "1" }),
        .right => try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "189", "0", "-1", "1", "1", "0", "0", "0", "0", "1" }),
        .left => try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "189", "0", "1", "0", "-1", "0", "1", "0", "0", "1" })
    }

    // try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "189", direction.to_input_transform_matrix() });
}

fn starts_with(str: []const u8, with: []const u8) bool {
    if(with.len > str.len) return false;
    for(with, 0..) |c, i| { if(str[i] != c) return false; }
    return true;
}

fn find_acelerometer() ![]const u8 {
    const path = try std.fs.openDirAbsolute("/sys/bus/iio/devices/", .{ .iterate = true });
    var w = try path.walk(allocator);
    while(try w.next()) |t| {
        if(starts_with(t.path, "iio:device")) {
            const sd = try path.openDir(t.path, .{ .iterate = true });
            var w1 = try sd.walk(allocator);
            while(try w1.next()) |t1| {
                if(t1.kind == .file and starts_with(t1.path, "in_accel")) {
                    // std.debug.print("/sys/bus/iio/devices/{s}/{s}\n", .{ t.path, t1.path });
                    return try allocator.dupe(u8, t.path[0..]);
                }
            }
        }
    }
    return error.AccelerometerNotFound;
}

fn find_new_line(str: []const u8) ?usize {
    for(str, 0..) |c, i| { if(c == '\n') return i; }
    return null;
}

fn get_acceleration(device_name: []const u8) !Accell {
    const path = try std.fs.openDirAbsolute("/sys/bus/iio/devices/", .{ .iterate = true });
    const device = try path.openDir(device_name, .{});

    const acc_scale_file = try device.openFile("in_accel_scale", .{ .mode = .read_only });
    const acc_x_file = try device.openFile("in_accel_x_raw", .{ .mode = .read_only });
    const acc_y_file = try device.openFile("in_accel_y_raw", .{ .mode = .read_only });
    const acc_z_file = try device.openFile("in_accel_z_raw", .{ .mode = .read_only });


    var buff: [256]u8 = undefined;
    var buff_view: []u8 = undefined;
    var nl: ?usize = undefined;

    _ = try acc_scale_file.readAll(&buff);
    nl = find_new_line(&buff);
    buff_view = if(nl) |v| buff[0..v] else &buff;
    const acc_scale: f64 = try std.fmt.parseFloat(f64, buff_view);

    _ = try acc_x_file.readAll(&buff);
    nl = find_new_line(&buff);
    buff_view = if(nl) |v| buff[0..v] else &buff;
    const acc_x: f64 = @floatFromInt(try std.fmt.parseInt(i64, buff_view, 10));

    _ = try acc_y_file.readAll(&buff);
    nl = find_new_line(&buff);
    buff_view = if(nl) |v| buff[0..v] else &buff;
    const acc_y: f64 = @floatFromInt(try std.fmt.parseInt(i64, buff_view, 10));

    _ = try acc_z_file.readAll(&buff);
    nl = find_new_line(&buff);
    buff_view = if(nl) |v| buff[0..v] else &buff;
    const acc_z: f64 = @floatFromInt(try std.fmt.parseInt(i64, buff_view, 10));

    return Accell{ .x = acc_x*acc_scale, .y = acc_y*acc_scale, .z = acc_z*acc_scale };
}

fn wait_for_key() !void {
    const si = std.fs.File.stdin();
    var si_reader = si.reader(&.{});
    var reader = &si_reader.interface;
    _ = try reader.readAlloc(allocator, 1);
}

fn wait_for_seconds(seconds: usize) void {
    std.debug.print("\n", .{});
    for(0..seconds+1) |s| {
        std.debug.print("\r\x1b[2KIn {}...", .{ seconds-s });
        std.Thread.sleep(std.time.ns_per_s);
    }
    std.debug.print("\n", .{});
}

pub fn main() !void {
    std.debug.print("\n", .{});
    const sensor = find_acelerometer() catch return;

    var acc: Accell = undefined;

    var last: Direction = .up;
    var current: Direction = .up;

    var i: usize = 0;

    while(true) {
        acc = try get_acceleration(sensor);

        if(@abs(acc.y) >= @abs(acc.x)) { // horizontal
            current = if(acc.y < 0) .up else .down;
        } else { // vertical
            current = if(acc.x < 0) .left else .right;
        }
        
        std.debug.print("\r\x1b[2KState: {s} {{{any}}} ", .{ current.to_string(), acc });

        for(0..i+1) |_| { std.debug.print(".", .{}); }
        i = (i + 1) % 3;

        std.Thread.sleep(100*std.time.ns_per_ms);

        if(last != current) {
            std.debug.print("Rotating {s}...\n", .{ current.to_string() });
            try rotate_screen(current);
            last = current;
        }
    }

    const usrHandler = struct {
        fn usrHandler(sig: i32, info: *const std.posix.siginfo_t, _: ?*anyopaque) callconv(.C) void {
            _  = info;
            std.debug.print("sig: {}\n", .{ sig });
            switch(sig) {
                std.posix.SIG.USR1 => { std.debug.print("\n\nUSR1\n", .{}); state.auto_rotate = true; },
                std.posix.SIG.HUP => { std.debug.print("\n\nHUP\n", .{}); state.auto_rotate = false; },
                std.posix.SIG.QUIT, std.posix.SIG.KILL => { std.debug.print("\n\nQUIT, KILL\n", .{}); std.posix.exit(0); },
                else => unreachable
            }
        }
    }.usrHandler;

    // Define the sigaction structure
    var sa: std.posix.Sigaction = .{
        .handler = .{ .handler = usrHandler },
        .mask = std.posix.empty_sigset,
        .flags = std.posix.SA.RESTART,
    };

    // Register the handler for SIGUSR1
    try std.posix.sigaction(std.posix.SIG.USR1, &sa, null);
    try std.posix.sigaction(std.posix.SIG.HUP, &sa, null);
    try std.posix.sigaction(std.posix.SIG.HUP, &sa, null);


    

    // var stdout_ = std.fs.File.stdout().writer(&.{});
    // var stdout = &stdout_.interface;
    // var state = try get_saved_state();
    // try stdout.print("{}\n\n", .{state});

    // state.auto_rotate = !state.auto_rotate;

    // try save_state(state);

    // try rotate_screen(state);
}

test "range" {
    const nm = 100;
    // var m: [nm]Accell = [1]Accell{.{.x = 0, .y = 0, .z = 0}}**nm;
    // var it: usize = 0;
    //
    std.debug.print("\n", .{});
    const sensor = try find_acelerometer();
    var acc: Accell = undefined;

    var mean: [4]Accell = [1]Accell{.{ .x = 0, .y = 0, .z = 0 }}**4;

    const direction_from_int = struct { fn dfi(int: usize) Direction { return @enumFromInt(int); } }.dfi;

    std.debug.print("Set up the device pointing to the \"{s}\" direction to capture...", .{ direction_from_int(0).to_string() });
    wait_for_seconds(5);
    for(&mean, 0..) |*m, it| {
        std.debug.print("Capturing \"{s}\" references...\n", .{ direction_from_int(it).to_string() });
        for(0..nm) |i| {
            std.debug.print("\r\x1b[2KSampling {}/{}...", .{ i+1, nm });
            acc = try get_acceleration(sensor);
            // m[it] = acc;
            m.*.x += acc.x / nm;
            m.*.y += acc.y / nm;
            m.*.z += acc.z / nm;
            // it = (it + 1) % nm;
            // std.debug.print("=> Sensor: {s} = {} <{}>\n", .{ sensor, acc, mean });
            // std.Thread.sleep(0.2*std.time.ns_per_s);
            //
            // std.Thread.sleep(1000);
            // if(it == nm) break;
        }
        std.debug.print(" DONE!\n", .{});
        if (it != 3) {
            std.debug.print("\n\nTilt the device to \"{s}\" to grab next position...", .{ direction_from_int(it+1).to_string() });
            wait_for_seconds(5);
        } else {
            std.debug.print("\n\nDone capturing!\n", .{});
        }
    }

    std.debug.print("=> Sensor: {s}\n", .{ sensor });
    for(mean, 0..) |m, i| {
        std.debug.print("\t- {s} reference: {any}\n", .{ direction_from_int(i).to_string(), m });
    }
}
