const std = @import("std");

pub fn main() !void {
    _ = try std.fs.File.stdout().write("portsnap\n");
}
