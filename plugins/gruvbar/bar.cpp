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
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
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
    if (titleChanged)
        m_szLastTitle = PWINDOW->m_title;

    // Recreate title texture when needed
    if (cfg.titleEnabled->value() && (titleChanged || m_bWindowSizeChanged || !m_pTextTex))
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

    const int maxWidth = std::clamp(static_cast<int>(bufferSize.x - scaledPadding * 2 - scaledBtnSpace * 2), 0, INT_MAX);
    pango_layout_set_width(layout, maxWidth * PANGO_SCALE);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);

    cairo_set_source_rgba(CAIRO, COLOR.r, COLOR.g, COLOR.b, COLOR.a);

    int layoutWidth, layoutHeight;
    pango_layout_get_size(layout, &layoutWidth, &layoutHeight);

    const bool isCenter = cfg.textAlign->value() != "left";
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
    const auto& cfg = g_pGlobalState->cfg;

    const bool BUTTONSRIGHT = cfg.buttonsAlign->value() != "left";

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
        if (g_pCompositor->vectorToLayerSurface(MOUSECOORDS, &PMONITOR->m_layerSurfaceLayers[layer], &surfaceCoords, &foundLS))
            return true;
    }

    // Check popups of layer surfaces (e.g. Quickshell AudioMixerPopup)
    if (g_pCompositor->vectorToLayerPopupSurface(MOUSECOORDS, PMONITOR, &surfaceCoords, &foundLS))
        return true;

    return false;
}

bool CBar::doButtonPress(Vector2D coords) {
    const auto& cfg = g_pGlobalState->cfg;

    const bool BUTTONSRIGHT = cfg.buttonsAlign->value() != "left";
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

                    // After moving to a special workspace, hide it so the
                    // window truly disappears regardless of which monitor.
                    if (dispatcher == "movetoworkspacesilent" && arg.starts_with("special:")) {
                        auto wsName = arg.substr(8);
                        for (auto& m : State::monitorState()->monitors()) {
                            if (m->m_activeSpecialWorkspace &&
                                m->m_activeSpecialWorkspace->m_name == "special:" + wsName) {
                                g_pKeybindManager->m_dispatchers["togglespecialworkspace"](wsName);
                                break;
                            }
                        }
                    }
                } else {
                    g_pKeybindManager->m_dispatchers["exec"](b.cmd);
                }
            }
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
    auto topWin      = g_pCompositor->vectorToWindowUnified(MOUSECOORDS, Desktop::View::RESERVED_EXTENTS | Desktop::View::ALLOW_FLOATING);
    if (topWin && topWin != PWINDOW)
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
