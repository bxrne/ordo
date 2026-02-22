# Ordo: Actor Runtime

A safety-first actor model library for Zig, designed for high-chattiness applications with addressable messaging, bounded memory, and explicit resource management.

## Overview

Ordo provides a complete actor-based runtime with these characteristics:

- **Addressable Messaging**: Send messages to actors by 128-bit ID
- **Thread-Safe Mailboxes**: Bounded, synchronized message queues prevent unbounded growth
- **Finite State Machines**: Simple, exhaustive state management with explicit transitions
- **Extensible Scheduling**: Support for multiple scheduling strategies (RoundRobin, Immediate, RAFT)
- **Static Memory Allocation**: All allocations happen at startup; no dynamic allocation during execution
- **Network-Ready**: Architecture prepared for distributed actor deployment
- **Comprehensive Assertions**: Positive and negative space coverage for correctness guarantees

## Core Components

### Actor
The fundamental unit of computation. Each actor has:
- Globally addressable 128-bit ID
- Bounded, thread-safe mailbox
- Finite state machine for behavior
- Non-blocking message processing

### Mailbox
Thread-safe message queue with hard capacity limits. Prevents:
- Unbounded queue growth
- Tail latency spikes from queue exhaustion
- Use-after-free from buffer underflow

### Finite State Machine
Simple, exhaustive state machine with four states (Idle, Running, Finished, Error) and four events (Start, Stop, Complete, Fail). All state/event pairs are explicitly handled.

### SimpleRuntime
Orchestrates actors, routes messages, and implements scheduling. Statically bounded to 256 actors maximum with configurable scheduling strategy.

## Building & Testing

Build the project:
```bash
zig build
```

Run POC:
```bash
zig build run
```

Run comprehensive test suite:
```bash
zig build test
```

The test suite covers:
- Mailbox send/recv, wrapping, full/empty conditions
- Actor initialization, message processing, FSM transitions
- Runtime registration, message routing, tick scheduling
- Error cases and assertion verification

## Example Usage

```zig
const std = @import("std");
const ordo = @import("ordo");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create runtime with RoundRobin scheduling
    var runtime = try ordo.SimpleRuntime.init(allocator, 4, .RoundRobin);
    defer runtime.deinit();

    // Create and register actors
    var actor1 = try ordo.Actor.init(1, allocator, 10);
    var actor2 = try ordo.Actor.init(2, allocator, 10);
    defer {
        actor1.deinit();
        actor2.deinit();
    }

    try runtime.register(&actor1);
    try runtime.register(&actor2);

    // Send messages between actors
    _ = runtime.send_msg(2, 1, 42); // Actor 1 -> Actor 2, payload=42

    // Execute 10 scheduling ticks
    const processed = runtime.run_ticks(10);
    std.debug.print("Processed {d} messages\n", .{processed});
}
```

## Scheduling Strategies

The runtime supports pluggable scheduling strategies:

- **RoundRobin** (current): Process one message from each actor per tick
- **Immediate** (extensible): Placeholder for future implementation
- **RAFT** (planned): Consensus-based scheduling for distributed deployments

## Memory Model

All memory is pre-allocated at startup:
- Arena allocator for runtime
- Pre-sized mailbox buffers for each actor
- No dynamic allocation during execution
- All cleanup tracked with `defer` statements

This design prevents:
- Unbounded heap growth
- Allocation failures during execution
- Garbage collection pauses
- Unpredictable memory behavior in production

## Assertion Coverage

Every function includes:
- **Preconditions**: What must be true before the function runs
- **Postconditions**: What is guaranteed to be true after
- **Invariants**: What is always true during execution
- **Positive space**: What we expect to happen
- **Negative space**: What we don't expect (and verify doesn't)

This exhaustive assertion approach enables early detection of subtle bugs and provides strong correctness guarantees.

## Network Readiness

The architecture is designed for distributed deployment:
- Actors have globally addressable 128-bit IDs that can encode cluster/node/actor hierarchy
- Message structure is trivially serializable for network transport
- Thread-safe mailboxes are ready for multi-threaded remote dispatch
- Scheduling strategies can evolve without breaking core abstractions

## Future Roadmap

- RAFT consensus protocol for distributed scheduling
- Network transport layer for inter-node communication
- Supervision strategies (restart policies, monitoring)
- Lock-free mailbox variants for high-contention scenarios
- Custom message handlers and behavior plugins

## References

- **Safety Inspiration**: NASA's Power of Ten Rules for Developing Safety-Critical Code
- **Coding Style**: TigerBeetle's Coding Style Guide
- **Actor Model**: Erlang/Akka actor model adapted for safety and performance
- **Testing Philosophy**: VOPR (Vagabond Or Principled Raid) - simulation-based property testing

## Why TigerStyle?

TigerStyle emphasizes that "style is necessary only where understanding is missing." By making the system's design explicit through:
- Bounded allocations
- Exhaustive assertions
- Simple control flow
- Clear naming
- Explicit error handling

We achieve code that is simultaneously more safe, more performant, and easier to understand.
