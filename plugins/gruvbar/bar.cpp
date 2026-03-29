#include "bar.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#define private public
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/protocols/wlr-layer-shell-unstable-v1.hpp>
#include <pango/pangocairo.h>

// ─── Construction / Destruction ──────────────────────────────────────────────

CBar::CBar(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow) {
    m_pWindow = pWindow;

    const auto PMONITOR = pWindow->m_monitor.lock();
    PMONITOR->m_scheduledRecalc = true;

    // Mouse event listeners
    m_pMouseButtonCallback = Event::bus()->m_events.input.mouse.button.listen(
        [&](IPointer::SButtonEvent e, Event::SCallbackInfo& info) { onMouseButton(info, e); });
    m_pMouseMoveCallback = Event::bus()->m_events.input.mouse.move.listen(
        [&](Vector2D c, Event::SCallbackInfo& info) { onMouseMove(c); });

    // Textures created lazily in renderBarTitle/renderBarButtons
}

CBar::~CBar() {
    std::erase(g_pGlobalState->bars, m_self);
}

// ─── Positioning ─────────────────────────────────────────────────────────────

SDecorationPositioningInfo CBar::getPositioningInfo() {
    static auto* const PHEIGHT     = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_height")->getDataStaticPtr();
    static auto* const PPRECEDENCE = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_precedence_over_border")->getDataStaticPtr();

    SDecorationPositioningInfo info;
    info.policy         = DECORATION_POSITION_STICKY;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = **PPRECEDENCE ? 10005 : 5000;
    info.reserved       = true;
    info.desiredExtents = {{0, **PHEIGHT}, {0, 0}};
    return info;
}

void CBar::onPositioningReply(const SDecorationPositioningReply& reply) {
    if (reply.assignedGeometry.size() != m_bAssignedBox.size())
        m_bWindowSizeChanged = true;
    m_bAssignedBox = reply.assignedGeometry;
}

// ─── Identity ────────────────────────────────────────────────────────────────

eDecorationType CBar::getDecorationType() {
    return DECORATION_CUSTOM;
}

eDecorationLayer CBar::getDecorationLayer() {
    return DECORATION_LAYER_UNDER;
}

uint64_t CBar::getDecorationFlags() {
    return DECORATION_ALLOWS_MOUSE_INPUT;
}

std::string CBar::getDisplayName() {
    return "Gruvbar";
}

// ─── Geometry helpers ────────────────────────────────────────────────────────

CBox CBar::assignedBoxGlobal() {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return {};

    CBox box = m_bAssignedBox;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, m_pWindow));
    return box;
}

// ─── Window updates ──────────────────────────────────────────────────────────

void CBar::updateWindow(PHLWINDOW pWindow) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return;

    const auto PMONITOR = PWINDOW->m_monitor.lock();
    if (!PMONITOR)
        return;

    static auto* const PHEIGHT      = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_height")->getDataStaticPtr();
    static auto* const PENABLETITLE = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_title_enabled")->getDataStaticPtr();

    const auto scale = PMONITOR->m_scale;
    const auto DECOBOX = assignedBoxGlobal();
    if (DECOBOX.w < 1 || DECOBOX.h < 1)
        return;

    const Vector2D bufferSize = {DECOBOX.w * scale, (double)**PHEIGHT * scale};
    if (bufferSize.x < 1 || bufferSize.y < 1)
        return;

    const bool titleChanged = PWINDOW->m_title != m_szLastTitle;
    if (titleChanged)
        m_szLastTitle = PWINDOW->m_title;

    // Recreate title texture when needed
    if (**PENABLETITLE && (titleChanged || m_bWindowSizeChanged || !m_pTextTex))
        renderBarTitle(bufferSize, scale);

    // Recreate button texture when needed
    if (m_bButtonsDirty || m_bWindowSizeChanged || !m_pButtonsTex)
        renderBarButtons(bufferSize, scale);

    m_bButtonsDirty = false;

    damageEntire();
}

void CBar::damageEntire() {
    // Hyprland auto-damages windows during rendering; explicit damage
    // via g_pHyprRenderer->damageBox/damageWindow isn't exported to plugins.
}

// ─── Text rendering (Cairo/Pango → texture) ─────────────────────────────────

void CBar::renderBarTitle(const Vector2D& bufferSize, float scale) {
    static auto* const PCOLOR    = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:col.text")->getDataStaticPtr();
    static auto* const PSIZE     = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_text_size")->getDataStaticPtr();
    static auto* const PFONT     = (Hyprlang::STRING const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_text_font")->getDataStaticPtr();
    static auto* const PALIGN    = (Hyprlang::STRING const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_text_align")->getDataStaticPtr();
    static auto* const PPADDING  = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_padding")->getDataStaticPtr();
    static auto* const PBTNPAD   = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_button_padding")->getDataStaticPtr();

    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return;

    const CHyprColor COLOR = CHyprColor(**PCOLOR);

    // Compute button space for text clipping
    float buttonSpace = **PBTNPAD;
    for (auto& b : g_pGlobalState->buttons)
        buttonSpace += b.size + **PBTNPAD;

    const auto scaledSize    = **PSIZE * scale;
    const auto scaledPadding = **PPADDING * scale;
    const auto scaledBtnSpace = buttonSpace * scale;

    // Cairo surface for text rendering
    const auto CAIROSURFACE = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, bufferSize.x, bufferSize.y);
    const auto CAIRO        = cairo_create(CAIROSURFACE);

    cairo_save(CAIRO);
    cairo_set_operator(CAIRO, CAIRO_OPERATOR_CLEAR);
    cairo_paint(CAIRO);
    cairo_restore(CAIRO);

    // Pango layout
    PangoLayout* layout = pango_cairo_create_layout(CAIRO);
    pango_layout_set_text(layout, m_szLastTitle.c_str(), -1);

    PangoFontDescription* fontDesc = pango_font_description_from_string(*PFONT);
    pango_font_description_set_size(fontDesc, scaledSize * PANGO_SCALE);
    pango_layout_set_font_description(layout, fontDesc);
    pango_font_description_free(fontDesc);

    const int maxWidth = std::clamp(static_cast<int>(bufferSize.x - scaledPadding * 2 - scaledBtnSpace * 2), 0, INT_MAX);
    pango_layout_set_width(layout, maxWidth * PANGO_SCALE);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);

    cairo_set_source_rgba(CAIRO, COLOR.r, COLOR.g, COLOR.b, COLOR.a);

    int layoutWidth, layoutHeight;
    pango_layout_get_size(layout, &layoutWidth, &layoutHeight);

    const bool isCenter = std::string{*PALIGN} != "left";
    const int  xOffset  = isCenter
        ? std::round(bufferSize.x / 2.0 - layoutWidth / PANGO_SCALE / 2.0)
        : std::round(scaledPadding + scaledBtnSpace);
    const int  yOffset  = std::round(bufferSize.y / 2.0 - layoutHeight / PANGO_SCALE / 2.0);

    cairo_move_to(CAIRO, xOffset, yOffset);
    pango_cairo_show_layout(CAIRO, layout);
    g_object_unref(layout);
    cairo_surface_flush(CAIROSURFACE);

    // Upload to GL texture via renderer (plugin can't call CGLTexture constructors directly)
    cairo_surface_flush(CAIROSURFACE);
    m_pTextTex = g_pHyprRenderer->createTexture(CAIROSURFACE);

    cairo_destroy(CAIRO);
    cairo_surface_destroy(CAIROSURFACE);
}

// ─── Button rendering (Cairo circles → texture) ─────────────────────────────

void CBar::renderBarButtons(const Vector2D& bufferSize, float scale) {
    static auto* const PBTNPAD = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_button_padding")->getDataStaticPtr();
    static auto* const PPADDING = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_padding")->getDataStaticPtr();
    static auto* const PALIGN  = (Hyprlang::STRING const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_buttons_alignment")->getDataStaticPtr();

    const bool BUTTONSRIGHT = std::string{*PALIGN} != "left";

    const auto CAIROSURFACE = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, bufferSize.x, bufferSize.y);
    const auto CAIRO        = cairo_create(CAIROSURFACE);

    cairo_save(CAIRO);
    cairo_set_operator(CAIRO, CAIRO_OPERATOR_CLEAR);
    cairo_paint(CAIRO);
    cairo_restore(CAIRO);

    static auto* const PFONT = (Hyprlang::STRING const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_text_font")->getDataStaticPtr();

    int offset = **PPADDING * scale;
    for (auto& button : g_pGlobalState->buttons) {
        const auto scaledSize = button.size * scale;
        const auto scaledPad  = **PBTNPAD * scale;

        const auto pos = Vector2D{
            BUTTONSRIGHT ? bufferSize.x - offset - scaledSize / 2.0 : offset + scaledSize / 2.0,
            bufferSize.y / 2.0
        };

        // Draw circle background
        cairo_set_source_rgba(CAIRO, button.bgcol.r, button.bgcol.g, button.bgcol.b, button.bgcol.a);
        cairo_arc(CAIRO, pos.x, pos.y, scaledSize / 2.0, 0, 2 * M_PI);
        cairo_fill(CAIRO);

        // Draw icon glyph centered in the circle
        if (!button.icon.empty()) {
            PangoLayout* layout = pango_cairo_create_layout(CAIRO);
            pango_layout_set_text(layout, button.icon.c_str(), -1);

            PangoFontDescription* fontDesc = pango_font_description_from_string(*PFONT);
            pango_font_description_set_size(fontDesc, scaledSize * 0.6 * PANGO_SCALE);
            pango_layout_set_font_description(layout, fontDesc);
            pango_font_description_free(fontDesc);

            int lw, lh;
            pango_layout_get_size(layout, &lw, &lh);
            const double iconX = pos.x - (lw / PANGO_SCALE) / 2.0;
            const double iconY = pos.y - (lh / PANGO_SCALE) / 2.0;

            cairo_set_source_rgba(CAIRO, button.fgcol.r, button.fgcol.g, button.fgcol.b, button.fgcol.a);
            cairo_move_to(CAIRO, iconX, iconY);
            pango_cairo_show_layout(CAIRO, layout);
            g_object_unref(layout);
        }

        offset += scaledPad + scaledSize;
    }

    cairo_surface_flush(CAIROSURFACE);
    m_pButtonsTex = g_pHyprRenderer->createTexture(CAIROSURFACE);

    cairo_destroy(CAIRO);
    cairo_surface_destroy(CAIROSURFACE);
}

// ─── Draw (add pass elements) ────────────────────────────────────────────────

void CBar::draw(PHLMONITOR pMonitor, float const& a) {
    if (!validMapped(m_pWindow))
        return;

    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return;

    static auto* const PCOLOR       = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_color")->getDataStaticPtr();
    static auto* const PHEIGHT      = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_height")->getDataStaticPtr();
    static auto* const PPRECEDENCE  = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_precedence_over_border")->getDataStaticPtr();

    if (**PHEIGHT < 1)
        return;

    const auto DECOBOX  = assignedBoxGlobal();
    const auto ROUNDING = PWINDOW->rounding() + (**PPRECEDENCE ? 0 : PWINDOW->getRealBorderSize());
    const auto scaledRounding = ROUNDING > 0 ? (int)(ROUNDING * pMonitor->m_scale) : 0;

    // Bar background box (monitor-local, scaled)
    CBox barBox = {
        DECOBOX.x - pMonitor->m_position.x,
        DECOBOX.y - pMonitor->m_position.y,
        DECOBOX.w,
        DECOBOX.h
    };
    barBox.scale(pMonitor->m_scale).round();

    if (barBox.w < 1 || barBox.h < 1)
        return;

    // 1) Bar background rectangle
    CHyprColor barColor(**PCOLOR);
    barColor.a *= a;

    CRectPassElement::SRectData rectData;
    rectData.box           = barBox;
    rectData.color         = barColor;
    rectData.round         = scaledRounding;
    rectData.roundingPower = PWINDOW->roundingPower();
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectData));

    // 2) Title text texture
    if (m_pTextTex) {
        CTexPassElement::SRenderData texData;
        texData.tex  = m_pTextTex;
        texData.box  = barBox;
        texData.a    = a;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CTexPassElement>(texData));
    }

    // 3) Button texture
    if (m_pButtonsTex) {
        CTexPassElement::SRenderData texData;
        texData.tex  = m_pButtonsTex;
        texData.box  = barBox;
        texData.a    = a;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CTexPassElement>(texData));
    }

    m_bWindowSizeChanged = false;
}

// ─── Input handling ──────────────────────────────────────────────────────────

Vector2D CBar::cursorRelativeToBar() {
    return g_pInputManager->getMouseCoordsInternal() - assignedBoxGlobal().pos();
}

bool CBar::isLayerSurfaceAbove() {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return false;

    const auto PMONITOR = PWINDOW->m_monitor.lock();
    if (!PMONITOR)
        return false;

    const auto MOUSECOORDS = g_pInputManager->getMouseCoordsInternal();

    // Check overlay and top layers — these sit above window decorations
    Vector2D surfaceCoords;
    PHLLS    foundLS;
    for (auto layer : {ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, ZWLR_LAYER_SHELL_V1_LAYER_TOP}) {
        if (g_pCompositor->vectorToLayerSurface(MOUSECOORDS, &PMONITOR->m_layerSurfaceLayers[layer], &surfaceCoords, &foundLS))
            return true;
    }

    return false;
}

bool CBar::doButtonPress(Vector2D coords) {
    static auto* const PBTNPAD  = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_button_padding")->getDataStaticPtr();
    static auto* const PPADDING = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_padding")->getDataStaticPtr();
    static auto* const PHEIGHT  = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_height")->getDataStaticPtr();
    static auto* const PALIGN   = (Hyprlang::STRING const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_buttons_alignment")->getDataStaticPtr();

    const bool BUTTONSRIGHT = std::string{*PALIGN} != "left";
    float offset = **PPADDING;

    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF = Vector2D{assignedBoxGlobal().w, (double)**PHEIGHT};
        Vector2D   btnPos = Vector2D{
            BUTTONSRIGHT ? BARBUF.x - **PBTNPAD - b.size - offset : offset,
            (BARBUF.y - b.size) / 2.0
        }.floor();

        if (coords.x >= btnPos.x && coords.x <= btnPos.x + b.size + **PBTNPAD &&
            coords.y >= btnPos.y && coords.y <= btnPos.y + b.size) {
            if (!b.cmd.empty()) {
                // If the command is "hyprctl dispatch X Y", call the dispatcher
                // directly in-process to avoid subprocess race conditions
                if (b.cmd.starts_with("hyprctl dispatch ")) {
                    auto rest = b.cmd.substr(17); // skip "hyprctl dispatch "
                    auto spacePos = rest.find(' ');
                    auto dispatcher = spacePos != std::string::npos ? rest.substr(0, spacePos) : rest;
                    auto arg = spacePos != std::string::npos ? rest.substr(spacePos + 1) : std::string{};
                    auto it = g_pKeybindManager->m_dispatchers.find(dispatcher);
                    if (it != g_pKeybindManager->m_dispatchers.end())
                        it->second(arg);
                    else
                        g_pKeybindManager->m_dispatchers["exec"](b.cmd);
                } else {
                    g_pKeybindManager->m_dispatchers["exec"](b.cmd);
                }
            }
            return true;
        }

        offset += **PBTNPAD + b.size;
    }

    return false;
}

void CBar::onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !PWINDOW->m_workspace || !PWINDOW->m_workspace->isVisible())
        return;

    static auto* const PHEIGHT = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:gruvbar:bar_height")->getDataStaticPtr();

    const auto COORDS = cursorRelativeToBar();

    // Release
    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        if (m_bCancelledDown)
            info.cancelled = true;
        m_bCancelledDown = false;

        if (m_bDragging) {
            g_pKeybindManager->m_dispatchers["mouse"]("0movewindow");
            m_bDragging = false;
        }
        m_bDragPending = false;
        return;
    }

    // Press — check if cursor is within our bar
    if (COORDS.x < 0 || COORDS.y < 0 || COORDS.x > assignedBoxGlobal().w || COORDS.y > **PHEIGHT)
        return;

    // Don't intercept clicks on layer surfaces above us (e.g. notification panels)
    if (isLayerSurfaceAbove())
        return;

    // Focus the window
    if (Desktop::focusState()->window() != PWINDOW)
        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);
    if (PWINDOW->m_isFloating)
        g_pCompositor->changeWindowZOrder(PWINDOW, true);

    info.cancelled   = true;
    m_bCancelledDown = true;

    // Check button press
    if (doButtonPress(COORDS))
        return;

    // Not a button — start drag
    m_bDragPending = true;
}

void CBar::onMouseMove(Vector2D coords) {
    if (m_bDragPending && isLayerSurfaceAbove()) {
        m_bDragPending = false;
        return;
    }

    if (m_bDragPending && !m_bDragging) {
        m_bDragPending = false;
        m_bDragging    = true;
        g_pKeybindManager->m_dispatchers["mouse"]("1movewindow");
    }
}

bool CBar::onInputOnDeco(const eInputType type, const Vector2D& coords, std::any data) {
    return false; // Input handled via event bus callbacks
}
