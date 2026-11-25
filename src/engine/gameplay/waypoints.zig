//! Shortest paths on a small, authored waypoint graph in the X/Z plane.
const std = @import("std");
const Vec3 = @import("../scene/transform.zig").Vec3;

pub const Blocker = struct {
    min: [2]f32,
    max: [2]f32,

    pub fn init(center: Vec3, half: Vec3, clearance: f32) Blocker {
        return .{
            .min = .{ center[0] - half[0] - clearance, center[2] - half[2] - clearance },
            .max = .{ center[0] + half[0] + clearance, center[2] + half[2] + clearance },
        };
    }

    fn crosses(self: Blocker, from: Vec3, to: Vec3) bool {
        var enter: f32 = 0;
        var leave: f32 = 1;
        for ([_]usize{ 0, 2 }, 0..) |axis, i| {
            const delta = to[axis] - from[axis];
            if (delta == 0) {
                if (from[axis] < self.min[i] or from[axis] > self.max[i]) return false;
                continue;
            }
            const a = (self.min[i] - from[axis]) / delta;
            const b = (self.max[i] - from[axis]) / delta;
            enter = @max(enter, @min(a, b));
            leave = @min(leave, @max(a, b));
            if (enter > leave) return false;
        }
        return true;
    }
};

pub const Graph = struct {
    pub const count = 8;
    points: [count]Vec3,
    blockers: [2]Blocker,

    fn clear(self: *const Graph, from: Vec3, to: Vec3) bool {
        for (self.blockers) |blocker| if (blocker.crosses(from, to)) return false;
        return true;
    }

    /// Connect the current position and destination to the authored nodes and
    /// return the first hop of the shortest reachable route.
    pub fn next(self: *const Graph, from: Vec3, to: Vec3) ?Vec3 {
        if (self.clear(from, to)) return to;
        var costs: [count]f32 = @splat(std.math.inf(f32));
        var first: [count]usize = undefined;
        var visited: [count]bool = @splat(false);
        for (self.points, 0..) |point, i| {
            if (!self.clear(from, point)) continue;
            costs[i] = distance(from, point);
            first[i] = i;
        }
        var best_cost = std.math.inf(f32);
        var hop: ?Vec3 = null;
        for (0..count) |_| {
            var cheapest = best_cost;
            var current: ?usize = null;
            for (costs, visited, 0..) |cost, done, i| {
                if (done or cost >= cheapest) continue;
                cheapest = cost;
                current = i;
            }
            const i = current orelse break;
            const point = self.points[i];
            visited[i] = true;
            const finish = cheapest + distance(point, to);
            if (finish < best_cost and self.clear(point, to)) {
                best_cost = finish;
                hop = self.points[first[i]];
            }
            for (self.points, 0..) |other, j| {
                const cost = cheapest + distance(point, other);
                if (visited[j] or cost >= costs[j] or !self.clear(point, other)) continue;
                costs[j] = cost;
                first[j] = first[i];
            }
        }
        return hop;
    }
};

pub fn distance(a: Vec3, b: Vec3) f32 {
    const x = b[0] - a[0];
    const z = b[2] - a[2];
    return @sqrt(x * x + z * z);
}

test "routes around cover using a shortest visible hop" {
    const graph: Graph = .{
        .points = .{ .{ -2, 0, -2 }, .{ 2, 0, -2 }, .{ 2, 0, 2 }, .{ -2, 0, 2 } } ++ @as([4]Vec3, @splat(.{ 30, 0, 30 })),
        .blockers = .{ .init(.{ 0, 0, 0 }, .{ 1, 1, 1 }, 0.4), .init(.{ 15, 0, 15 }, .{ 1, 1, 1 }, 0.4) },
    };
    try std.testing.expectEqual(Vec3{ -2, 0, 2 }, graph.next(.{ -4, 0, 0.5 }, .{ 4, 0, 0.5 }).?);
    try std.testing.expectEqual(Vec3{ 2, 0, 2 }, graph.next(.{ -2, 0, 2 }, .{ 4, 0, 0.5 }).?);
    try std.testing.expectEqual(Vec3{ 4, 0, 0.5 }, graph.next(.{ 2, 0, 2 }, .{ 4, 0, 0.5 }).?);
    try std.testing.expectEqual(null, graph.next(.{ -4, 0, 0 }, .{ 0, 0, 0 }));
}
