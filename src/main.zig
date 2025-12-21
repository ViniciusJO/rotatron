const std = @import("std");
// const stdout = std.io.getStdOut().writer();

const allocator = std.heap.page_allocator;

const file_path = "$HOME/.cache/sr_state";
const State = struct { auto_rotate: bool, auto_save: bool, prev_state: u8 };

const Resolution = [_][]const u8{ "1920x1080", "1920x1080", "1920x1080", "1920x1080" };

const RES = [_][]const u8{ "1920x1080", "1920x1080", "1920x1080", "1920x1080" };
const ROT = [_][]const u8{ "normal", "inverted", "left", "right" };
const COOR = [_][]const u8{ "1 0 0 0 1 0 0 0 1", "-1 0 1 0 -1 1 0 0 1", "0 -1 1 1 0 0 0 0 1", "0 1 0 -1 0 1 0 0 1" };

fn get_saved_state() !State {
    var buff = [_]u8{0} ** 255;

    const file = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();
    _ = try file.read(&buff);

    const byte = buff[0] - '0';

    return State{ .prev_state = byte & 3, .auto_rotate = ((byte >> 2) & 1) != 0, .auto_save = true };
}

fn save_state(s: State) !void {
    var byte: u8 = s.prev_state;

    byte += if (s.auto_rotate) 4 else 0;
    const file = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.write_only });
    defer file.close();
    _ = try file.write(&[_]u8{byte + '0'});
}

const Accell = struct { x: f64, y: f64 };

fn change(a: Accell, g: f64, s: State) State {
    s.prev_state = if (a.y < -g) 0 else if (a.y > g) 1 else if (a.x > g) 2 else if (a.x < -g) 3;
    return s;
}

fn shell_cmd(cmd: []const []const u8) ![]const u8 {
    // const child = std.process.Child.init(&[_][]const u8{ "echo", "hellou" }, std.heap.page_allocator);
    // try child.spawn();
    // var child = std.process.Child.init(&[_][]const u8{ "echo", "kkkkkk!" }, allocator);
    var child = std.process.Child.init(cmd, allocator);
    // defer child.deinit();

    // Redireciona a saída padrão do processo para que possamos lê-la
    child.stdout_behavior = .Pipe;

    try child.spawn();

    var buffer: [1024]u8 = undefined;
    var stdout_reader = child.stdout.?.reader(&.{});
    const n = try stdout_reader.interface.readSliceShort(&buffer);

    // std.debug.print("{s}\n", .{buffer[0..n]});

    // Aguarda o processo terminar
    _ = try child.wait();

    return buffer[0..n];
}

fn shell_cmd_nr(cmd: []const []const u8) !void {
    _ = try shell_cmd(cmd);
}

fn rotate_screen(state: State) !void {
    try shell_cmd_nr(&[_][]const u8{ "xrandr -o", ROT[state.prev_state], "-s", RES[state.prev_state] });
    try shell_cmd_nr(&[_][]const u8{ "xinput set-prop", "GXTP7936:00 27C6:0123", "\"Coordinate Transformation Matrix\"", COOR[state.prev_state] });

    if (state.auto_save) try save_state(state);
}

pub fn main() !void {
    var stdout_ = std.fs.File.stdout().writer(&.{});
    var stdout = &stdout_.interface;
    var state = try get_saved_state();
    try stdout.print("{}\n\n", .{state});

    state.auto_rotate = !state.auto_rotate;

    try save_state(state);

    try rotate_screen(state);
}
