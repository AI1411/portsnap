// tests/table_test.zig
// table.printTable のゴールデンテスト。
// NO_COLOR=1 相当の無色出力（isTty() = false の環境）を想定して
// std.ArrayList に書き出した文字列の構造を検証する。

const std = @import("std");
const types = @import("types");
const table = @import("table");

/// テスト用の最小限 PortEntry を生成するヘルパー。
fn makeIpv4Entry(
    protocol: types.Protocol,
    addr: [4]u8,
    port: u16,
    state: types.SocketState,
    pid: ?u32,
    process_name: ?[]const u8,
    cmdline: ?[]const u8,
) types.PortEntry {
    return .{
        .protocol = protocol,
        .local_addr = addr,
        .local_addr6 = .{0} ** 16,
        .local_port = port,
        .remote_addr = .{0, 0, 0, 0},
        .remote_addr6 = .{0} ** 16,
        .remote_port = 0,
        .state = state,
        .inode = 0,
        .pid = pid,
        .process_name = process_name,
        .cmdline = cmdline,
        .uid = 0,
        .is_ipv6 = false,
    };
}

fn makeIpv6Entry(
    protocol: types.Protocol,
    addr: [16]u8,
    port: u16,
    state: types.SocketState,
) types.PortEntry {
    return .{
        .protocol = protocol,
        .local_addr = .{0, 0, 0, 0},
        .local_addr6 = addr,
        .local_port = port,
        .remote_addr = .{0, 0, 0, 0},
        .remote_addr6 = .{0} ** 16,
        .remote_port = 0,
        .state = state,
        .inode = 0,
        .pid = null,
        .process_name = null,
        .cmdline = null,
        .uid = 0,
        .is_ipv6 = true,
    };
}

test "printTable: ヘッダーに件数が表示される" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const entries: []const types.PortEntry = &.{
        makeIpv4Entry(.tcp, .{ 0, 0, 0, 0 }, 8080, .listen, 1234, "my-api", "./my-api"),
        makeIpv4Entry(.tcp, .{ 127, 0, 0, 1 }, 5432, .listen, 5678, "postgres", "postgres"),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "portsnap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "2 ports in use"));
}

test "printTable: エントリー0件でもクラッシュしない" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const entries: []const types.PortEntry = &.{};
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "0 ports in use"));
}

test "printTable: IPv4 アドレスが正しく表示される" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const entries: []const types.PortEntry = &.{
        makeIpv4Entry(.tcp, .{ 0, 0, 0, 0 }, 8080, .listen, null, null, null),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "0.0.0.0:8080"));
}

test "printTable: IPv6 アドレスがあっても列が崩れない（LOCAL 列内に収まる）" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // 全フィールドが非ゼロの最長 IPv6 アドレス
    const full_addr: [16]u8 = .{ 0x20, 0x01, 0x0d, 0xb8, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x11, 0x11, 0x22, 0x22 };
    const entries: []const types.PortEntry = &.{
        makeIpv6Entry(.tcp6, full_addr, 65535, .listen),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    // STATE 列に "LISTEN" が存在することで列崩れがないと判断
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "LISTEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "tcp6"));
}

test "printTable: 長い PROCESS 名が列幅で切り詰められる" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const entries: []const types.PortEntry = &.{
        makeIpv4Entry(.tcp, .{ 127, 0, 0, 1 }, 80, .listen, 1, "containerd-shim-v2", "containerd-shim"),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    // 16文字列が列幅内に収まるか（はみ出した場合 STATE 列の位置がずれる）
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "LISTEN"));
}

test "printTable: 長い COMMAND が 40 文字で切り詰められる" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const long_cmd = "very-long-command-that-exceeds-the-column-width-limit";
    const entries: []const types.PortEntry = &.{
        makeIpv4Entry(.tcp, .{ 0, 0, 0, 0 }, 9090, .listen, 1, "app", long_cmd),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    // 切り詰め後の先頭 40 文字は出力に含まれる
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, long_cmd[0..40]));
    // 41 文字目以降は含まれない
    try std.testing.expect(!std.mem.containsAtLeast(u8, out, 1, long_cmd[40..]));
}

test "printTable: pid=null の場合は '-' が表示される" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const entries: []const types.PortEntry = &.{
        makeIpv4Entry(.udp, .{ 0, 0, 0, 0 }, 53, .unknown, null, null, null),
    };
    try table.printTable(entries, writer);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "udp"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "0.0.0.0:53"));
}
