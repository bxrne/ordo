const std = @import("std");

const log = std.log.scoped(.ordo_mailbox);

pub const Message = struct {
    sender_id: u128,
    payload: u64,
};

/// Mailbox for actors - bounded, thread-safe queue.
/// All allocations are pre-allocated at initialization.
/// Hard bounded to prevent unbounded queue growth and tail latency spikes.
pub const Mailbox = struct {
    buffer: []Message,
    send_index: u32 = 0,
    recv_index: u32 = 0,
    max_size: u32,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, max_size: u32) !Mailbox {
        // Preconditions: max_size must be positive.
        std.debug.assert(max_size > 0);

        log.debug("mailbox.init: max_size={d}", .{max_size});

        const buffer = try allocator.alloc(Message, max_size);
        std.debug.assert(buffer.len == max_size);

        const mailbox = Mailbox{
            .buffer = buffer,
            .max_size = max_size,
            .send_index = 0,
            .recv_index = 0,
        };

        // Postconditions: mailbox is empty and valid.
        std.debug.assert(mailbox.send_index == mailbox.recv_index);
        std.debug.assert(mailbox.buffer.len > 0);

        log.debug("mailbox.init: created with capacity {d}", .{max_size});

        return mailbox;
    }

    /// Receive a message from mailbox. Returns null if empty.
    pub fn recv(self: *Mailbox) ?Message {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Invariant: recv_index <= send_index (always).
        std.debug.assert(self.recv_index <= self.send_index);

        if (self.send_index == self.recv_index) {
            // Negative space: mailbox is empty, return null.
            log.debug("mailbox.recv: empty", .{});
            return null;
        }

        // Positive space: mailbox has messages.
        std.debug.assert(self.send_index > self.recv_index);

        const msg = self.buffer[self.recv_index % self.max_size];
        self.recv_index += 1;
        log.debug("mailbox.recv: got msg from {d}, payload={d}", .{ msg.sender_id, msg.payload });

        // Wrap indices to prevent unbounded growth.
        if (self.recv_index == self.max_size and self.send_index == self.max_size) {
            self.recv_index = 0;
            self.send_index = 0;
        }

        // Postcondition: indices wrapped correctly if needed.
        std.debug.assert(self.recv_index <= self.max_size or (self.recv_index == 0 and self.send_index == 0));

        return msg;
    }

    /// Send a message to mailbox. Returns true if successful, false if full.
    pub fn send(self: *Mailbox, msg: Message) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Invariant: recv_index <= send_index.
        std.debug.assert(self.recv_index <= self.send_index);

        const count = self.send_index - self.recv_index;

        // Negative space: mailbox is full.
        if (count >= self.max_size) {
            std.debug.assert(count == self.max_size);
            log.debug("mailbox.send: FULL from {d}, payload={d}", .{ msg.sender_id, msg.payload });
            return false;
        }

        // Positive space: mailbox has free space.
        std.debug.assert(count < self.max_size);

        self.buffer[self.send_index % self.max_size] = msg;
        const old_send_index = self.send_index;
        self.send_index += 1;

        log.debug("mailbox.send: accepted from {d}, payload={d}, capacity={d}/{d}", .{ msg.sender_id, msg.payload, count + 1, self.max_size });

        // Postcondition: send_index incremented correctly.
        std.debug.assert(self.send_index == old_send_index + 1);
        std.debug.assert(self.send_index > self.recv_index);

        return true;
    }

    pub fn is_empty(self: *const Mailbox) bool {
        // Cannot acquire mutex in const fn, so check directly.
        // For const context, caller is responsible for synchronization.
        return self.send_index == self.recv_index;
    }

    pub fn deinit(self: *Mailbox, allocator: std.mem.Allocator) void {
        // Precondition: buffer must be valid.
        std.debug.assert(self.buffer.len > 0);
        allocator.free(self.buffer);
    }
};

// Tests.
test "mailbox_init_creates_empty_mailbox" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const mailbox = try Mailbox.init(allocator, 5);
    defer mailbox.deinit(allocator);

    try std.testing.expect(mailbox.is_empty());
    try std.testing.expectEqual(mailbox.max_size, 5);
    try std.testing.expectEqual(mailbox.send_index, 0);
    try std.testing.expectEqual(mailbox.recv_index, 0);
}

test "mailbox_send_recv_fifo_order" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailbox = try Mailbox.init(allocator, 3);
    defer mailbox.deinit(allocator);

    const msg1 = Message{ .sender_id = 1, .payload = 100 };
    const msg2 = Message{ .sender_id = 2, .payload = 200 };

    try std.testing.expect(mailbox.send(msg1));
    try std.testing.expect(mailbox.send(msg2));

    const recv1 = mailbox.recv();
    try std.testing.expect(recv1 != null);
    try std.testing.expectEqual(recv1.?.sender_id, 1);
    try std.testing.expectEqual(recv1.?.payload, 100);

    const recv2 = mailbox.recv();
    try std.testing.expect(recv2 != null);
    try std.testing.expectEqual(recv2.?.sender_id, 2);
    try std.testing.expectEqual(recv2.?.payload, 200);

    try std.testing.expect(mailbox.is_empty());
}

test "mailbox_recv_empty_returns_null" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailbox = try Mailbox.init(allocator, 2);
    defer mailbox.deinit(allocator);

    try std.testing.expect(mailbox.recv() == null);
    try std.testing.expect(mailbox.recv() == null);
}

test "mailbox_full_send_returns_false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailbox = try Mailbox.init(allocator, 2);
    defer mailbox.deinit(allocator);

    const msg = Message{ .sender_id = 1, .payload = 42 };

    try std.testing.expect(mailbox.send(msg));
    try std.testing.expect(mailbox.send(msg));
    try std.testing.expect(!mailbox.send(msg)); // Full.
}

test "mailbox_wraps_indices" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailbox = try Mailbox.init(allocator, 2);
    defer mailbox.deinit(allocator);

    const msg = Message{ .sender_id = 1, .payload = 42 };

    // Fill and drain twice to test wrapping.
    for (0..2) |_| {
        try std.testing.expect(mailbox.send(msg));
        try std.testing.expect(mailbox.send(msg));
        _ = mailbox.recv();
        _ = mailbox.recv();
        try std.testing.expect(mailbox.is_empty());
    }
}

test "mailbox_interleaved_send_recv" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mailbox = try Mailbox.init(allocator, 3);
    defer mailbox.deinit(allocator);

    const msg1 = Message{ .sender_id = 1, .payload = 100 };
    const msg2 = Message{ .sender_id = 2, .payload = 200 };
    const msg3 = Message{ .sender_id = 3, .payload = 300 };

    try std.testing.expect(mailbox.send(msg1));
    try std.testing.expect(mailbox.send(msg2));

    const recv1 = mailbox.recv();
    try std.testing.expect(recv1 != null);
    try std.testing.expectEqual(recv1.?.payload, 100);

    try std.testing.expect(mailbox.send(msg3));

    const recv2 = mailbox.recv();
    const recv3 = mailbox.recv();
    try std.testing.expectEqual(recv2.?.payload, 200);
    try std.testing.expectEqual(recv3.?.payload, 300);
    try std.testing.expect(mailbox.is_empty());
}
