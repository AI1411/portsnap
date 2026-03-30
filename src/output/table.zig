// src/output/table.zig
// Colored table output for PortEntry list.

const std = @import("std");
const types = @import("types");
const color = @import("color");

const col_proto: usize = 6;
const col_local: usize = 47; // "[xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx]:65535" = 47 chars
const col_state: usize = 12;
const col_pid: usize = 7;
const col_process: usize = 16; // /proc/[pid]/comm は最大 15 文字
const col_command: usize = 40;

fn formatLocalAddr(entry: types.PortEntry, buf: []u8) []const u8 {
    if (entry.is_ipv6) {
        const a = entry.local_addr6;
        return std.fmt.bufPrint(buf, "[{x:0>4}{x:0>4}:{x:0>4}{x:0>4}:{x:0>4}{x:0>4}:{x:0>4}{x:0>4}]:{d}", .{
            (@as(u16, a[0]) << 8) | a[1],
            (@as(u16, a[2]) << 8) | a[3],
            (@as(u16, a[4]) << 8) | a[5],
            (@as(u16, a[6]) << 8) | a[7],
            (@as(u16, a[8]) << 8) | a[9],
            (@as(u16, a[10]) << 8) | a[11],
            (@as(u16, a[12]) << 8) | a[13],
            (@as(u16, a[14]) << 8) | a[15],
            entry.local_port,
        }) catch "?";
    } else {
        const a = entry.local_addr;
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}:{d}", .{ a[0], a[1], a[2], a[3], entry.local_port }) catch "?";
    }
}

/// 文字列を width 文字になるようスペースでパディングして writer に出力する。
/// 文字列が width を超える場合は width 文字で切り詰める。
fn writeCol(writer: anytype, s: []const u8, width: usize) !void {
    const actual = if (s.len > width) s[0..width] else s;
    try writer.writeAll(actual);
    if (actual.len < width) {
        const pad = width - actual.len;
        var i: usize = 0;
        while (i < pad) : (i += 1) try writer.writeByte(' ');
    }
}

/// PortEntry のリストをカラー付きテーブルとして writer に出力する。
pub fn printTable(entries: []const types.PortEntry, writer: anytype) !void {
    const use_color = std.fs.File.stdout().isTty() and std.posix.getenv("NO_COLOR") == null;

    // ヘッダー
    try writer.print("portsnap \u{2014} {d} ports in use\n\n", .{entries.len});

    // カラムヘッダー
    if (use_color) try writer.writeAll(color.bold);
    try writer.writeByte(' ');
    try writeCol(writer, "PROTO", col_proto);
    try writer.writeAll("  ");
    try writeCol(writer, "LOCAL", col_local);
    try writer.writeAll("  ");
    try writeCol(writer, "STATE", col_state);
    try writer.writeAll("  ");
    try writeCol(writer, "PID", col_pid);
    try writer.writeAll("  ");
    try writeCol(writer, "PROCESS", col_process);
    try writer.writeAll("  ");
    try writer.writeAll("COMMAND");
    try writer.writeByte('\n');
    if (use_color) try writer.writeAll(color.reset);

    // セパレーター（─ = U+2500, 3 bytes in UTF-8）
    const sep_cols = 1 + col_proto + 2 + col_local + 2 + col_state + 2 + col_pid + 2 + col_process + 2 + col_command;
    if (use_color) try writer.writeAll(color.dim);
    var si: usize = 0;
    while (si < sep_cols) : (si += 1) {
        try writer.writeAll("\u{2500}");
    }
    try writer.writeByte('\n');
    if (use_color) try writer.writeAll(color.reset);

    // 各エントリー
    var addr_buf: [64]u8 = undefined;
    var pid_buf: [12]u8 = undefined;
    for (entries) |entry| {
        const local_addr = formatLocalAddr(entry, &addr_buf);
        const state_str = entry.state.toString();
        const proto_str = entry.protocol.toString();

        const pid_str: []const u8 = if (entry.pid) |p|
            std.fmt.bufPrint(&pid_buf, "{d}", .{p}) catch "-"
        else
            "-";

        const process_str = entry.process_name orelse "-";

        // COMMAND: 最大 col_command 文字に切り詰め
        const raw_cmd = entry.cmdline orelse "";
        const cmd_str = if (raw_cmd.len > col_command) raw_cmd[0..col_command] else raw_cmd;

        try writer.writeByte(' ');
        try writeCol(writer, proto_str, col_proto);
        try writer.writeAll("  ");
        try writeCol(writer, local_addr, col_local);
        try writer.writeAll("  ");
        if (use_color) try writer.writeAll(color.colorForState(entry.state));
        try writeCol(writer, state_str, col_state);
        if (use_color) try writer.writeAll(color.reset);
        try writer.writeAll("  ");
        try writeCol(writer, pid_str, col_pid);
        try writer.writeAll("  ");
        try writeCol(writer, process_str, col_process);
        try writer.writeAll("  ");
        try writer.writeAll(cmd_str);
        try writer.writeByte('\n');
    }
}
