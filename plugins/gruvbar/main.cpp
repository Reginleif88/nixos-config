#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprutils/string/VarList2.hpp>

#include "bar.hpp"
#include "globals.hpp"

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static void onNewWindow(PHLWINDOW window) {
    if (window->m_X11DoesntWantBorders)
        return;

    // Don't add twice
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
}

Hyprlang::CParseResult onNewButton(const char* K, const char* V) {
    std::string            v = V;
    Hyprutils::String::CVarList2 vars(std::move(v));

    Hyprlang::CParseResult result;

    // gruvbar-button = bgcolor, size, icon, action, fgcolor
    if (std::string(vars[0]).empty() || std::string(vars[1]).empty()) {
        result.setError("bgcolor and size cannot be empty");
        return result;
    }

    float size = 10;
    try {
        size = std::stof(std::string(vars[1]));
    } catch (...) {
        result.setError("failed to parse button size");
        return result;
    }

    auto bgcolor = configStringToInt(std::string(vars[0]));
    if (!bgcolor) {
        result.setError("invalid bgcolor");
        return result;
    }

    auto fgcolor = configStringToInt("rgb(ffffff)");
    if (vars.size() >= 5) {
        fgcolor = configStringToInt(std::string(vars[4]));
        if (!fgcolor) {
            result.setError("invalid fgcolor");
            return result;
        }
    }

    g_pGlobalState->buttons.push_back(SGruvButton{
        std::string(vars[3]),   // cmd
        CHyprColor(*bgcolor),   // bgcol
        CHyprColor(*fgcolor),   // fgcol
        size,                   // size
        std::string(vars[2]),   // icon
        nullptr                 // iconTex
    });

    for (auto& b : g_pGlobalState->bars) {
        if (auto bar = b.lock())
            bar->m_bButtonsDirty = true;
    }

    return result;
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

    // Register config values
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_color",                   Hyprlang::INT{*configStringToInt("rgba(282828ff)")});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_height",                  Hyprlang::INT{28});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:col.text",                    Hyprlang::INT{*configStringToInt("rgba(ebdbb2ff)")});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_text_size",               Hyprlang::INT{12});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_text_font",               Hyprlang::STRING{"Sans"});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_text_align",              Hyprlang::STRING{"center"});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_buttons_alignment",       Hyprlang::STRING{"right"});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_padding",                 Hyprlang::INT{10});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_button_padding",          Hyprlang::INT{8});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_precedence_over_border",  Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(PHANDLE, "plugin:gruvbar:bar_title_enabled",           Hyprlang::INT{1});

    // Register button keyword
    HyprlandAPI::addConfigKeyword(PHANDLE, "plugin:gruvbar:gruvbar-button", onNewButton, Hyprlang::SHandlerOptions{});

    // Event listeners
    static auto P1 = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });
    static auto P2 = Event::bus()->m_events.config.preReload.listen([&] { onPreConfigReload(); });

    // Add decoration to existing windows
    for (auto& w : g_pCompositor->m_windows) {
        if (w->isHidden() || !w->m_isMapped)
            continue;
        onNewWindow(w);
    }

    HyprlandAPI::reloadConfig();

    return {"gruvbar", "Gruvbox-themed titlebar plugin", "reginleif88", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    for (auto& m : g_pCompositor->m_monitors)
        m->m_scheduledRecalc = true;
}
