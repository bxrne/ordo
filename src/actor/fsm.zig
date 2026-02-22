const std = @import("std");

const log = std.log.scoped(.ordo_fsm);

pub const State = enum {
    Idle,
    Running,
    Finished,
    Error,
};

pub const Event = enum {
    Start,
    Stop,
    Complete,
    Fail,
};

/// Finite state machine for actor behavior.
/// Simple, explicit control flow with no recursion.
pub const Fsm = struct {
    state: State,

    pub fn init() Fsm {
        const fsm = Fsm{ .state = State.Idle };

        // Postcondition: FSM starts in Idle state.
        std.debug.assert(fsm.state == State.Idle);

        return fsm;
    }

    /// Transition state based on event.
    /// Exhaustive handling of all state/event pairs.
    pub fn on_event(self: *Fsm, event: Event) void {
        const old_state = self.state;

        // Positive and negative spaces: all state/event pairs handled.
        switch (self.state) {
            State.Idle => {
                switch (event) {
                    Event.Start => {
                        self.state = State.Running;
                        // Postcondition: transitioned to Running.
                        std.debug.assert(self.state == State.Running);
                    },
                    Event.Stop, Event.Complete, Event.Fail => {
                        // Negative space: these events have no effect in Idle state.
                        std.debug.assert(self.state == State.Idle);
                    },
                }
            },
            State.Running => {
                switch (event) {
                    Event.Complete => {
                        self.state = State.Finished;
                        std.debug.assert(self.state == State.Finished);
                    },
                    Event.Fail => {
                        self.state = State.Error;
                        std.debug.assert(self.state == State.Error);
                    },
                    Event.Stop => {
                        self.state = State.Idle;
                        std.debug.assert(self.state == State.Idle);
                    },
                    Event.Start => {
                        // Negative space: Start is already running.
                        std.debug.assert(self.state == State.Running);
                    },
                }
            },
            State.Finished, State.Error => {
                switch (event) {
                    Event.Start => {
                        self.state = State.Running;
                        std.debug.assert(self.state == State.Running);
                    },
                    Event.Stop, Event.Complete, Event.Fail => {
                        // Negative space: no effect on terminal states.
                        std.debug.assert(self.state == State.Finished or self.state == State.Error);
                    },
                }
            },
        }

        if (old_state != self.state) {
            log.debug(
                "FSM transition: {s} -> {s} (event={s})",
                .{ @tagName(old_state), @tagName(self.state), @tagName(event) },
            );
        }
    }
};

// Tests.
test "fsm_init_starts_idle" {
    const fsm = Fsm.init();
    try std.testing.expect(fsm.state == State.Idle);
}

test "fsm_idle_to_running" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    try std.testing.expect(fsm.state == State.Running);
}

test "fsm_running_to_finished" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Complete);
    try std.testing.expect(fsm.state == State.Finished);
}

test "fsm_running_to_error" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Fail);
    try std.testing.expect(fsm.state == State.Error);
}

test "fsm_running_to_idle" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Stop);
    try std.testing.expect(fsm.state == State.Idle);
}

test "fsm_finished_to_running" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Complete);
    fsm.on_event(Event.Start);
    try std.testing.expect(fsm.state == State.Running);
}

test "fsm_error_to_running" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Fail);
    fsm.on_event(Event.Start);
    try std.testing.expect(fsm.state == State.Running);
}

test "fsm_idle_ignores_invalid_events" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Complete);
    try std.testing.expect(fsm.state == State.Idle);

    fsm.on_event(Event.Fail);
    try std.testing.expect(fsm.state == State.Idle);

    fsm.on_event(Event.Stop);
    try std.testing.expect(fsm.state == State.Idle);
}

test "fsm_finished_ignores_completion_events" {
    var fsm = Fsm.init();
    fsm.on_event(Event.Start);
    fsm.on_event(Event.Complete);
    fsm.on_event(Event.Fail); // Ignored in Finished.
    try std.testing.expect(fsm.state == State.Finished);

    fsm.on_event(Event.Stop); // Ignored in Finished.
    try std.testing.expect(fsm.state == State.Finished);
}
