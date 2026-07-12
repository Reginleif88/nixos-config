import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

Item {
    id: sidebarRoot
    width: 0; height: 0

    required property color bgColor
    required property color borderColor
    required property string targetScreen
    required property bool targetWorkspaceActive
    property int panelWidth: 460
    property int triggerWidth: 4
    property url url: "https://gemini.google.com"

    property bool open: false
    readonly property var targetScreenObject: {
        var screens = Quickshell.screens.values
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === sidebarRoot.targetScreen)
                return screens[i]
        }
        return null
    }
    readonly property bool available: targetScreenObject !== null && targetWorkspaceActive

    Timer {
        id: hideTimer
        interval: 300
        onTriggered: sidebarRoot.open = false
    }

    onAvailableChanged: {
        if (!sidebarRoot.available) {
            sidebarRoot.open = false
            panelLoader.active = false
        }
    }

    // Trigger zone: one thin strip on the screen owning workspace 1.
    PanelWindow {
        screen: sidebarRoot.targetScreenObject
        visible: sidebarRoot.available
        anchors { top: true; bottom: true; left: true }
        exclusiveZone: 0
        implicitWidth: sidebarRoot.triggerWidth
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                hideTimer.stop()
                sidebarRoot.open = true
            }
            onExited: hideTimer.restart()
        }
    }

    // The WebEngine profile and view do not exist until the sidebar is opened.
    // Closing the hover panel destroys them again after the short hide delay.
    LazyLoader {
        id: panelLoader
        active: sidebarRoot.open && sidebarRoot.available

        PanelWindow {
            id: panel
            screen: sidebarRoot.targetScreenObject
            visible: true
            anchors { top: true; bottom: true; left: true }
            exclusiveZone: 0
            implicitWidth: sidebarRoot.panelWidth
            color: sidebarRoot.bgColor
            focusable: true

            property var geminiProfile: null

            WebEngineProfilePrototype {
                id: geminiProfileProto
                storageName: "gemini-sidebar"
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
            }

            Component.onCompleted: panel.geminiProfile = geminiProfileProto.instance()

            Rectangle {
                anchors.fill: parent
                color: sidebarRoot.bgColor

                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: sidebarRoot.borderColor
                }

                WebEngineView {
                    id: webView
                    anchors.fill: parent
                    anchors.rightMargin: 1
                    url: sidebarRoot.url
                    backgroundColor: sidebarRoot.bgColor
                    profile: panel.geminiProfile
                }

                Shortcut {
                    sequence: "F5"
                    enabled: sidebarRoot.open
                    onActivated: webView.reload()
                }
            }

            // Hover tracker on top of WebEngineView so its subsurface
            // doesn't steal onExited from us.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onExited: hideTimer.restart()
                onEntered: hideTimer.stop()
            }
        }
    }
}
