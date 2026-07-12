const std = @import("std");
const kuhn = @import("kuhn.zig");

pub fn main() !void {
    var start_ts: std.posix.timespec = undefined;
    var end_ts: std.posix.timespec = undefined;
    
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &start_ts);
    
    var trainer = kuhn.Trainer{};
    const iterations = 10_000_000;
    const value = trainer.train(iterations);
    
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &end_ts);
    
    const start_ns = @as(u64, @intCast(start_ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(start_ts.nsec));
    const end_ns = @as(u64, @intCast(end_ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(end_ts.nsec));
    const elapsed_ns = end_ns - start_ns;
    
    const ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const iter_per_sec = @as(f64, @floatFromInt(iterations)) / (ms / 1000.0);
    
    std.debug.print("Solved {d} iterations in {d:.3} ms ({d:.3} million iter/sec) (value: {d:.6})\n", .{
        iterations,
        ms,
        iter_per_sec / 1_000_000.0,
        value,
    });
}
