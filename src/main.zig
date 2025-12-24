const std = @import("std");
const clap = @import("clap");

const TOUCHSCREEN_DEVICE_NAME = "GXTP7936:00 27C6:0123";
const CLEAR_LINE = "\r\x1b[2K";

const Mode = enum { automatic, manual };
const State = struct {
    mode: Mode,
    anounce: bool,
    to_set: bool,
    end_all: bool,

    const Self = @This();

    pub fn change_mode(self: *Self, mode: Mode) void {
        @atomicStore(Mode, &self.mode, mode, .seq_cst);
        @atomicStore(bool, &self.anounce, true, .seq_cst);
    }

    pub fn toggle_mode(self: *Self) void {
        @atomicStore(
            Mode,
            &self.mode,
            switch(state.mode) { .automatic => .manual, .manual => .automatic },
            .seq_cst
        );
        @atomicStore(bool, &self.anounce, true, .seq_cst);
    }

    pub fn set(self: *Self) void {
        @atomicStore(Mode, &self.mode, Mode.manual, .seq_cst);
        @atomicStore(bool, &self.anounce, true, .seq_cst);
        @atomicStore(bool, &self.to_set, true, .seq_cst);
    }

    pub fn stop_app(self: *Self) void {
        @atomicStore(bool, &self.end_all, true, .seq_cst);
    }
};

const Accell = struct { x: f64, y: f64, z: f64 };

const Direction = enum {
    up, right, down, left,

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

const debug = false;

const allocator = std.heap.page_allocator;
const file_path = "$HOME/.cache/sr_state";
var state = State{ .mode = .manual, .anounce = false, .to_set = false, .end_all = false };

fn rotate_screen(direction: Direction) !void {
    const shell = struct { fn shell(cmd: []const []const u8) !void {
        var child = std.process.Child.init(cmd, allocator);
        _ = try child.spawnAndWait();
    } }.shell;

    try shell(&[_][]const u8{ "xrandr", "-o", direction.to_xrandr_rot_ref(), "-s", "1920x1080" });
    // try shell(&[_][]const u8{ "xinput", "set-prop", "GXTP7936:00 27C6:0123", "\"Coordinate Transformation Matrix\"", direction.to_xrandr_rot_ref() });

    const touch_device = TOUCHSCREEN_DEVICE_NAME;

    switch(direction) {
        .up => try shell(&[_][]const u8{ "xinput", "set-prop", touch_device, "189", "1", "0", "0", "0", "1", "0", "0", "0", "1" }),
        .down => try shell(&[_][]const u8{ "xinput", "set-prop", touch_device, "189", "-1", "0", "1", "0", "-1", "1", "0", "0", "1" }),
        .right => try shell(&[_][]const u8{ "xinput", "set-prop", touch_device, "189", "0", "-1", "1", "1", "0", "0", "0", "0", "1" }),
        .left => try shell(&[_][]const u8{ "xinput", "set-prop", touch_device, "189", "0", "1", "0", "-1", "0", "1", "0", "0", "1" })
    }

    try shell(&[_][]const u8{ "bash", "-c", "$HOME/.scripts/wallpaper/change_wallpaper_feh.sh $HOME/.background" });

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

pub fn file_exists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{ .mode = .read_only }) catch return false;
    return true;
}

fn signal_handler(sig: i32) callconv(.c) void {
    std.debug.print("{s}", .{ CLEAR_LINE });
    switch(sig) {
        std.posix.SIG.USR1 => { state.toggle_mode(); },
        std.posix.SIG.USR2 => { state.set(); },
        std.posix.SIG.QUIT,
        std.posix.SIG.KILL,
        std.posix.SIG.INT => { state.stop_app(); },
        else => unreachable
    }
}

fn handle_signals(sigs: []const u8, cbk: ?*const fn(i32) callconv(.c) void) void {
    var sa: std.posix.Sigaction = .{
        .handler = .{ .handler = cbk },
        .mask = [1]c_ulong{ 0 },
        .flags = std.posix.SA.RESTART,
    };

    for(sigs) |sig| { std.posix.sigaction(sig, &sa, null); }
}

const Client = struct {
    thread: std.Thread,
    stream: std.net.Stream,
    done: bool,
};

fn usage(name: []u8) noreturn {
    std.debug.print("usage: {s} <command> [<params>] \n", .{name});
    std.posix.exit(0);
}

pub fn main() !void {
    std.debug.print("\n", .{});
    defer std.debug.print("\n", .{});

    const argsZ = try std.process.argsAlloc(allocator);
    const program_name = argsZ[0][0..argsZ[0].len];

    const RunMode = enum { daemon, client, interactive };
    var run_mode: RunMode = .daemon;

    if(argsZ.len > 1) {
        const command = argsZ[1][0..argsZ[1].len];
        if(std.mem.eql(u8, "daemon", command)) {
            run_mode = .daemon;
        } else if(std.mem.eql(u8, "interactive", command)) {
            run_mode = .interactive;
        } else if(std.mem.eql(u8, "client", command)) {
            run_mode = .client;
        } else usage(program_name);
    } else usage(program_name);

    const socket_path = "/tmp/my_unix_socket.sock";

    const socket_exists = file_exists(socket_path);
    const exec_name = std.fs.path.basename(program_name);

    handle_signals(&[_]u8{
        std.posix.SIG.USR1,
        std.posix.SIG.USR2,
        std.posix.SIG.QUIT,
        std.posix.SIG.INT,
    }, signal_handler);

    switch(run_mode) {
        .daemon => {
            std.debug.print("{s}: server mode", .{exec_name});
            if(socket_exists) return error.DaemonAlreadyRunning;

            std.debug.print("(", .{});
            defer std.debug.print("\n", .{});

            var socket_addr = try std.net.Address.initUnix(socket_path);

            var listener = try socket_addr.listen(.{});
            defer listener.deinit();

            std.debug.print("{s})\n", .{socket_path});

            const client_handler = struct {
                pub fn ch(conn: *std.net.Server.Connection) void {
                    const stream = conn.stream;
                    defer stream.close();
                    

                    while(!state.end_all) {
                        var reader_buf: [1024]u8 = undefined;
                        var writer_buf: [1024]u8 = undefined;
                        var reader_ = stream.reader(&reader_buf);
                        var reader: *std.Io.Reader = reader_.interface();
                        var writer_ = stream.writer(&writer_buf);
                        var writer: *std.Io.Writer = &writer_.interface;

                        const bytes_read = reader.takeDelimiterExclusive('\n') catch |e| {
                            if(error.EndOfStream == e) break;
                            // std.log.err("{}\n", .{e});
                            break;
                        };

                        if(std.mem.eql(u8, bytes_read, "quit")) { break; }
                        else if(std.mem.eql(u8, bytes_read, "manual")) { state.change_mode(.manual); }
                        else if(std.mem.eql(u8, bytes_read, "automatic")) { state.change_mode(.automatic); }
                        else if(std.mem.eql(u8, bytes_read, "toggle")) { state.toggle_mode(); }
                        else if(std.mem.eql(u8, bytes_read, "set")) { state.set(); }
                        else if(std.mem.eql(u8, bytes_read, "stop")) { state.stop_app(); }
                        else if(std.mem.eql(u8, bytes_read, "mode")) { 
                            const msg = std.fmt.allocPrint(allocator, "{s}\n", .{ switch(state.mode) { .manual => "MANUAL", .automatic => "AUTOMATIC" } }) catch break;
                            defer allocator.free(msg);
                            writer.writeAll(msg) catch break;
                            writer.flush() catch break;
                            continue;
                        }

                        const msg = std.fmt.allocPrint(allocator, "OK\n", .{}) catch break;
                        defer allocator.free(msg);
                        writer.writeAll(msg) catch break;
                        writer.flush() catch break;
                    }
                }
            }.ch;

            const acceptor = struct {
                pub fn ac(listener_: *std.net.Server) !void {
                    var clients_thread_pool: std.Thread.Pool = undefined;
                    try clients_thread_pool.init(std.Thread.Pool.Options{
                        .allocator = allocator,
                        .n_jobs = 16,
                    });
                    defer clients_thread_pool.deinit();
                    var wg: std.Thread.WaitGroup = undefined;

                    while(!state.end_all) {
                        var conn = listener_.accept() catch return;
                        clients_thread_pool.spawnWg(&wg, client_handler, .{&conn});
                        if(state.end_all) { wg.finish(); return; }
                    }

                    wg.wait();
                }
            }.ac;

            const sensor_f = struct {
                pub fn sen() !void {

                    const sensor = find_acelerometer() catch return;

                    var acc: Accell = undefined;

                    var last: Direction = .up;
                    var current: Direction = .up;

                    var i: usize = 0;

                    while(!state.end_all) {
                        switch(state.mode) {
                            .automatic => {
                                if(state.anounce) {
                                    std.debug.print("\n>> AUTOMATIC MODE\n", .{});
                                    state.anounce = false;
                                }
                                acc = try get_acceleration(sensor);

                                if(@abs(acc.y) >= @abs(acc.x)) { // horizontal
                                    current = if(acc.y < 0) .up else .down;
                                } else { // vertical
                                    current = if(acc.x < 0) .left else .right;
                                }

                                if(debug) {
                                    std.debug.print("\r\x1b[2KState: {s} {{{any}}} ", .{ current.to_string(), acc });
                                    for(0..i+1) |_| { std.debug.print(".", .{}); }
                                    i = (i + 1) % 3;
                                }

                                std.Thread.sleep(100*std.time.ns_per_ms);

                                if(last != current) {
                                    if(debug) std.debug.print("Rotating {s}...\n", .{ current.to_string() });
                                    try rotate_screen(current);
                                    last = current;
                                }
                            },
                            .manual => {
                                if(state.anounce) {
                                    std.debug.print("\n>> MANUAL MODE\n", .{});
                                    state.anounce = false;
                                }

                                if(state.to_set) {
                                    std.debug.print("\n>> >> SET\n", .{});

                                    acc = try get_acceleration(sensor);

                                    if(@abs(acc.y) >= @abs(acc.x)) { // horizontal
                                        current = if(acc.y < 0) .up else .down;
                                    } else { // vertical
                                        current = if(acc.x < 0) .left else .right;
                                    }

                                    try rotate_screen(current);

                                    last = current;
                                    state.to_set = false;
                                }
                            }
                        }
                    }
                }
            }.sen;

            const acceptor_thread = try std.Thread.spawn(.{}, acceptor, .{ &listener });
            const sensor_thread = try std.Thread.spawn(.{}, sensor_f, .{ });

            while(!state.end_all) {} else {
                struct {
                    pub fn cc() void {
                        const stream = std.net.connectUnixSocket(socket_path) catch return;
                        stream.close();
                    }
                }.cc();

                std.fs.deleteFileAbsolute(socket_path) catch return;
            }

            acceptor_thread.join();
            sensor_thread.join();
        },
        .client => {
            std.debug.print("{s}: client mode\n", .{ exec_name });
            if(!socket_exists) return error.DaemonNotRunning;

            const stream = try std.net.connectUnixSocket(socket_path);
            defer stream.close();

            var reader_buf: [1024]u8 = undefined;
            var writer_buf: [1024]u8 = undefined;
            var reader_ = stream.reader(&reader_buf);
            var reader: *std.Io.Reader = reader_.interface();
            var writer_ = stream.writer(&writer_buf);
            var writer: *std.Io.Writer = &writer_.interface;

            const Task = enum { automatic, manual, set, get_mode };
            const task: Task = .automatic;

            switch(task) {
                .set => {
                    try writer.print("set\n", .{});
                    try writer.flush();
                    const response = try reader.takeDelimiterExclusive('\n');
                    if(!std.mem.eql(u8, "OK", response)) return error.FailerdToSet;
                },
                .manual => {
                    try writer.print("manual\n", .{});
                    try writer.flush();
                    const response = try reader.takeDelimiterExclusive('\n');
                    if(!std.mem.eql(u8, "OK", response)) return error.FailerdToSet;
                },
                .automatic => {
                    try writer.print("automatic\n", .{});
                    try writer.flush();
                    const response = try reader.takeDelimiterExclusive('\n');
                    if(!std.mem.eql(u8, "OK", response)) return error.FailerdToSet;
                },
                .get_mode => {
                    try writer.print("mode\n", .{});
                    try writer.flush();
                    const response = try reader.takeDelimiterExclusive('\n');
                    std.debug.print("{s}\n", .{response});
                }
            }
        },
        .interactive => {
            std.debug.print("{s}: interactive mode\n", .{exec_name});
            if(!socket_exists) return error.DaemonNotRunning;

            const stream = try std.net.connectUnixSocket(socket_path);
            defer stream.close();

            var reader_buf: [1024]u8 = undefined;
            var writer_buf: [1024]u8 = undefined;
            var reader_ = stream.reader(&reader_buf);
            var reader: *std.Io.Reader = reader_.interface();
            var writer_ = stream.writer(&writer_buf);
            var writer: *std.Io.Writer = &writer_.interface;

            var stdin_file = std.fs.File.stdin();
            defer stdin_file.close();
            var stdin_reader = stdin_file.reader(&.{});
            var stdin = &stdin_reader.interface;

            var stdout_file = std.fs.File.stdout();
            defer stdout_file.close();
            var stdout_reader = stdout_file.writer(&.{});
            var stdout = &stdout_reader.interface;


            while(!state.end_all) {
               try stdout.print("{s}>> ", .{ CLEAR_LINE });
               try stdout.flush();

               const req = try stdin.takeDelimiterExclusive('\n');
               try writer.print("{s}\n", .{req});
               try writer.flush();

               const res = try reader.takeDelimiterExclusive('\n');
               try stdout.print("{s}\n", .{res});
               try stdout.flush();
            }
        }
    }

    // 1. Remove the socket file if it already exists, as it persists after program exit.
    // std.fs.deleteFileAbsolute(socket_path) catch |err| switch (err) {
    //     error.FileNotFound => {},
    //     else => return err,
    // };

    









    

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
