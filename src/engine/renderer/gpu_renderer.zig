//! M2 SDL GPU swapchain clear. Use on the window's owning thread.
const builtin = @import("builtin");
const sdl = @import("sdl3");
const Logger = @import("zigsdl3demo").Logger;

const log = Logger.init(.info);
const clear_color: sdl.FColor = .{ .r = 0.1, .g = 0.2, .b = 0.4, .a = 1.0 };

pub const GpuRenderer = struct {
    device: *sdl.gpu.Device,
    window: sdl.Window,

    pub const Extent = struct { width: u32, height: u32 };

    pub fn init(window: sdl.Window) !GpuRenderer {
        const device = sdl.gpu.Device.init(.{ .spirv = true }, builtin.mode == .debug, "vulkan") catch |err| {
            log.log(.error_, "gpu", "创建 Vulkan 设备失败: {s}", .{sdl.lastErrorText()});
            return err;
        };
        errdefer device.deinit();
        if (!device.shaderFormats().spirv) {
            log.log(.error_, "gpu", "Vulkan 设备未报告 SPIR-V 支持", .{});
            return error.UnsupportedShaderFormat;
        }
        device.claimWindow(window) catch |err| {
            log.log(.error_, "gpu", "声明窗口失败: {s}", .{sdl.lastErrorText()});
            return err;
        };
        errdefer device.releaseWindow(window);
        device.setSwapchainParameters(window, .sdr, .vsync) catch |err| {
            log.log(.error_, "gpu", "配置交换链失败: {s}", .{sdl.lastErrorText()});
            return err;
        };

        log.log(.info, "gpu", "后端 {s}，支持 SPIR-V，交换链格式 {s}", .{
            device.driver(), @tagName(device.swapchainTextureFormat(window)),
        });
        return .{ .device = device, .window = window };
    }

    pub fn deinit(self: GpuRenderer) void {
        self.device.waitForIdle() catch {
            log.log(.warn, "gpu", "等待设备空闲失败: {s}", .{sdl.lastErrorText()});
        };
        self.device.releaseWindow(self.window);
        self.device.deinit();
    }

    /// Returns null when SDL skips presentation, for example during minimization.
    pub fn clear(self: GpuRenderer) !?Extent {
        const commands = self.device.acquireCommandBuffer() catch |err| {
            log.log(.error_, "gpu", "获取命令缓冲失败: {s}", .{sdl.lastErrorText()});
            return err;
        };
        const swapchain = commands.waitAndAcquireSwapchainTexture(self.window) catch |err| {
            log.log(.error_, "gpu", "获取交换链图像失败: {s}", .{sdl.lastErrorText()});
            cancel(commands) catch {};
            return err;
        };
        const texture = swapchain.texture orelse {
            try cancel(commands);
            return null;
        };

        const pass = commands.beginRenderPass(&.{.{
            .texture = texture,
            .clear_color = clear_color,
            .load_op = .clear,
            .store_op = .store,
        }}, null) catch |err| {
            log.log(.error_, "gpu", "开始清屏 Render Pass 失败: {s}", .{sdl.lastErrorText()});
            // After acquiring a swapchain image, SDL requires submission even on failure.
            submit(commands) catch {};
            return err;
        };
        pass.end();
        try submit(commands);
        return .{ .width = swapchain.width, .height = swapchain.height };
    }
};

fn cancel(commands: *sdl.gpu.CommandBuffer) !void {
    commands.cancel() catch |err| {
        log.log(.error_, "gpu", "取消命令缓冲失败: {s}", .{sdl.lastErrorText()});
        return err;
    };
}

fn submit(commands: *sdl.gpu.CommandBuffer) !void {
    commands.submit() catch |err| {
        log.log(.error_, "gpu", "提交命令缓冲失败: {s}", .{sdl.lastErrorText()});
        return err;
    };
}
