const std = @import("std");

pub const String = struct {
    buffer: []u8,
    length: usize,
    capacity: usize,
    allocator: std.mem.Allocator,
    reallocation_size: usize,

    pub const Error = error{OutOfMemory};

    pub fn init(allocator: std.mem.Allocator, capacity: usize) Error!String {
        return String.initWithReallocation(allocator, capacity, 4096);
    }

    pub fn initWithReallocation(allocator: std.mem.Allocator, capacity: usize, reallocation_size: usize) Error!String {
        return String{
            .buffer = try allocator.alloc(u8, capacity),
            .length = 0,
            .capacity = capacity,
            .allocator = allocator,
            .reallocation_size = reallocation_size,
        };
    }

    pub fn deinit(self: String) void {
        self.allocator.free(self.buffer.ptr[0..self.capacity]);
    }

    pub fn appendFit(self: *String, data: []const u8) Error!usize {
        const end_index = self.length + data.len;
        if (end_index > self.capacity) {
            return Error.OutOfMemory;
        }

        const buffer_ptr = @as([*]u8, @ptrCast(self.buffer));
        const dest_slice = buffer_ptr[self.length..end_index];
        std.mem.copyForwards(u8, dest_slice, data);

        self.length += data.len;

        return self.length;
    }

    pub fn append(self: *String, data: []const u8) Error!usize {
        const end_index = self.length + data.len;
        if (end_index > self.capacity) {
            const new_capacity = self.capacity + self.reallocation_size;
            const new_buffer = try self.allocator.realloc(self.buffer, new_capacity);
            self.buffer = new_buffer;
            self.capacity = new_capacity;
        }

        const buffer_ptr = @as([*]u8, @ptrCast(self.buffer));
        const dest_slice = buffer_ptr[self.length..end_index];
        std.mem.copyForwards(u8, dest_slice, data);

        self.length += data.len;

        return self.length;
    }

    pub fn slice(self: *String) []u8 {
        return self.buffer[0..self.length];
    }

    pub fn split(self: *String, separators: []const u8) error{ OutOfMemory, UninitializedArrayList }!std.ArrayList(*String) {
        var result = std.ArrayList(*String).init(self.allocator);
        errdefer {
            for (result.items) |substring| {
                substring.deinit();
                self.allocator.destroy(substring);
            }
            result.deinit();
        }

        if (self.length == 0) {
            return result;
        }

        var start: usize = 0;
        var idx: usize = 0;

        while (idx < self.length) : (idx += 1) {
            if (idx + 1 > self.length) break;

            const char_slice = self.slice()[idx .. idx + 1];

            const is_separator = std.mem.indexOf(u8, separators, char_slice) != null;
            const is_last_char = idx == self.length - 1;

            var end_idx: usize = idx;
            if (is_last_char and !is_separator) {
                end_idx += 1;
            }

            if (is_separator or is_last_char) {
                if (start < end_idx) {
                    const substring = try self.allocator.create(String);
                    errdefer self.allocator.destroy(substring);

                    substring.* = try String.init(self.allocator, end_idx - start);
                    errdefer substring.deinit();

                    _ = try substring.append(self.slice()[start..end_idx]);
                    try result.append(substring);
                }
                start = idx + 1;
            }
        }

        return result;
    }

    pub fn toLowercase(self: *String) void {
        for (self.slice()) |*char| {
            if (char.* >= 'A' and char.* <= 'Z') {
                char.* += 32;
            }
        }
    }

    pub fn utf8Length(self: *String) !usize {
        return try std.unicode.utf8CountCodepoints(self.slice());
    }
};
