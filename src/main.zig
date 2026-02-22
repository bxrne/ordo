const std = @import("std");
const ordo = @import("ordo");

const log = std.log.scoped(.ordo);

/// POC: Lab test demonstrating actor-based runtime with addressable messaging.
/// Creates actors, sends inter-actor messages, and demonstrates scheduling.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    log.info("Ordo Actor Runtime POC", .{});

    var runtime = try ordo.SimpleRuntime.init(allocator, 4, .RoundRobin);

    log.info("Runtime initialized with 4 workers (RoundRobin strategy)", .{});

    const actor_count = 3;
    var actors: [actor_count]*ordo.Actor = undefined;

    log.info("Creating {d} test actors", .{actor_count});
    for (0..actor_count) |i| {
        const actor_id: u128 = @as(u128, @intCast(i)) + 1;
        const actor = try allocator.create(ordo.Actor);
        actor.* = try ordo.Actor.init(actor_id, allocator, 10);
        actors[i] = actor;
        try runtime.register(actor);
        log.info("Actor {d} registered (id={d})", .{ i, actor_id });
    }

    // Cleanup: actors must be cleaned up before runtime due to defer ordering.
    defer {
        for (0..actor_count) |i| {
            actors[i].*.deinit();
            allocator.destroy(actors[i]);
        }
    }

    defer {
        runtime.deinit();
    }

    log.info("Sending inter-actor messages", .{});

    _ = runtime.send_msg(2, 1, 42);
    log.info("Actor 1 -> Actor 2: payload=42", .{});

    _ = runtime.send_msg(3, 2, 100);
    log.info("Actor 2 -> Actor 3: payload=100", .{});

    _ = runtime.send_msg(1, 3, 5);
    log.info("Actor 3 -> Actor 1: payload=5", .{});

    log.info("Running 5 ticks with RoundRobin scheduling", .{});
    const processed = runtime.run_ticks(5);
    log.info("Processed {d} messages total", .{processed});

    log.info("Final actor states", .{});
    for (0..actor_count) |i| {
        const actor = actors[i];
        const state_name = switch (actor.state.state) {
            .Idle => "Idle",
            .Running => "Running",
            .Finished => "Finished",
            .Error => "Error",
        };
        const mailbox_empty = actor.mailbox.is_empty();
        log.info("Actor {d}: state={s}, mailbox_empty={}", .{
            i + 1,
            state_name,
            mailbox_empty,
        });
    }
    }
