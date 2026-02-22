const std = @import("std");
const ordo = @import("ordo");

// Actor IDs
const READER_ID = 1;
const WRITER_ID = 2;
const APPENDER_ID = 3;

// Message payloads (represent line numbers to append)
const MSG_READ = 1;
const MSG_WRITE = 2;
const MSG_APPEND = 3;

const OUTPUT_FILE = "output.txt";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create output file
    const cwd = std.fs.cwd();
    const file = try cwd.createFile(OUTPUT_FILE, .{
        .truncate = true,
    });
    defer file.close();

    // Initialize runtime
    var runtime = try ordo.SimpleRuntime.init(allocator, 1, .RoundRobin);
    defer runtime.deinit();

    // Create three actors for append pipeline
    var reader = try ordo.Actor.init(READER_ID, allocator, 10);
    var writer = try ordo.Actor.init(WRITER_ID, allocator, 10);
    var appender = try ordo.Actor.init(APPENDER_ID, allocator, 10);
    defer {
        reader.deinit();
        writer.deinit();
        appender.deinit();
    }

    // Register actors with runtime
    try runtime.register(&reader);
    try runtime.register(&writer);
    try runtime.register(&appender);

    std.debug.print("Append Pipeline: Reader -> Writer -> Appender -> File\n", .{});
    std.debug.print("Output file: {s}\n", .{OUTPUT_FILE});
    std.debug.print("Registered 3 actors\n\n", .{});

    // Kick off the pipeline: reader sends to writer
    _ = runtime.send_msg(WRITER_ID, READER_ID, MSG_READ);
    std.debug.print("Actor {d} sends MSG_READ to actor {d}\n", .{ READER_ID, WRITER_ID });

    // Writer will send to appender
    _ = runtime.send_msg(APPENDER_ID, WRITER_ID, MSG_WRITE);
    std.debug.print("Actor {d} sends MSG_WRITE to actor {d}\n", .{ WRITER_ID, APPENDER_ID });

    // Appender receives and appends
    _ = runtime.send_msg(APPENDER_ID, APPENDER_ID, MSG_APPEND);
    std.debug.print("Actor {d} sends MSG_APPEND (self)\n\n", .{APPENDER_ID});

    // Run the actor system for 10 ticks
    std.debug.print("Running runtime for 10 ticks...\n", .{});
    const processed = runtime.run_ticks(10);

    // Append lines to file based on processed messages
    const file_write = try cwd.openFile(OUTPUT_FILE, .{
        .mode = .write_only,
    });
    defer file_write.close();

    try file_write.seekFromEnd(0);

    var buf: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    // Each processed message = one line
    for (0..processed) |i| {
        fba.reset();
        const line = try std.fmt.allocPrint(fba.allocator(), "Line {d}: Message processed at tick\n", .{i + 1});
        try file_write.writeAll(line);
    }

    std.debug.print("\nPipeline Complete:\n", .{});
    std.debug.print("  Processed: {d} messages\n", .{processed});
    std.debug.print("  Total sent: {d} messages\n", .{runtime.total_messages_sent});
    std.debug.print("  Total ticks: {d}\n", .{runtime.total_ticks});
    std.debug.print("  Reader processed: {d}\n", .{reader.processed_count});
    std.debug.print("  Writer processed: {d}\n", .{writer.processed_count});
    std.debug.print("  Appender processed: {d}\n", .{appender.processed_count});
    std.debug.print("  Appended {d} lines to {s}\n", .{ processed, OUTPUT_FILE });
}
