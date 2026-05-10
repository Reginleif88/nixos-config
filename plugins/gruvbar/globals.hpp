#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <vector>
#include <string>

class CBar;

struct SGruvButton {
    std::string          cmd;
    CHyprColor           bgcol;
    CHyprColor           fgcol;
    float                size;
    std::string          icon;
    SP<Render::ITexture> iconTex;
};

// V2 plugin config (Hyprland 0.55+). The plugin holds shared pointers to its
// IValue instances; the config manager populates them from user Lua/.conf
// writes. Read live via cfg.<name>->value().
struct SCfg {
    SP<Config::Values::CColorValue>  barColor;
    SP<Config::Values::CIntValue>    barHeight;
    SP<Config::Values::CColorValue>  textColor;       // "col.text"
    SP<Config::Values::CIntValue>    textSize;
    SP<Config::Values::CStringValue> textFont;
    SP<Config::Values::CStringValue> textAlign;
    SP<Config::Values::CStringValue> buttonsAlign;
    SP<Config::Values::CIntValue>    padding;
    SP<Config::Values::CIntValue>    buttonPadding;
    SP<Config::Values::CBoolValue>   precedenceOverBorder;
    SP<Config::Values::CBoolValue>   titleEnabled;
};

struct SGlobalState {
    SCfg                     cfg;
    std::vector<SGruvButton> buttons;
    std::vector<WP<CBar>>    bars;
};

inline HANDLE           PHANDLE = nullptr;
inline UP<SGlobalState> g_pGlobalState;
