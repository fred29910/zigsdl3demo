#include <SDL3/SDL.h>
#include <algorithm>
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

extern "C" bool demo_imgui_load_font_bytes(const void *bytes, size_t len)
{
    if (bytes == nullptr || len == 0)
        return false;
    ImGuiIO &io = ImGui::GetIO();
    io.Fonts->Clear();
    // 字体字节由 Zig @embedFile 静态持有，禁止 ImGui 接管并释放。
    ImFontConfig font_cfg;
    font_cfg.FontDataOwnedByAtlas = false;
    ImFont *font = io.Fonts->AddFontFromMemoryTTF(const_cast<void *>(bytes), (int)len, 20.0f, &font_cfg);
    if (font == nullptr)
        return false;
    return true;
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
    enum Phase : uint32_t { Playing, Won, Lost } phase;
    enum EnemyState : uint32_t { Patrol, Chase, Attack, Down } enemy_state;
    uint32_t enemy_hp;
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

    if (status.phase != TrainingStatus::Playing || !captured) {
        hud_panel(ImVec2(size.x * 0.5f, size.y * 0.5f), ImVec2(0.5f, 0.5f));
        if (ImGui::Begin("##RoundStatus", nullptr, flags)) {
            if (status.phase == TrainingStatus::Won) {
                ImGui::TextUnformatted("Range cleared");
                ImGui::TextUnformatted("E: try again");
            } else if (status.phase == TrainingStatus::Lost) {
                ImGui::TextUnformatted("Training failed");
                ImGui::TextUnformatted("E: try again");
            } else {
                ImGui::TextUnformatted("FPS Training Range");
                ImGui::TextUnformatted("Disable the blue target and orange robot");
                ImGui::TextUnformatted("Tab: capture mouse and play");
            }
        }
        ImGui::End();
        return;
    }
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
                                  size_t entity_count, size_t body_count, uint32_t physics_steps, float ray_distance, bool grounded,
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
        ImGui::Text("Draws: %zu | Entities: %zu", draw_count, entity_count);
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
            ImGui::Text("Objectives: %u / 2", unsigned(status->target_hp == 0) + unsigned(status->enemy_hp == 0));
            if (status->target_hp > 0)
                ImGui::Text("Target: %u / %u HP", status->target_hp, status->target_max_hp);
            else
                ImGui::TextUnformatted("Target down");
            const char *states[] = {"Patrol", "Chase", "Attack", "Down"};
            ImGui::Text("Robot: %s (%u HP)", states[status->enemy_state], status->enemy_hp);
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

extern "C" int demo_imgui_prepare_lobby(float *sensitivity, int *volume, const char *notice)
{
    ImGui_ImplSDLGPU3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();

    int action = 0;
    const ImVec2 display = ImGui::GetIO().DisplaySize;
    const float ui_scale = std::max(1.0f, std::min(display.x, display.y) / 720.0f);

    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f));
    ImGui::SetNextWindowSize(display);
    constexpr ImGuiWindowFlags root_flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(24.0f * ui_scale, 24.0f * ui_scale));
    if (ImGui::Begin("##LobbyRoot", nullptr, root_flags)) {
        ImGui::TextUnformatted("训练场大厅");
        ImGui::TextUnformatted("SDL3 / Vulkan 训练场演示入口");
        ImGui::Spacing();

        if (notice != nullptr && notice[0] != '\0') {
            ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.72f, 0.12f, 0.12f, 1.0f));
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
            const float banner_h = 44.0f * ui_scale;
            if (ImGui::BeginChild("##LobbyNotice", ImVec2(0.0f, banner_h), true)) {
                ImGui::TextWrapped("%s", notice);
            }
            ImGui::EndChild();
            ImGui::PopStyleColor(2);
            ImGui::Spacing();
        }

        const float button_h = 46.0f * ui_scale;
        const float spacing = 10.0f * ui_scale;
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(8.0f * ui_scale, spacing));

        // Main focus entry.
        if (ImGui::IsWindowAppearing())
            ImGui::SetKeyboardFocusHere();
        if (ImGui::Button("开始训练", ImVec2(-1.0f, button_h))) action = 1;

        if (ImGui::Button("外部模型预览", ImVec2(-1.0f, button_h))) action = 2;
        if (ImGui::Button("2D 输入演示", ImVec2(-1.0f, button_h))) action = 3;
        if (ImGui::Button("Vulkan 清屏演示", ImVec2(-1.0f, button_h))) action = 4;

        ImGui::Spacing();
        ImGui::TextUnformatted("设置");
        if (sensitivity != nullptr) {
            ImGui::SetNextItemWidth(-1.0f);
            ImGui::InputFloat("视角灵敏度", sensitivity, 0.1f, 1.0f, "%.2f");
            ImGui::TextUnformatted("允许范围：0.5 - 2.0");
        }
        if (volume != nullptr) {
            ImGui::SetNextItemWidth(-1.0f);
            ImGui::InputInt("音量", volume, 1, 10);
            ImGui::TextUnformatted("允许范围：0 - 100");
        }

        ImGui::Spacing();
        ImGui::TextUnformatted("大厅内按 Esc 不会退出");
        if (ImGui::Button("退出", ImVec2(-1.0f, button_h))) action = 5;

        ImGui::PopStyleVar();
    }
    ImGui::End();
    ImGui::PopStyleVar();

    ImGui::Render();
    return action;
}

extern "C" void demo_imgui_prepare_lobby_upload(SDL_GPUCommandBuffer *commands)
{
    ImGui_ImplSDLGPU3_PrepareDrawData(ImGui::GetDrawData(), commands);
}

extern "C" int demo_imgui_prepare_preview(char *path_buf, size_t path_cap)
{
    ImGui_ImplSDLGPU3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();

    int action = 0;
    const ImVec2 display = ImGui::GetIO().DisplaySize;
    const float ui_scale = std::max(1.0f, std::min(display.x, display.y) / 720.0f);

    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f));
    ImGui::SetNextWindowSize(display);
    constexpr ImGuiWindowFlags root_flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(24.0f * ui_scale, 24.0f * ui_scale));
    if (ImGui::Begin("##PreviewRoot", nullptr, root_flags)) {
        ImGui::TextUnformatted("外部模型预览");
        ImGui::TextUnformatted("输入或粘贴 GLB 路径后加载模型");
        ImGui::Spacing();

        if (path_buf != nullptr && path_cap > 0) {
            ImGui::SetNextItemWidth(-1.0f);
            ImGui::InputText("模型路径", path_buf, path_cap);
        }
        ImGui::Spacing();

        const float button_h = 42.0f * ui_scale;
        if (ImGui::Button("加载模型", ImVec2(-1.0f, button_h))) action = 1;
        if (ImGui::Button("返回大厅", ImVec2(-1.0f, button_h))) action = 2;
    }
    ImGui::End();
    ImGui::PopStyleVar();

    ImGui::Render();
    return action;
}