//! Damageable entities opt in by carrying a Health component.
pub const Health = struct {
    current: u16,
    maximum: u16,

    pub const Damage = struct {
        applied: u16,
        remaining: u16,
    };

    pub fn init(maximum: u16) Health {
        return .{ .current = maximum, .maximum = maximum };
    }

    pub fn applyDamage(self: *Health, amount: u16) ?Damage {
        const applied = @min(self.current, amount);
        if (applied == 0) return null;
        self.current -= applied;
        return .{ .applied = applied, .remaining = self.current };
    }
};
