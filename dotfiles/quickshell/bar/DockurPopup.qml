import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Confirmation popup for stopping the memory-heavy Dockur Windows VM.
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
    required property color accentYellow
    required property string fontFamily
    required property int fontSize

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    property bool shuttingDown: false
    property string actionStatus: ""

    readonly property string shutdownCommand:
        "systemctl --user stop windows-desktop.service; " +
        "exec pkexec systemctl stop docker-windows.service"

    function toggleConfirmation() {
        if (shutdownProc.running)
            return

        if (visible) {
            visible = false
        } else {
            actionStatus = ""
            visible = true
        }
    }

    function startShutdown() {
        if (shutdownProc.running)
            return

        shuttingDown = true
        actionStatus = "Stopping Windows…"
        shutdownProc.running = true
    }

    Process {
        id: shutdownProc
        command: ["bash", "-c", popup.shutdownCommand]

        onExited: function(exitCode, exitStatus) {
            popup.shuttingDown = false
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
                    : "Shut down Windows to free its allocated memory?"
                color: popup.fgColor
                font.pixelSize: popup.fontSize - 1
                font.family: popup.fontFamily
                wrapMode: Text.WordWrap
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: 30
                    radius: 4
                    color: popup.mutedColor

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: popup.fgColor
                        font.pixelSize: popup.fontSize - 1
                        font.family: popup.fontFamily
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.visible = false
                    }
                }

                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: 30
                    radius: 4
                    color: popup.shuttingDown
                        ? popup.mutedColor
                        : Qt.rgba(popup.accentRed.r, popup.accentRed.g,
                                  popup.accentRed.b, 0.22)

                    Text {
                        anchors.centerIn: parent
                        text: popup.shuttingDown ? "Stopping…" : "Shut down"
                        color: popup.shuttingDown ? popup.mutedColor : popup.accentRed
                        font.pixelSize: popup.fontSize - 1
                        font.family: popup.fontFamily
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !popup.shuttingDown
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.startShutdown()
                    }
                }
            }

            Text {
                visible: popup.actionStatus !== ""
                text: popup.actionStatus
                color: popup.actionStatus === "Windows stopped"
                    ? popup.accentYellow : popup.accentRed
                font.pixelSize: popup.fontSize - 2
                font.family: popup.fontFamily
            }
        }
    }
}
