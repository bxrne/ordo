const std = @import("std");
const Mailbox = @import("mailbox.zig").Mailbox;
const Message = @import("mailbox.zig").Message;
const Fsm = @import("fsm.zig").Fsm;
const Event = @import("fsm.zig").Event;

const log = std.log.scoped(.ordo_actor);

/// Actor with addressable ID, bounded mailbox, and finite state machine.
/// Designed for high-chattiness local actor model with supervisor mailbox.
/// Future: networked actors, RAFT plugin, workload distribution.
pub const Actor = struct {
    id: u128,
    mailbox: Mailbox,
    state: Fsm,
    allocator: std.mem.Allocator,
    processed_count: u32 = 0,

    pub fn init(
        id: u128,
        allocator: std.mem.Allocator,
        mailbox_size: u32,
    ) !Actor {
        // Preconditions: id must be non-zero, mailbox_size must be positive.
        std.debug.assert(id > 0);
        std.debug.assert(mailbox_size > 0);

        log.info("actor.init: id={d}, mailbox_size={d}", .{ id, mailbox_size });

        const mailbox = try Mailbox.init(allocator, mailbox_size);
        std.debug.assert(mailbox.max_size == mailbox_size);

        const actor = Actor{
            .id = id,
            .mailbox = mailbox,
            .state = Fsm.init(),
            .allocator = allocator,
            .processed_count = 0,
        };

        // Postconditions: actor is initialized with valid state.
        std.debug.assert(actor.id == id);
        std.debug.assert(actor.mailbox.is_empty());
        std.debug.assert(actor.processed_count == 0);

        log.info("actor.init: actor {d} created", .{id});

        return actor;
    }

    /// Process one message from the mailbox (non-blocking).
    /// Returns true if a message was processed, false if mailbox empty.
    pub fn process_one(self: *Actor) bool {
        // Precondition: actor is valid.
        std.debug.assert(self.id > 0);

        if (self.mailbox.recv()) |msg| {
            // Positive space: received a message.
            std.debug.assert(msg.sender_id > 0);

            log.debug("actor {d}: processing msg from {d}, payload={d}", .{ self.id, msg.sender_id, msg.payload });

            // Simulate message handling with FSM state transitions.
            if (msg.payload > 0) {
                self.state.on_event(Event.Start);
            }

            self.processed_count += 1;

            log.debug("actor {d}: processed {d} messages total", .{ self.id, self.processed_count });

            // Postcondition: message was processed and counter incremented.
            std.debug.assert(self.processed_count > 0);

            return true;
        }

        // Negative space: mailbox was empty.
        std.debug.assert(self.mailbox.is_empty());
        return false;
    }

    /// Enqueue a message to this actor's mailbox.
    /// Returns true if successful, false if mailbox is full.
    pub fn enqueue(self: *Actor, msg: Message) bool {
        // Preconditions: actor and message are valid.
        std.debug.assert(self.id > 0);
        std.debug.assert(msg.sender_id > 0);

        const result = self.mailbox.send(msg);

        if (result) {
            log.debug("actor {d}: enqueued msg from {d}", .{ self.id, msg.sender_id });
            // Postcondition: if send succeeded, mailbox is not empty.
            std.debug.assert(!self.mailbox.is_empty());
        } else {
            log.warn("actor {d}: failed to enqueue msg from {d} (mailbox full)", .{ self.id, msg.sender_id });
        }

        return result;
    }

    pub fn deinit(self: *Actor) void {
        // Precondition: actor is valid.
        std.debug.assert(self.id > 0);
        log.info("actor.deinit: actor {d}, processed {d} messages", .{ self.id, self.processed_count });
        self.mailbox.deinit(self.allocator);
    }
};

// Tests.
test "actor_init_creates_valid_actor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try std.testing.expectEqual(actor.id, 1);
    try std.testing.expect(actor.mailbox.is_empty());
    try std.testing.expectEqual(actor.processed_count, 0);
}

test "actor_enqueue_message_succeeds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    const msg = Message{ .sender_id = 2, .payload = 42 };

    try std.testing.expect(actor.enqueue(msg));
    try std.testing.expect(!actor.mailbox.is_empty());
}

test "actor_process_one_handles_message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    const msg = Message{ .sender_id = 2, .payload = 42 };
    try std.testing.expect(actor.enqueue(msg));

    try std.testing.expect(actor.process_one());
    try std.testing.expectEqual(actor.processed_count, 1);
    try std.testing.expect(actor.mailbox.is_empty());
}

test "actor_process_one_empty_returns_false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    try std.testing.expect(!actor.process_one());
    try std.testing.expectEqual(actor.processed_count, 0);
}

test "actor_process_multiple_messages" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    const msg1 = Message{ .sender_id = 2, .payload = 100 };
    const msg2 = Message{ .sender_id = 3, .payload = 200 };
    const msg3 = Message{ .sender_id = 4, .payload = 300 };

    try std.testing.expect(actor.enqueue(msg1));
    try std.testing.expect(actor.enqueue(msg2));
    try std.testing.expect(actor.enqueue(msg3));

    try std.testing.expect(actor.process_one());
    try std.testing.expect(actor.process_one());
    try std.testing.expect(actor.process_one());
    try std.testing.expect(!actor.process_one());

    try std.testing.expectEqual(actor.processed_count, 3);
}

test "actor_mailbox_full_enqueue_fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 2);
    defer actor.deinit();

    const msg = Message{ .sender_id = 2, .payload = 42 };

    try std.testing.expect(actor.enqueue(msg));
    try std.testing.expect(actor.enqueue(msg));
    try std.testing.expect(!actor.enqueue(msg)); // Full.
}

test "actor_fsm_transitions_on_message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var actor = try Actor.init(1, allocator, 10);
    defer actor.deinit();

    // Initial state is Idle.
    try std.testing.expect(actor.state.state == std.meta.stringToEnum(Fsm, "Idle").?);

    // Send and process message with payload > 0.
    const msg = Message{ .sender_id = 2, .payload = 1 };
    try std.testing.expect(actor.enqueue(msg));
    try std.testing.expect(actor.process_one());

    // After processing, state should be Running.
    try std.testing.expect(actor.state.state == std.meta.stringToEnum(Fsm, "Running").?);
}
