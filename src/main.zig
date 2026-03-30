const std = @import("std");
const types = @import("types");
const proc_net = @import("proc_net");
const proc_fd = @import("proc_fd");
const proc_info = @import("proc_info");
const table = @import("table");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries: std.ArrayList(types.PortEntry) = .empty;
    try proc_net.scanAll(allocator, &entries);
    try proc_fd.resolvePids(allocator, entries.items);
    try proc_info.resolveProcessInfo(allocator, entries.items);

    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    try table.printTable(entries.items, &stdout_writer.interface);
    try stdout_writer.interface.flush();
}
