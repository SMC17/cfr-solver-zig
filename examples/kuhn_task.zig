const std = @import("std");
const cfr = @import("cfr");

pub fn main(init: std.process.Init) !void {
    var trainer = cfr.kuhn.Trainer{};
    const trajectory_value = trainer.train(20_000);
    var policy: [12][2]f64 = undefined;
    for (&trainer.isets, &policy) |*info, *out| out.* = info.average();
    const bytes = try std.json.Stringify.valueAlloc(init.gpa, .{
        .schema = 1,
        .game = "kuhn-ante1-bet1",
        .iterations = @as(usize, 20_000),
        .trajectory_value = trajectory_value,
        .history_ids = [_][]const u8{ "", "p", "b", "pb" },
        .policy = policy,
    }, .{ .whitespace = .indent_2 });
    defer init.gpa.free(bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
