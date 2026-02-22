const std = @import("std");
const Actor = @import("../actor/mod.zig").Actor;
const Message = @import("../actor/mailbox.zig").Message;

const log = std.log.scoped(.ordo_runtime);

const MAX_ACTORS = 256;
const MAX_TICKS = 1_000_000;

/// Scheduling strategy for actor dispatching.
/// Extensible enum for future strategies (RAFT, Immediate, etc).
pub const ScheduleStrategy = enum {
    RoundRobin,
    Immediate,
    // RAFT, // Future extensions
};

/// Simple runtime manages actors with addressable messaging.
/// Statically bounded for predictable performance and safety.
/// No unbounded allocations after initialization.
pub const Simple = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    actor_map: std.AutoHashMap(u128, *Actor),
    actor_count: u32 = 0,
    running: bool = false,
    schedule: ScheduleStrategy = .RoundRobin,
    total_messages_sent: u64 = 0,
    total_ticks: u32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        worker_count: u8,
        strategy: ScheduleStrategy,
    ) !Simple {
        // Preconditions: worker_count must be positive and <= max.
        std.debug.assert(worker_count > 0);
        std.debug.assert(worker_count <= 256);

        log.info("runtime.init: workers={d}, strategy={s}", .{ worker_count, @tagName(strategy) });

        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        errdefer allocator.destroy(arena);

        const runtime = Simple{
            .allocator = allocator,
            .arena = arena,
            .actor_map = std.AutoHashMap(u128, *Actor).init(arena.allocator()),
            .schedule = strategy,
        };

        // Postconditions: runtime is initialized with valid state.
        std.debug.assert(runtime.actor_count == 0);
        std.debug.assert(runtime.total_messages_sent == 0);
        std.debug.assert(!runtime.running);

        log.info("runtime.init: ready", .{});

        return runtime;
    }

    /// Register an actor with the runtime.
    /// Returns error if actor already registered or max actors exceeded.
    pub fn register(self: *Simple, actor: *Actor) !void {
        // Preconditions: runtime must not be running, actor must be valid.
        std.debug.assert(!self.running);
        std.debug.assert(self.actor_count < MAX_ACTORS);
        std.debug.assert(actor.id > 0);

        log.debug("runtime.register: registering actor {d}", .{actor.id});

        // Negative space: duplicate registration check.
        if (self.actor_map.contains(actor.id)) {
            log.err("runtime.register: actor {d} already registered", .{actor.id});
            return error.ActorAlreadyRegistered;
        }

        try self.actor_map.put(actor.id, actor);
        const old_count = self.actor_count;
        self.actor_count += 1;

        log.info("runtime.register: actor {d} registered ({d}/{d})", .{ actor.id, self.actor_count, MAX_ACTORS });

        // Postcondition: actor count incremented.
        std.debug.assert(self.actor_count == old_count + 1);
        std.debug.assert(self.actor_map.contains(actor.id));
    }

    /// Send a message to an actor by ID.
    /// Returns true if successful, false if actor not found or mailbox full.
    pub fn send_msg(
        self: *Simple,
        target_id: u128,
        sender_id: u128,
        payload: u64,
    ) bool {
        // Preconditions: IDs must be non-zero.
        std.debug.assert(target_id > 0);
        std.debug.assert(sender_id > 0);

        if (self.actor_map.get(target_id)) |target| {
            const msg = Message{
                .sender_id = sender_id,
                .payload = payload,
            };

            log.debug("runtime.send_msg: {d} -> {d}, payload={d}", .{ sender_id, target_id, payload });

            const success = target.enqueue(msg);

            // Postcondition: if send succeeded, increment counter.
            if (success) {
                self.total_messages_sent += 1;
                std.debug.assert(self.total_messages_sent > 0);
            }

            return success;
        }

        // Negative space: actor not found.
        log.warn("runtime.send_msg: target actor {d} not found", .{target_id});
        return false;
    }

    /// Process one tick across all actors.
    /// Returns number of messages processed.
    pub fn tick(self: *Simple) u32 {

        var processed: u32 = 0;
        var iter = self.actor_map.valueIterator();

        while (iter.next()) |actor| {
            if (actor.*.process_one()) {
                processed += 1;
            }
        }

        // Postcondition: processed count is non-negative.
        std.debug.assert(processed >= 0);

        return processed;
    }

    /// Run the runtime for N ticks (blocking).
    /// Returns total messages processed.
    pub fn run_ticks(self: *Simple, tick_count: u32) u32 {
        // Preconditions: tick count must be valid.
        std.debug.assert(tick_count > 0);
        std.debug.assert(tick_count <= MAX_TICKS);
        std.debug.assert(!self.running);

        log.info("runtime.run_ticks: starting {d} ticks with {d} actors", .{ tick_count, self.actor_count });

        self.running = true;
        defer self.running = false;

        var total_processed: u32 = 0;
        var i: u32 = 0;

        while (i < tick_count and self.running) : (i += 1) {
            const tick_result = self.tick();
            total_processed += tick_result;
            self.total_ticks += 1;

            if (tick_result > 0) {
                log.debug("runtime.run_ticks: tick {d} processed {d} messages", .{ i + 1, tick_result });
            }
        }

        log.info("runtime.run_ticks: completed {d} ticks, processed {d} messages total", .{ i, total_processed });

        // Postcondition: ticks completed. running will be false after defer.
        std.debug.assert(self.total_ticks >= i);

        return total_processed;
    }

    /// Gracefully stop the runtime.
    pub fn stop(self: *Simple) void {
        self.running = false;
    }

    /// Clean up all resources.
    /// Note: Does NOT call deinit on actors (caller is responsible for cleanup).
    /// Only cleans up the runtime's own allocations (actor map and arena).
    pub fn deinit(self: *Simple) void {
        // Ensure runtime is stopped before cleanup.
        self.running = false;

        log.info("runtime.deinit: total_messages_sent={d}, total_ticks={d}, actors={d}", .{ self.total_messages_sent, self.total_ticks, self.actor_count });

        // Postcondition: all runtime resources freed.
        // Actors are the caller's responsibility to clean up.
        self.actor_map.deinit();
        self.arena.deinit();
        self.allocator.destroy(self.arena);

        log.info("runtime.deinit: cleanup complete", .{});
    }
};

// Tests.
test "runtime_init_creates_valid_runtime" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    try std.testing.expectEqual(runtime.actor_count, 0);
    try std.testing.expect(!runtime.running);
    try std.testing.expectEqual(runtime.total_messages_sent, 0);
}

test "runtime_register_actor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try runtime.register(&actor);
    try std.testing.expectEqual(runtime.actor_count, 1);
}

test "runtime_register_duplicate_fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try runtime.register(&actor);
    try std.testing.expectError(error.ActorAlreadyRegistered, runtime.register(&actor));
}

test "runtime_send_msg_succeeds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try runtime.register(&actor);

    const success = runtime.send_msg(1, 2, 42);
    try std.testing.expect(success);
    try std.testing.expectEqual(runtime.total_messages_sent, 1);
}

test "runtime_send_msg_nonexistent_actor_fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    const success = runtime.send_msg(99, 1, 42); // Actor 99 doesn't exist.
    try std.testing.expect(!success);
    try std.testing.expectEqual(runtime.total_messages_sent, 0);
}

test "runtime_tick_processes_messages" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try runtime.register(&actor);

    _ = runtime.send_msg(1, 2, 42);

    runtime.running = true;
    const processed = runtime.tick();
    runtime.running = false;

    try std.testing.expectEqual(processed, 1);
}

test "runtime_run_ticks_executes_multiple_ticks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Simple.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    var actor1 = try Actor.init(1, allocator, 10);
    var actor2 = try Actor.init(2, allocator, 10);
    defer {
        actor1.deinit();
        actor2.deinit();
    }

    try runtime.register(&actor1);
    try runtime.register(&actor2);

    _ = runtime.send_msg(1, 2, 42);
    _ = runtime.send_msg(2, 1, 100);

    const processed = runtime.run_ticks(5);
    try std.testing.expectEqual(processed, 2);
    try std.testing.expectEqual(runtime.total_messages_sent, 2);
    try std.testing.expect(!runtime.running);
}
