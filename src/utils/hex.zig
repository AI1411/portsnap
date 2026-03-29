// src/utils/hex.zig
// Utility to decode hex-encoded IP addresses and ports from /proc/net/tcp.

const std = @import("std");
const builtin = @import("builtin");

pub const HexError = error{
    InvalidHexChar,
    InvalidLength,
};

/// comptime lookup table: ASCII code -> nibble value (0xFF = invalid)
const hex_table: [256]u8 = blk: {
    var table = [_]u8{0xFF} ** 256;
    var i: u8 = 0;
    while (i <= 9) : (i += 1) table['0' + i] = i;
    i = 0;
    while (i < 6) : (i += 1) {
        table['a' + i] = 10 + i;
        table['A' + i] = 10 + i;
    }
    break :blk table;
};

/// Convert two hex characters (hi nibble, lo nibble) to a single byte.
pub fn parseHexU8(hi: u8, lo: u8) HexError!u8 {
    const h = hex_table[hi];
    const l = hex_table[lo];
    if (h == 0xFF or l == 0xFF) return error.InvalidHexChar;
    return (h << 4) | l;
}

/// Decode an 8-character hex string to a 4-byte IPv4 address (network byte order).
/// /proc/net/tcp prints __be32 with %08X using native endianness, so:
///   - little-endian: "0100007F" -> 127.0.0.1 (bytes reversed)
///   - big-endian:    "7F000001" -> 127.0.0.1 (bytes as-is)
pub fn decodeIpv4(hex_str: []const u8) HexError![4]u8 {
    if (hex_str.len != 8) return error.InvalidLength;
    const b0 = try parseHexU8(hex_str[0], hex_str[1]);
    const b1 = try parseHexU8(hex_str[2], hex_str[3]);
    const b2 = try parseHexU8(hex_str[4], hex_str[5]);
    const b3 = try parseHexU8(hex_str[6], hex_str[7]);
    return if (builtin.cpu.arch.endian() == .little)
        [4]u8{ b3, b2, b1, b0 } // little-endian: reverse bytes
    else
        [4]u8{ b0, b1, b2, b3 }; // big-endian: bytes are already in network order
}

/// Decode a 4-character hex string to a u16 port number (big-endian).
pub fn decodePort(hex_str: []const u8) HexError!u16 {
    if (hex_str.len != 4) return error.InvalidLength;
    const hi = try parseHexU8(hex_str[0], hex_str[1]);
    const lo = try parseHexU8(hex_str[2], hex_str[3]);
    return (@as(u16, hi) << 8) | @as(u16, lo);
}

/// Decode a 32-character hex string to a 16-byte IPv6 address (network byte order).
/// /proc/net/tcp6 prints each 32-bit group of __be32 with %08X using native endianness.
/// On little-endian each 4-byte group must be reversed; on big-endian kept as-is.
pub fn decodeIpv6(hex_str: []const u8) HexError![16]u8 {
    if (hex_str.len != 32) return error.InvalidLength;
    var result: [16]u8 = undefined;
    const is_little = builtin.cpu.arch.endian() == .little;
    var group: usize = 0;
    while (group < 4) : (group += 1) {
        const offset = group * 8;
        const b0 = try parseHexU8(hex_str[offset + 0], hex_str[offset + 1]);
        const b1 = try parseHexU8(hex_str[offset + 2], hex_str[offset + 3]);
        const b2 = try parseHexU8(hex_str[offset + 4], hex_str[offset + 5]);
        const b3 = try parseHexU8(hex_str[offset + 6], hex_str[offset + 7]);
        if (is_little) {
            // little-endian: reverse each 4-byte group to network order
            result[group * 4 + 0] = b3;
            result[group * 4 + 1] = b2;
            result[group * 4 + 2] = b1;
            result[group * 4 + 3] = b0;
        } else {
            // big-endian: already in network order
            result[group * 4 + 0] = b0;
            result[group * 4 + 1] = b1;
            result[group * 4 + 2] = b2;
            result[group * 4 + 3] = b3;
        }
    }
    return result;
}
