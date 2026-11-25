#include <SDL3/SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlgpu3.h"

extern "C" bool demo_imgui_init(SDL_Window *window, SDL_GPUDevice *device)
{
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    if (!ImGui_ImplSDL3_InitForSDLGPU(window)) {
        ImGui::DestroyContext();
        return false;
    }

    ImGui_ImplSDLGPU3_InitInfo info = {};
    info.Device = device;
    info.ColorTargetFormat = SDL_GetGPUSwapchainTextureFormat(device, window);
    info.MSAASamples = SDL_GPU_SAMPLECOUNT_1;
    if (!ImGui_ImplSDLGPU3_Init(&info)) {
        ImGui_ImplSDL3_Shutdown();
        ImGui::DestroyContext();
        return false;
    }
    return true;
}

extern "C" void demo_imgui_shutdown()
{
    ImGui_ImplSDLGPU3_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();
}

extern "C" void demo_imgui_event(const SDL_Event *event)
{
    ImGui_ImplSDL3_ProcessEvent(event);
}

struct TrainingStatus {
    uint32_t rounds;
    uint32_t capacity;
    uint32_t player_hp;
    uint32_t player_max_hp;
    uint32_t target_hp;
    uint32_t target_max_hp;
    float reload_remaining;
    float reload_duration;
    enum Feedback : uint32_t { None, Surface, Damage, Defeated } feedback;
};

static void hud_panel(ImVec2 position, ImVec2 pivot)
{
    ImGui::SetNextWindowPos(position, ImGuiCond_Always, pivot);
    ImGui::SetNextWindowBgAlpha(0.82f);
}

static void draw_hud(const TrainingStatus &status, bool captured)
{
    constexpr ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize |
        ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoFocusOnAppearing;
    const ImVec2 size = ImGui::GetIO().DisplaySize;
    if (size.x <= 0 || size.y <= 0)
        return;

    constexpr float margin = 12.0f;
    hud_panel(ImVec2(margin, size.y - margin), ImVec2(0, 1));
    if (ImGui::Begin("##PlayerHealth", nullptr, flags)) {
        ImGui::Text("Health  %u / %u", status.player_hp, status.player_max_hp);
        const float fraction = status.player_max_hp ? (float)status.player_hp / status.player_max_hp : 0.0f;
        ImGui::PushStyleColor(ImGuiCol_PlotHistogram, ImVec4(0.35f, 0.85f, 0.58f, 1));
        ImGui::ProgressBar(fraction, ImVec2(124, 5), "");
        ImGui::PopStyleColor();
    }
    ImGui::End();

    hud_panel(ImVec2(size.x - margin, size.y - margin), ImVec2(1, 1));
    if (ImGui::Begin("##Magazine", nullptr, flags)) {
        ImGui::Text("Ammo  %u / %u", status.rounds, status.capacity);
        if (status.reload_remaining > 0.0f) {
            ImGui::Text("Reloading %.1f s", status.reload_remaining);
            const float fraction = 1.0f - status.reload_remaining / status.reload_duration;
            ImGui::ProgressBar(fraction, ImVec2(124, 5), "");
        } else if (status.rounds == 0) {
            ImGui::TextUnformatted("R to reload");
        }
    }
    ImGui::End();

    hud_panel(ImVec2(size.x - margin, margin), ImVec2(1, 0));
    if (ImGui::Begin("##FrameRate", nullptr, flags))
        ImGui::Text("%.0f FPS", ImGui::GetIO().Framerate);
    ImGui::End();

    if (!captured)
        return;
    const ImVec2 center(size.x * 0.5f, size.y * 0.5f);
    ImDrawList *foreground = ImGui::GetForegroundDrawList();
    const ImVec2 left(center.x - 5, center.y), right(center.x + 5, center.y);
    const ImVec2 top(center.x, center.y - 5), bottom(center.x, center.y + 5);
    foreground->AddLine(left, right, IM_COL32_BLACK, 3.0f);
    foreground->AddLine(top, bottom, IM_COL32_BLACK, 3.0f);
    foreground->AddLine(left, right, IM_COL32_WHITE);
    foreground->AddLine(top, bottom, IM_COL32_WHITE);
    if (status.feedback != TrainingStatus::None) {
        const ImU32 color = status.feedback == TrainingStatus::Defeated ? IM_COL32(255, 80, 80, 255)
                            : status.feedback == TrainingStatus::Damage ? IM_COL32(255, 210, 70, 255)
                            : IM_COL32(140, 205, 255, 255);
        for (int x = -1; x <= 1; x += 2) {
            for (int y = -1; y <= 1; y += 2) {
                foreground->AddLine(ImVec2(center.x + 6 * x, center.y + 6 * y),
                                    ImVec2(center.x + 13 * x, center.y + 13 * y), color, 2.0f);
            }
        }
    }
}

extern "C" void demo_imgui_prepare(SDL_GPUCommandBuffer *commands, float ms, bool captured, float *speed, size_t draw_count,
                                  size_t body_count, uint32_t physics_steps, float ray_distance, bool grounded,
                                  const TrainingStatus *status)
{
    ImGui_ImplSDLGPU3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    ImGui::SetNextWindowPos(ImVec2(12, 12), ImGuiCond_Once);
    if (ImGui::Begin("Scene", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        if (status)
            ImGui::Text("Frame: %.2f ms", ms);
        else
            ImGui::Text("Frame: %.2f ms  (%.0f FPS)", ms, ms > 0.0f ? 1000.0f / ms : 0.0f);
        ImGui::Text("Opaque draws: %zu", draw_count);
        ImGui::TextUnformatted(captured ? "Tab: release mouse" : "Tab: capture mouse");
        if (body_count) {
            ImGui::TextUnformatted("WASD: move | Shift: sprint | Space: jump");
            ImGui::TextUnformatted(grounded ? "Player: grounded" : "Player: airborne");
            ImGui::Text("Jolt bodies: %zu | Steps: %u", body_count, physics_steps);
            if (ray_distance >= 0.0f)
                ImGui::Text("Ray hit: %.2f m", ray_distance);
        } else ImGui::TextUnformatted("WASD: fly | Space / Ctrl: up / down");
        if (status) {
            ImGui::TextUnformatted("Left mouse: fire | R: reload");
            if (status->target_hp > 0)
                ImGui::Text("Target: %u / %u HP", status->target_hp, status->target_max_hp);
            else
                ImGui::TextUnformatted("Target down");
        }
        if (speed) {
            ImGui::SetNextItemWidth(170);
            ImGui::SliderFloat("Rotation", speed, 0.0f, 3.0f, "%.2f rad/s");
        }
    }
    ImGui::End();
    if (status)
        draw_hud(*status, captured);
    ImGui::Render();
    ImGui_ImplSDLGPU3_PrepareDrawData(ImGui::GetDrawData(), commands);
}

extern "C" void demo_imgui_draw(SDL_GPUCommandBuffer *commands, SDL_GPURenderPass *pass)
{
    ImGui_ImplSDLGPU3_RenderDrawData(ImGui::GetDrawData(), commands, pass);
}
