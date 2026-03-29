#pragma once

#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include "globals.hpp"

class CBar : public IHyprWindowDecoration {
  public:
    CBar(PHLWINDOW pWindow);
    virtual ~CBar();

    virtual SDecorationPositioningInfo getPositioningInfo() override;
    virtual void                       onPositioningReply(const SDecorationPositioningReply& reply) override;
    virtual void                       draw(PHLMONITOR, float const& a) override;
    virtual eDecorationType            getDecorationType() override;
    virtual void                       updateWindow(PHLWINDOW) override;
    virtual void                       damageEntire() override;
    virtual bool                       onInputOnDeco(const eInputType, const Vector2D&, std::any = {}) override;
    virtual eDecorationLayer           getDecorationLayer() override;
    virtual uint64_t                   getDecorationFlags() override;
    virtual std::string                getDisplayName() override;

    PHLWINDOWREF getOwner() { return m_pWindow; }
    WP<CBar>     m_self;
    bool         m_bButtonsDirty = true;

  private:
    PHLWINDOWREF   m_pWindow;
    CBox           m_bAssignedBox;
    bool           m_bWindowSizeChanged = true;

    // Cached textures
    SP<ITexture> m_pTextTex;
    SP<ITexture> m_pButtonsTex;
    std::string    m_szLastTitle;

    // Input state
    bool m_bDragging    = false;
    bool m_bDragPending = false;
    bool m_bCancelledDown = false;

    // Event listeners
    CHyprSignalListener m_pMouseButtonCallback;
    CHyprSignalListener m_pMouseMoveCallback;

    // Input handlers
    void onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e);
    void onMouseMove(Vector2D coords);
    bool doButtonPress(Vector2D coords);
    Vector2D cursorRelativeToBar();

    // Layer surface check
    bool isLayerSurfaceAbove();

    // Internal rendering helpers
    void renderBarTitle(const Vector2D& bufferSize, float scale);
    void renderBarButtons(const Vector2D& bufferSize, float scale);

    // Geometry helpers
    CBox assignedBoxGlobal();
};
