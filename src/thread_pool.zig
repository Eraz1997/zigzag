const std = @import("std");
const logging = @import("./logging.zig");
const memory = @import("./memory.zig");
const task = @import("./task.zig");
const app = @import("./app.zig");

const TaskQueue = std.fifo.LinearFifo(task.Task, .Dynamic);
const WorkersSet = std.AutoHashMap(usize, *const std.Thread);

pub const ThreadPool = struct {
    max_workers: usize,
    allocator: std.mem.Allocator,
    gpa: memory.GeneralPurposeAllocator,
    queue: TaskQueue,
    active_workers: WorkersSet,
    last_worker_id: usize = 0,
    queue_mutex: std.Thread.Mutex = std.Thread.Mutex{},
    active_workers_mutex: std.Thread.Mutex = std.Thread.Mutex{},

    pub fn init() ThreadPool {
        var gpa = memory.GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        const max_workers = std.Thread.getCpuCount() catch |err| error_handler: {
            logging.Logger.err("Could not get the number of available CPUs: {}", .{err});
            break :error_handler 1;
        };

        return ThreadPool{
            .max_workers = max_workers,
            .allocator = allocator,
            .gpa = gpa,
            .queue = TaskQueue.init(allocator),
            .active_workers = WorkersSet.init(allocator),
        };
    }

    pub fn push_task(
        self: *ThreadPool,
        new_task: task.Task,
    ) void {
        if (self.active_workers.count() < self.max_workers) {
            self.active_workers_mutex.lock();
            const worker_id = self.last_worker_id +% 1;
            const thread = std.Thread.spawn(.{ .allocator = self.allocator }, handle_task, .{ self, new_task, worker_id }) catch |err| {
                logging.Logger.err("Cannot spawn thread: {}", .{err});
                return;
            };
            self.active_workers.put(worker_id, &thread) catch |err| {
                logging.Logger.err(
                    "Cannot insert worker ID {} in pool. Thread might not be joined and more threads could be spawned: {}",
                    .{ worker_id, err },
                );
            };
            self.active_workers_mutex.unlock();
        } else {
            self.queue_mutex.lock();
            self.queue.writeItem(new_task) catch |err| {
                logging.Logger.err("Failed to insert task in the queue: {}", .{err});
            };
            self.queue_mutex.unlock();
        }
    }

    pub fn deinit(self: *ThreadPool) void {
        std.debug.assert(self.gpa.deinit() == .ok);
        self.queue.deinit();
        var worker_iterator = self.active_workers.valueIterator();
        while (worker_iterator.next()) |worker| {
            (worker.*).join();
        }
        self.active_workers.deinit();
    }
};

fn handle_task(thread_pool: *ThreadPool, task_to_execute: task.Task, worker_id: usize) void {
    task_to_execute.function(task_to_execute.app, task_to_execute.response);
    thread_pool.queue_mutex.lock();
    const candidate_next_task = thread_pool.queue.readItem();
    thread_pool.queue_mutex.unlock();
    if (candidate_next_task) |next_task| {
        return handle_task(thread_pool, next_task, worker_id);
    } else {
        thread_pool.active_workers_mutex.lock();
        if (!thread_pool.active_workers.remove(worker_id)) {
            logging.Logger.err("Worker ID {} could not be found, something went wrong with pool handling.", .{worker_id});
        }
        thread_pool.active_workers_mutex.unlock();
    }
}
