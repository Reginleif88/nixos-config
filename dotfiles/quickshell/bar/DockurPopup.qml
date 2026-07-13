import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Confirmation popup for the Dockur Windows VM: either drop just the FreeRDP
// session (leaving the VM running) or stop the memory-heavy container itself.
PopupWindow {
    id: popup
    visible: false
    grabFocus: true

    required property var anchorWindow
    required property var anchorItem

    anchor.window: anchorWindow
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    required property color bgColor
    required property color fgColor
    required property color mutedColor
    required property color accentRed
    required property color accentBlue
    required property color accentYellow
    required property string fontFamily
    required property int fontSize

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    property bool shuttingDown: false
    property bool disconnecting: false
    property string actionStatus: ""
    property bool statusIsError: false

    readonly property bool busy: shuttingDown || disconnecting

    // The RDP client is a plain user service, so it stops without pkexec.
    readonly property string disconnectCommand:
        "systemctl --user stop windows-desktop.service"

    readonly property string shutdownCommand:
        disconnectCommand + "; " +
        "exec pkexec systemctl stop docker-windows.service"

    function toggleConfirmation() {
        if (busy)
            return

        if (visible) {
            visible = false
        } else {
            actionStatus = ""
            statusIsError = false
            visible = true
        }
    }

    function startDisconnect() {
        if (busy)
            return

        disconnecting = true
        actionStatus = "Closing RDP session…"
        statusIsError = false
        disconnectProc.running = true
    }

    function startShutdown() {
        if (busy)
            return

        shuttingDown = true
        actionStatus = "Stopping Windows…"
        statusIsError = false
        shutdownProc.running = true
    }

    Process {
        id: disconnectProc
        command: ["bash", "-c", popup.disconnectCommand]

        onExited: function(exitCode, exitStatus) {
            popup.disconnecting = false
            popup.statusIsError = exitCode !== 0
            if (exitCode === 0) {
                popup.actionStatus = "RDP session closed"
                closeTimer.restart()
            } else {
                popup.actionStatus = "Disconnect failed"
            }
        }
    }

    Process {
        id: shutdownProc
        command: ["bash", "-c", popup.shutdownCommand]

        onExited: function(exitCode, exitStatus) {
            popup.shuttingDown = false
            popup.statusIsError = exitCode !== 0
            if (exitCode === 0) {
                popup.actionStatus = "Windows stopped"
                closeTimer.restart()
            } else {
                popup.actionStatus = "Shutdown cancelled or failed"
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 1400
        onTriggered: popup.visible = false
    }

    // Shared look for the three stacked action buttons.
    component ActionButton: Rectangle {
        id: btn

        required property string label
        required property color accent
        property bool enabledAction: true

        signal activated()

        width: parent.width
        height: 30
        radius: 4
        color: btn.enabledAction
            ? Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, 0.22)
            : popup.mutedColor

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.enabledAction ? btn.accent : popup.mutedColor
            font.pixelSize: popup.fontSize - 1
            font.family: popup.fontFamily
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            enabled: btn.enabledAction
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    Rectangle {
        id: popupContent
        width: 292
        height: mainColumn.implicitHeight + 24
        color: popup.bgColor
        border.color: popup.mutedColor
        border.width: 1
        radius: 6

        Column {
            id: mainColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            Text {
                text: "Dockur Windows"
                color: popup.fgColor
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                font.bold: true
            }

            Text {
                width: parent.width
                text: popup.shuttingDown
                    ? "Stopping the Windows container and desktop client…"
                    : popup.disconnecting
                        ? "Closing the FreeRDP session…"
                        : "Close the RDP session, or shut Windows down to free its allocated memory?"
                color: popup.fgColor
                font.pixelSize: popup.fontSize - 1
                font.family: popup.fontFamily
                wrapMode: Text.WordWrap
            }

            ActionButton {
                label: popup.disconnecting ? "Disconnecting…" : "Disconnect RDP"
                accent: popup.accentBlue
                enabledAction: !popup.busy
                onActivated: popup.startDisconnect()
            }

            ActionButton {
                label: popup.shuttingDown ? "Stopping…" : "Shut down VM"
                accent: popup.accentRed
                enabledAction: !popup.busy
                onActivated: popup.startShutdown()
            }

            ActionButton {
                label: "Cancel"
                accent: popup.fgColor
                onActivated: popup.visible = false
            }

            Text {
                visible: popup.actionStatus !== ""
                text: popup.actionStatus
                color: popup.statusIsError ? popup.accentRed : popup.accentYellow
                font.pixelSize: popup.fontSize - 2
                font.family: popup.fontFamily
            }
        }
    }
}
