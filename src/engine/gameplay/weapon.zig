//! Frame-driven weapon state. The caller supplies input and resolves each shot.
pub const WeaponData = struct {
    damage: u16,
    rounds_per_second: f32,
    magazine_size: u16,
    reload_seconds: f32,
    range: f32,
};

pub const Weapon = struct {
    pub const State = enum { idle, firing, reloading };

    data: WeaponData,
    rounds: u16,
    state: State = .idle,
    remaining: f32 = 0,

    pub fn init(data: WeaponData) Weapon {
        return .{ .data = data, .rounds = data.magazine_size };
    }

    /// Returns true once per accepted shot. A reload uses the training range's unlimited reserve.
    pub fn update(self: *Weapon, dt: f32, trigger: bool, reload: bool) bool {
        self.remaining = @max(0, self.remaining - dt);
        if (self.state == .reloading) {
            if (self.remaining > 0) return false;
            self.rounds = self.data.magazine_size;
            self.state = .idle;
            return false;
        }
        // Keep the shot cooldown if the player begins reloading during it.
        if (reload and self.rounds < self.data.magazine_size) {
            self.remaining = @max(self.remaining, self.data.reload_seconds);
            self.state = .reloading;
            return false;
        }
        if (self.remaining > 0) return false;
        self.state = .idle;
        if (!trigger or self.rounds == 0) return false;

        self.rounds -= 1;
        self.state = .firing;
        self.remaining = 1 / self.data.rounds_per_second;
        return true;
    }
};
