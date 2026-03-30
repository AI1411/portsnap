// src/output/select.zig
// インタラクティブ選択TUI。rawターミナルモードでポートを選択してkillする。

const std = @import("std");
const types = @import("types");
const signal_utils = @import("signal");

pub const KeyState = enum { normal, esc_start, esc_bracket };

pub const Action = enum {
    move_up,
    move_down,
    confirm, // Enter
    accept, // 'y' (プロンプト中のkill確認)
    cancel, // 'n' / Esc (プロンプト解除)
    quit,
    none,
};

/// 1バイトをステートマシンでパースしてActionを返す。
/// ESCシーケンス（↑↓）は複数バイトにわたるため state を更新しながら処理する。
pub fn parseKeyByte(byte: u8, state: *KeyState) Action {
    switch (state.*) {
        .normal => switch (byte) {
            0x1b => {
                state.* = .esc_start;
                return .none;
            },
            'k' => return .move_up,
            'j' => return .move_down,
            '\r' => return .confirm,
            'y', 'Y' => return .accept,
            'n', 'N' => return .cancel,
            'q', 'Q' => return .quit,
            else => return .none,
        },
        .esc_start => switch (byte) {
            '[' => {
                state.* = .esc_bracket;
                return .none;
            },
            else => {
                // '[' 以外が来たら単独 ESC とみなして quit
                state.* = .normal;
                return .quit;
            },
        },
        .esc_bracket => {
            state.* = .normal;
            return switch (byte) {
                'A' => .move_up,
                'B' => .move_down,
                else => .none,
            };
        },
    }
}

/// カーソルを上下に移動する。境界では折り返さない。
pub fn moveCursor(cursor: usize, comptime direction: enum { up, down }, len: usize) usize {
    if (len == 0) return 0;
    return switch (direction) {
        .up => if (cursor > 0) cursor - 1 else 0,
        .down => if (cursor + 1 < len) cursor + 1 else len - 1,
    };
}

/// 文字列を width 文字分パディングして writer に書き出す。
fn writeCol(writer: anytype, s: []const u8, width: usize) !void {
    const actual = if (s.len > width) s[0..width] else s;
    try writer.writeAll(actual);
    const pad = width -| actual.len;
    var j: usize = 0;
    while (j < pad) : (j += 1) try writer.writeByte(' ');
}

/// ポート一覧と選択状態を画面に描画する。
fn render(
    entries: []const types.PortEntry,
    cursor: usize,
    in_prompt: bool,
    error_msg: ?[]const u8,
) !void {
    var out_buf: [16384]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buf);
    const w = &out.interface;

    // 画面クリア + カーソル先頭
    try w.writeAll("\x1b[2J\x1b[H");

    // ヘッダー
    try w.print("pps \u{2014} {d} ports  [\u{2191}\u{2193}/jk] \u{79fb}\u{52d5}  [Enter] kill  [q] \u{7d42}\u{4e86}\n\n", .{entries.len});

    // カラムヘッダー
    try w.writeAll("\x1b[1m  PROTO  PORT             STATE         PID      PROCESS\x1b[0m\n");

    // セパレーター
    try w.writeAll("\u{2500}" ** 57 ++ "\n");

    // エントリ一覧
    var port_buf: [24]u8 = undefined;
    var pid_buf: [12]u8 = undefined;
    for (entries, 0..) |entry, i| {
        const is_selected = (i == cursor);
        const has_pid = (entry.pid != null);

        if (is_selected) try w.writeAll("\x1b[7m"); // 反転表示
        if (!has_pid and !is_selected) try w.writeAll("\x1b[2m"); // PIDなしは暗く

        // 選択マーカー
        if (is_selected) {
            try w.writeAll(">");
        } else {
            try w.writeAll(" ");
        }

        // PROTO (5文字)
        const proto = entry.protocol.toString();
        try w.writeAll(" ");
        try writeCol(w, proto, 5);
        try w.writeAll("  ");

        // PORT (15文字)
        const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{entry.local_port}) catch "?";
        try writeCol(w, port_str, 15);
        try w.writeAll("  ");

        // STATE (12文字)
        try writeCol(w, entry.state.toString(), 12);
        try w.writeAll("  ");

        // PID (7文字)
        const pid_str: []const u8 = if (entry.pid) |p|
            std.fmt.bufPrint(&pid_buf, "{d}", .{p}) catch "-"
        else
            "-";
        try writeCol(w, pid_str, 7);
        try w.writeAll("  ");

        // PROCESS (15文字)
        const proc = entry.process_name orelse "-";
        const proc_trunc = if (proc.len > 15) proc[0..15] else proc;
        try w.writeAll(proc_trunc);

        if (is_selected or (!has_pid and !is_selected)) try w.writeAll("\x1b[0m");
        try w.writeByte('\n');
    }

    try w.writeByte('\n');

    // 確認プロンプトまたはエラーメッセージ
    if (in_prompt) {
        const entry = entries[cursor];
        const proc = entry.process_name orelse "process";
        const pid = entry.pid orelse 0;
        try w.print("Kill {s} (PID {d})? [y/N] ", .{ proc, pid });
    } else if (error_msg) |msg| {
        try w.print("\x1b[31m{s}\x1b[0m\n", .{msg});
    }

    try w.flush();
}

/// インタラクティブ選択モードを起動する。
/// ユーザーが選択してkillするか、qで終了するまでブロックする。
pub fn run(allocator: std.mem.Allocator, entries: []const types.PortEntry) !void {
    _ = allocator;

    if (entries.len == 0) {
        var buf: [64]u8 = undefined;
        var out = std.fs.File.stdout().writer(&buf);
        try out.interface.writeAll("pps: no ports found\n");
        try out.interface.flush();
        return;
    }

    const stdin_fd = std.fs.File.stdin().handle;

    // ターミナル設定を保存し、終了時に必ず復元する
    const orig = try std.posix.tcgetattr(stdin_fd);
    defer std.posix.tcsetattr(stdin_fd, .FLUSH, orig) catch {};

    // rawモードに切り替え（canonical off, echo off）
    var raw = orig;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);

    var cursor: usize = 0;
    var in_prompt = false;
    var key_state: KeyState = .normal;
    var error_msg: ?[]const u8 = null;

    // 初回描画
    try render(entries, cursor, in_prompt, error_msg);

    var key_buf: [1]u8 = undefined;
    loop: while (true) {
        const n = std.posix.read(stdin_fd, &key_buf) catch break;
        if (n == 0) continue;

        const action = parseKeyByte(key_buf[0], &key_state);

        // ESCシーケンス蓄積中は再描画しない
        if (action == .none) continue;

        // 新しい操作でエラーメッセージをクリア
        error_msg = null;

        if (in_prompt) {
            switch (action) {
                .accept => {
                    const entry = entries[cursor];
                    if (entry.pid) |pid| {
                        signal_utils.sendSignal(pid, .SIGTERM) catch {
                            error_msg = "Kill failed (insufficient permissions?)";
                            in_prompt = false;
                            try render(entries, cursor, in_prompt, error_msg);
                            continue :loop;
                        };
                        break :loop; // kill成功 → 終了
                    }
                    in_prompt = false;
                },
                else => {
                    // y 以外はすべてキャンセル
                    in_prompt = false;
                },
            }
        } else {
            switch (action) {
                .move_up => cursor = moveCursor(cursor, .up, entries.len),
                .move_down => cursor = moveCursor(cursor, .down, entries.len),
                .confirm => {
                    if (entries[cursor].pid != null) {
                        in_prompt = true;
                    }
                },
                .quit => break :loop,
                else => {},
            }
        }

        try render(entries, cursor, in_prompt, error_msg);
    }

    // 終了時に画面クリア
    var clear_buf: [16]u8 = undefined;
    var out = std.fs.File.stdout().writer(&clear_buf);
    try out.interface.writeAll("\x1b[2J\x1b[H");
    try out.interface.flush();
}
