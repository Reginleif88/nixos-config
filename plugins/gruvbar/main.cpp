#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <optional>

#include "bar.hpp"
#include "globals.hpp"

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static bool shouldSkipWindow(PHLWINDOW window) {
    return window->m_class == "windows-11" || window->m_initialClass == "windows-11";
}

static void onNewWindow(PHLWINDOW window) {
    if (window->m_X11DoesntWantBorders)
        return;

    if (shouldSkipWindow(window))
        return;

    if (std::ranges::any_of(window->m_windowDecorations,
            [](const auto& d) { return d->getDisplayName() == "Gruvbar"; }))
        return;

    auto bar = makeUnique<CBar>(window);
    g_pGlobalState->bars.emplace_back(bar);
    bar->m_self = bar;
    HyprlandAPI::addWindowDecoration(PHANDLE, window, std::move(bar));
}

static void onPreConfigReload() {
    g_pGlobalState->buttons.clear();
    for (auto& b : g_pGlobalState->bars)
        if (auto bar = b.lock())
            {
                bar->m_bButtonsDirty = true;
                bar->m_bTextDirty = true;
            }
}

// hl.plugin.gruvbar.add_button({ bg = "rgb(...)", size = 14, glyph = "X",
//                                command = "...", fg = "rgb(...)" })
//
// Replaces the legacy `gruvbar-button` keyword (addConfigKeyword has no V2
// equivalent). Lua-only — under a legacy hyprland.conf this function isn't
// registered.
static int gruvbarAddButton(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);

    auto getStr = [&](const char* key, std::optional<std::string> defaultVal = std::nullopt) -> std::string {
        lua_getfield(L, 1, key);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            if (!defaultVal) {
                luaL_error(L, "gruvbar.add_button: missing required field '%s'", key);
                return {};
            }
            return *defaultVal;
        }
        if (!lua_isstring(L, -1)) {
            lua_pop(L, 1);
            luaL_error(L, "gruvbar.add_button: field '%s' must be a string", key);
            return {};
        }
        std::string out = lua_tostring(L, -1);
        lua_pop(L, 1);
        return out;
    };

    auto getNum = [&](const char* key, std::optional<float> defaultVal = std::nullopt) -> float {
        lua_getfield(L, 1, key);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            if (!defaultVal) {
                luaL_error(L, "gruvbar.add_button: missing required field '%s'", key);
                return 0;
            }
            return *defaultVal;
        }
        if (!lua_isnumber(L, -1)) {
            lua_pop(L, 1);
            luaL_error(L, "gruvbar.add_button: field '%s' must be a number", key);
            return 0;
        }
        float out = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
        return out;
    };

    const std::string bg      = getStr("bg");
    const float       size    = getNum("size", 10.f);
    const std::string glyph   = getStr("glyph");
    const std::string command = getStr("command");
    const std::string fg      = getStr("fg", std::string("rgb(ffffff)"));

    auto bgcolor = Config::ParserUtils::parseColor(bg);
    if (!bgcolor)
        return luaL_error(L, "gruvbar.add_button: invalid bg color: %s", bgcolor.error().c_str());

    auto fgcolor = Config::ParserUtils::parseColor(fg);
    if (!fgcolor)
        return luaL_error(L, "gruvbar.add_button: invalid fg color: %s", fgcolor.error().c_str());

    g_pGlobalState->buttons.push_back(SGruvButton{
        .cmd     = command,
        .bgcol   = CHyprColor((uint64_t)*bgcolor),
        .fgcol   = CHyprColor((uint64_t)*fgcolor),
        .size    = size,
        .icon    = glyph,
        .iconTex = nullptr,
    });

    for (auto& b : g_pGlobalState->bars)
        if (auto bar = b.lock())
            bar->m_bButtonsDirty = true;

    return 0;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[gruvbar] Version mismatch (headers != running hyprland)",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[gruvbar] Version mismatch");
    }

    g_pGlobalState = makeUnique<SGlobalState>();
    auto& cfg      = g_pGlobalState->cfg;

    using namespace Config::Values;

    cfg.barColor = makeShared<CColorValue>(
        "plugin:gruvbar:bar_color", "Bar background color (ARGB hex)",
        Config::ParserUtils::parseColor("rgba(282828ff)").value_or(0));
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.barColor);

    cfg.barHeight = makeShared<CIntValue>(
        "plugin:gruvbar:bar_height", "Bar height in pixels", 28,
        SIntValueOptions{.min = 1, .max = 200});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.barHeight);

    cfg.textColor = makeShared<CColorValue>(
        "plugin:gruvbar:col.text", "Title text color",
        Config::ParserUtils::parseColor("rgba(ebdbb2ff)").value_or(0));
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.textColor);

    cfg.textSize = makeShared<CIntValue>(
        "plugin:gruvbar:bar_text_size", "Title text size", 12,
        SIntValueOptions{.min = 1, .max = 200});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.textSize);

    cfg.textFont = makeShared<CStringValue>(
        "plugin:gruvbar:bar_text_font", "Title font family", std::string{"Sans"});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.textFont);

    cfg.textAlign = makeShared<CStringValue>(
        "plugin:gruvbar:bar_text_align", "Title alignment (left|center|right)", std::string{"center"});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.textAlign);

    cfg.buttonsAlign = makeShared<CStringValue>(
        "plugin:gruvbar:bar_buttons_alignment", "Button alignment (left|right)", std::string{"right"});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.buttonsAlign);

    cfg.padding = makeShared<CIntValue>(
        "plugin:gruvbar:bar_padding", "Bar inner padding", 10,
        SIntValueOptions{.min = 0, .max = 200});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.padding);

    cfg.buttonPadding = makeShared<CIntValue>(
        "plugin:gruvbar:bar_button_padding", "Inter-button padding", 8,
        SIntValueOptions{.min = 0, .max = 200});
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.buttonPadding);

    cfg.precedenceOverBorder = makeShared<CBoolValue>(
        "plugin:gruvbar:bar_precedence_over_border", "Place bar above the window border", true);
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.precedenceOverBorder);

    cfg.titleEnabled = makeShared<CBoolValue>(
        "plugin:gruvbar:bar_title_enabled", "Render the window title in the bar", true);
    HyprlandAPI::addConfigValueV2(PHANDLE, cfg.titleEnabled);

    if (!HyprlandAPI::addLuaFunction(PHANDLE, "gruvbar", "add_button", &gruvbarAddButton))
        HyprlandAPI::addNotification(PHANDLE,
            "[gruvbar] addLuaFunction failed (Hyprland not running with Lua config?)",
            CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    static auto P1 = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });
    static auto P2 = Event::bus()->m_events.config.preReload.listen([&] { onPreConfigReload(); });

    for (auto& w : Desktop::windowState()->windows()) {
        if (w->isHidden() || !w->m_isMapped)
            continue;
        onNewWindow(w);
    }

    return {"gruvbar", "Gruvbox-themed titlebar plugin", "reginleif88", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    for (auto& m : State::monitorState()->monitors())
        m->m_scheduledRecalc = true;
}
