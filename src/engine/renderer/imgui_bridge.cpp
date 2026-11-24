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

extern "C" void demo_imgui_prepare(SDL_GPUCommandBuffer *commands, float ms, bool captured, float *speed, size_t draw_count)
{
    ImGui_ImplSDLGPU3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    ImGui::SetNextWindowPos(ImVec2(12, 12), ImGuiCond_Once);
    if (ImGui::Begin("Scene", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::Text("Frame: %.2f ms  (%.0f FPS)", ms, ms > 0.0f ? 1000.0f / ms : 0.0f);
        ImGui::Text("Opaque draws: %zu", draw_count);
        ImGui::TextUnformatted(captured ? "Tab: release mouse" : "Tab: capture mouse");
        ImGui::TextUnformatted("WASD: fly | Space / Ctrl: up / down");
        ImGui::SetNextItemWidth(170);
        ImGui::SliderFloat("Rotation", speed, 0.0f, 3.0f, "%.2f rad/s");
    }
    ImGui::End();
    ImGui::Render();
    ImGui_ImplSDLGPU3_PrepareDrawData(ImGui::GetDrawData(), commands);
}

extern "C" void demo_imgui_draw(SDL_GPUCommandBuffer *commands, SDL_GPURenderPass *pass)
{
    ImGui_ImplSDLGPU3_RenderDrawData(ImGui::GetDrawData(), commands, pass);
}
