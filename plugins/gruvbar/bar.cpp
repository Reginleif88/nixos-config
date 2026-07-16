#include "bar.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#define private public
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/config/lua/ConfigManager.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
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
    const auto& cfg = g_pGlobalState->cfg;

    SDecorationPositioningInfo info;
    info.policy         = DECORATION_POSITION_STICKY;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = cfg.precedenceOverBorder->value() ? 10005 : 5000;
    info.reserved       = true;
    info.desiredExtents = {{0, (int)cfg.barHeight->value()}, {0, 0}};
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

    const auto& cfg = g_pGlobalState->cfg;

    const auto scale = PMONITOR->m_scale;
    const auto DECOBOX = assignedBoxGlobal();
    if (DECOBOX.w < 1 || DECOBOX.h < 1)
        return;

    const Vector2D bufferSize = {DECOBOX.w * scale, (double)cfg.barHeight->value() * scale};
    if (bufferSize.x < 1 || bufferSize.y < 1)
        return;

    const bool titleChanged = PWINDOW->m_title != m_szLastTitle;
    if (titleChanged) {
        m_szLastTitle = PWINDOW->m_title;
        m_bTextDirty = true;
    }

    // Rebuild title textures on config changes, resize, and title changes, but
    // avoid a Cairo/Pango upload for every progress-style title update.
    if (cfg.titleEnabled->value()) {
        const auto now = std::chrono::steady_clock::now();
        const bool firstRender = m_tpLastTextRender.time_since_epoch().count() == 0;
        const bool rateLimitExpired = firstRender
            || std::chrono::duration_cast<std::chrono::milliseconds>(now - m_tpLastTextRender).count() >= 50;
        if (m_bTextDirty && (rateLimitExpired || m_bWindowSizeChanged || !m_pTextTex)) {
            renderBarTitle(bufferSize, scale);
            m_tpLastTextRender = now;
            m_bTextDirty = false;
        }
    } else {
        m_pTextTex.reset();
        m_bTextDirty = false;
    }

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
    const auto& cfg = g_pGlobalState->cfg;

    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW)
        return;

    const CHyprColor COLOR = CHyprColor((uint64_t)cfg.textColor->value());

    // Compute button space for text clipping
    const auto btnPad = cfg.buttonPadding->value();
    float buttonSpace = btnPad;
    for (auto& b : g_pGlobalState->buttons)
        buttonSpace += b.size + btnPad;

    const auto scaledSize     = cfg.textSize->value() * scale;
    const auto scaledPadding  = cfg.padding->value() * scale;
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

    const auto fontStr = cfg.textFont->value();
    PangoFontDescription* fontDesc = pango_font_description_from_string(fontStr.c_str());
    pango_font_description_set_size(fontDesc, scaledSize * PANGO_SCALE);
    pango_layout_set_font_description(layout, fontDesc);
    pango_font_description_free(fontDesc);

    const bool buttonsRight = cfg.buttonsAlign->value() != "left";
    const double leftInset = scaledPadding + (buttonsRight ? 0 : scaledBtnSpace);
    const double rightInset = scaledPadding + (buttonsRight ? scaledBtnSpace : 0);
    const int maxWidth = std::clamp(static_cast<int>(bufferSize.x - leftInset - rightInset), 0, INT_MAX);
    pango_layout_set_width(layout, maxWidth * PANGO_SCALE);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);

    cairo_set_source_rgba(CAIRO, COLOR.r, COLOR.g, COLOR.b, COLOR.a);

    int layoutWidth, layoutHeight;
    pango_layout_get_size(layout, &layoutWidth, &layoutHeight);

    const auto textAlign = cfg.textAlign->value();
    const double textWidth = layoutWidth / static_cast<double>(PANGO_SCALE);
    const int xOffset = textAlign == "left"
        ? std::round(leftInset)
        : textAlign == "right"
            ? std::round(bufferSize.x - rightInset - textWidth)
            : std::round((bufferSize.x + leftInset - rightInset - textWidth) / 2.0);
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
    const auto& cfg = g_pGlobalState->cfg;

    const bool BUTTONSRIGHT = cfg.buttonsAlign->value() == "right";

    const auto CAIROSURFACE = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, bufferSize.x, bufferSize.y);
    const auto CAIRO        = cairo_create(CAIROSURFACE);

    cairo_save(CAIRO);
    cairo_set_operator(CAIRO, CAIRO_OPERATOR_CLEAR);
    cairo_paint(CAIRO);
    cairo_restore(CAIRO);

    const auto fontStr = cfg.textFont->value();

    int offset = cfg.padding->value() * scale;
    for (auto& button : g_pGlobalState->buttons) {
        const auto scaledSize = button.size * scale;
        const auto scaledPad  = cfg.buttonPadding->value() * scale;

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

            PangoFontDescription* fontDesc = pango_font_description_from_string(fontStr.c_str());
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

    const auto& cfg = g_pGlobalState->cfg;

    if (cfg.barHeight->value() < 1)
        return;

    const auto DECOBOX  = assignedBoxGlobal();
    const auto ROUNDING = PWINDOW->rounding() + (cfg.precedenceOverBorder->value() ? 0 : PWINDOW->getRealBorderSize());
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
    CHyprColor barColor((uint64_t)cfg.barColor->value());
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
        if (Desktop::viewState()->hitTest().layerSurfaceAt(MOUSECOORDS, &PMONITOR->m_layerSurfaceLayers[layer], &surfaceCoords, &foundLS))
            return true;
    }

    // Check popups of layer surfaces (e.g. Quickshell AudioMixerPopup)
    if (Desktop::viewState()->hitTest().layerPopupSurfaceAt(MOUSECOORDS, PMONITOR, &surfaceCoords, &foundLS))
        return true;

    return false;
}

// Run a button's configured command.
//
// A command of the form `hyprctl dispatch '<lua>'` is, on Hyprland 0.56+,
// nothing but `hl.dispatch(<lua>)` evaluated on the compositor's Lua state
// (see dispatchRequest() in Hyprland's HyprCtl.cpp). Evaluate it in-process
// instead of spawning hyprctl: it is the same code path minus the socket
// round-trip, so the clicked window can't change underneath us in between.
//
// Anything else is a plain shell command and goes to the executor.
static void runButtonCommand(const std::string& cmd) {
    static constexpr std::string_view DISPATCH_PREFIX = "hyprctl dispatch ";

    if (cmd.starts_with(DISPATCH_PREFIX) && Config::mgr()->type() == Config::CONFIG_LUA) {
        std::string lua = cmd.substr(DISPATCH_PREFIX.size());

        // A shell would strip one layer of quoting before hyprctl ever saw the
        // snippet; we bypass the shell, so strip it ourselves.
        if (lua.size() > 1 && (lua.front() == '\'' || lua.front() == '"') && lua.back() == lua.front())
            lua = lua.substr(1, lua.size() - 2);

        const auto LUAMGR = dynamicPointerCast<Config::Lua::CConfigManager>(WP<Config::IConfigManager>(Config::mgr()));
        if (LUAMGR) {
            // eval() returns nullopt on success, a message on failure.
            if (const auto FAILURE = LUAMGR->eval(std::format("return hl.dispatch({})", lua)); FAILURE)
                Log::logger->log(Log::ERR, "[gruvbar] button dispatch failed: {} (lua: {})", *FAILURE, lua);
            return;
        }
    }

    Config::Supplementary::executor()->spawn(cmd);
}

bool CBar::doButtonPress(Vector2D coords) {
    const auto& cfg = g_pGlobalState->cfg;

    const bool BUTTONSRIGHT = cfg.buttonsAlign->value() == "right";
    float offset = cfg.padding->value();
    const auto btnPad = cfg.buttonPadding->value();
    const auto barH   = (double)cfg.barHeight->value();

    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF = Vector2D{assignedBoxGlobal().w, barH};
        Vector2D   btnPos = Vector2D{
            BUTTONSRIGHT ? BARBUF.x - btnPad - b.size - offset : offset,
            (BARBUF.y - b.size) / 2.0
        }.floor();

        if (coords.x >= btnPos.x && coords.x <= btnPos.x + b.size + btnPad &&
            coords.y >= btnPos.y && coords.y <= btnPos.y + b.size) {
            if (!b.cmd.empty())
                runButtonCommand(b.cmd);
            return true;
        }

        offset += btnPad + b.size;
    }

    return false;
}

void CBar::onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !PWINDOW->m_workspace || !PWINDOW->m_workspace->isVisible())
        return;

    const auto barH = (double)g_pGlobalState->cfg.barHeight->value();

    const auto COORDS = cursorRelativeToBar();

    // Release
    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        if (m_bCancelledDown)
            info.cancelled = true;
        m_bCancelledDown = false;

        if (m_bDragging) {
            // End the drag we started in onMouseMove. Calling endDragTarget directly
            // (vs. the "mouse:0movewindow" dispatcher) is symmetric with how we
            // started the drag and avoids the dispatcher's "no drag in progress" guard.
            if (g_layoutManager && g_layoutManager->dragController() && g_layoutManager->dragController()->target())
                g_layoutManager->endDragTarget();
            m_bDragging = false;
        }
        m_bDragPending = false;
        return;
    }

    // Press — check if cursor is within our bar
    if (COORDS.x < 0 || COORDS.y < 0 || COORDS.x > assignedBoxGlobal().w || COORDS.y > barH)
        return;

    // Don't consume clicks if our window is occluded by another window
    auto MOUSECOORDS = g_pInputManager->getMouseCoordsInternal();
    auto topWin      = Desktop::viewState()->hitTest().windowAt(MOUSECOORDS, Desktop::View::RESERVED_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (topWin && topWin != PWINDOW)
        return;

    // Don't intercept clicks on layer surfaces above us (e.g. notification panels)
    if (isLayerSurfaceAbove())
        return;

    // Focus the window
    if (Desktop::focusState()->window() != PWINDOW)
        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);
    if (PWINDOW->m_isFloating)
        Desktop::windowState()->raise(PWINDOW);

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

        const auto PWINDOW = m_pWindow.lock();
        if (!PWINDOW)
            return;

        // Bypass the "mouse:1movewindow" dispatcher: it calls
        // `vectorToWindowUnified` at the cursor to *find* a window, then walks
        // decos via `checkInputOnDecos(INPUT_TYPE_DRAG_START)` and aborts if any
        // returns true. Our deco *is* the cursor target, so that lookup is
        // wasted at best and racy at worst. We already know exactly which
        // window the user is dragging — go straight to the drag controller.
        if (g_layoutManager && PWINDOW->layoutTarget()) {
            g_layoutManager->beginDragTarget(PWINDOW->layoutTarget(), MBIND_MOVE);
            m_bDragging = true;
        }
    }
}

bool CBar::onInputOnDeco(const eInputType type, const Vector2D& coords, std::any data) {
    // Only suppress raw button click-through to the underlying surface.
    // DRAG_START / DRAG_END must NOT be consumed: Hyprland calls those on every
    // deco when starting/finishing a window drag (KeybindManager::changeMouseBindMode,
    // DragController::endDrag) and treats `true` as "this deco absorbed the drag,
    // abort it" — which would block our own mouse:1movewindow dispatch and any
    // drop-into-tile logic when releasing on another window's bar.
    if (type != INPUT_TYPE_BUTTON)
        return false;

    const auto barH = (double)g_pGlobalState->cfg.barHeight->value();

    // Bounds check — coords are relative to the decoration's assigned box
    if (coords.x < 0 || coords.y < 0 || coords.x > assignedBoxGlobal().w || coords.y > barH)
        return false;

    // Don't intercept clicks on layer surfaces above us (e.g. notification panels)
    if (isLayerSurfaceAbove())
        return false;

    return true;
}
