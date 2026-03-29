#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <vector>
#include <string>

class CBar;

struct SGruvButton {
    std::string cmd;
    CHyprColor  bgcol;
    CHyprColor  fgcol;
    float       size;
    std::string icon;
    SP<ITexture> iconTex;
};

struct SGlobalState {
    std::vector<SGruvButton>  buttons;
    std::vector<WP<CBar>>    bars;
};

inline HANDLE            PHANDLE = nullptr;
inline UP<SGlobalState>  g_pGlobalState;
