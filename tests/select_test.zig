// tests/select_test.zig
const std = @import("std");
const select = @import("select");

// ── parseKeyByte テスト ──────────────────────────────────────────

test "parseKeyByte: j moves down" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('j', &state);
    try std.testing.expectEqual(select.Action.move_down, action);
    try std.testing.expectEqual(select.KeyState.normal, state);
}

test "parseKeyByte: k moves up" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('k', &state);
    try std.testing.expectEqual(select.Action.move_up, action);
    try std.testing.expectEqual(select.KeyState.normal, state);
}

test "parseKeyByte: up arrow sequence ESC [ A" {
    var state: select.KeyState = .normal;
    const a1 = select.parseKeyByte(0x1b, &state);
    try std.testing.expectEqual(select.Action.none, a1);
    try std.testing.expectEqual(select.KeyState.esc_start, state);

    const a2 = select.parseKeyByte('[', &state);
    try std.testing.expectEqual(select.Action.none, a2);
    try std.testing.expectEqual(select.KeyState.esc_bracket, state);

    const a3 = select.parseKeyByte('A', &state);
    try std.testing.expectEqual(select.Action.move_up, a3);
    try std.testing.expectEqual(select.KeyState.normal, state);
}

test "parseKeyByte: down arrow sequence ESC [ B" {
    var state: select.KeyState = .normal;
    _ = select.parseKeyByte(0x1b, &state);
    _ = select.parseKeyByte('[', &state);
    const action = select.parseKeyByte('B', &state);
    try std.testing.expectEqual(select.Action.move_down, action);
}

test "parseKeyByte: lone ESC quits" {
    var state: select.KeyState = .normal;
    _ = select.parseKeyByte(0x1b, &state);
    // '[' 以外 → quit
    const action = select.parseKeyByte('x', &state);
    try std.testing.expectEqual(select.Action.quit, action);
    try std.testing.expectEqual(select.KeyState.normal, state);
}

test "parseKeyByte: Enter confirms" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('\r', &state);
    try std.testing.expectEqual(select.Action.confirm, action);
}

test "parseKeyByte: y accepts" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('y', &state);
    try std.testing.expectEqual(select.Action.accept, action);
}

test "parseKeyByte: n cancels" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('n', &state);
    try std.testing.expectEqual(select.Action.cancel, action);
}

test "parseKeyByte: q quits" {
    var state: select.KeyState = .normal;
    const action = select.parseKeyByte('q', &state);
    try std.testing.expectEqual(select.Action.quit, action);
}

// ── moveCursor テスト ────────────────────────────────────────────

test "moveCursor: up at top stays 0" {
    try std.testing.expectEqual(@as(usize, 0), select.moveCursor(0, .up, 5));
}

test "moveCursor: down at bottom stays len-1" {
    try std.testing.expectEqual(@as(usize, 4), select.moveCursor(4, .down, 5));
}

test "moveCursor: up from middle" {
    try std.testing.expectEqual(@as(usize, 1), select.moveCursor(2, .up, 5));
}

test "moveCursor: down from middle" {
    try std.testing.expectEqual(@as(usize, 3), select.moveCursor(2, .down, 5));
}

test "moveCursor: empty list returns 0" {
    try std.testing.expectEqual(@as(usize, 0), select.moveCursor(0, .up, 0));
    try std.testing.expectEqual(@as(usize, 0), select.moveCursor(0, .down, 0));
}
