const std = @import("std");
const Self = @This();

current_slot: u16,
max_slots: u16,   // peak — what the compiler needs for frame size

pub fn init() Self {
    return .{ .current_slot = 0, .max_slots = 0 };
}

pub fn allocate(self: *Self) u16 {
    const slot = self.current_slot;
    self.current_slot += 1;
    if (self.current_slot > self.max_slots) self.max_slots = self.current_slot;
    return slot;
}

pub fn release(self: *Self, count: u16) void {
    self.current_slot -= count;
}
