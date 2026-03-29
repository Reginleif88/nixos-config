import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// ProtonVPN status popup for Quickshell bar
// Shows connection status, server details, and disconnect control

PopupWindow {
    id: popup
    visible: false
    grabFocus: true

    // These must be set by the parent (shell.qml)
    required property var anchorWindow
    required property var anchorItem

    anchor.window: anchorWindow
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    // Theme colors (passed from root)
    required property color bgColor
    required property color fgColor
    required property color mutedColor
    required property color accentGreen
    required property color accentYellow
    required property color accentRed
    required property color accentTeal
    required property string fontFamily
    required property int fontSize

    // Expose state to parent for bar icon/text coloring
    property bool vpnConnected: false
    property string vpnServer: ""
    property string vpnCountry: ""

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    // ─────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────
    property var connectedInfo: null
    property var profiles: []
    property string _statusBuf: ""
    property bool actionBusy: false

    // Optimistic disconnect state
    property bool disconnectPending: false

    readonly property string scriptsDir:
        Qt.resolvedUrl("../scripts/").toString().replace("file://", "")

    // ─────────────────────────────────────────────────────
    // Status polling
    // ─────────────────────────────────────────────────────
    Process {
        id: vpnStatusProc
        command: ["bash", popup.scriptsDir + "vpn_panel.sh", "--status"]
        stdout: SplitParser {
            onRead: function(line) { popup._statusBuf += line }
        }
        onExited: function() {
            try {
                var d = JSON.parse(popup._statusBuf)
                if (!popup.disconnectPending) {
                    popup.connectedInfo = d.connected || null
                    popup.vpnConnected = d.connected !== null && d.connected !== undefined
                    popup.vpnServer = popup.vpnConnected ? (d.connected.name || "") : ""
                    popup.vpnCountry = popup.vpnConnected ? (d.connected.country || "") : ""
                }
                popup.profiles = d.profiles || []
            } catch(e) {}
            popup._statusBuf = ""
        }
    }

    // Background poll (always running) — keeps pill icon current
    Timer {
        id: bgPollTimer
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!popup.visible)
                vpnStatusProc.running = true
        }
    }

    // Foreground poll (when popup is open) — faster updates
    Timer {
        id: fgPollTimer
        interval: 3000
        running: popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: vpnStatusProc.running = true
    }

    // ─────────────────────────────────────────────────────
    // Action processes
    // ─────────────────────────────────────────────────────
    Process {
        id: vpnConnectProc
        property string targetProfile: ""
        command: ["bash", popup.scriptsDir + "vpn_panel.sh", "--connect", targetProfile]
        stdout: SplitParser {
            onRead: function(line) { popup._statusBuf += line }
        }
        onExited: function() {
            popup.actionBusy = false
            try {
                var d = JSON.parse(popup._statusBuf)
                popup.connectedInfo = d.connected || null
                popup.vpnConnected = d.connected !== null && d.connected !== undefined
                popup.vpnServer = popup.vpnConnected ? (d.connected.name || "") : ""
                popup.vpnCountry = popup.vpnConnected ? (d.connected.country || "") : ""
                popup.profiles = d.profiles || []
            } catch(e) {}
            popup._statusBuf = ""
        }
    }

    Process {
        id: vpnDisconnectProc
        command: ["bash", popup.scriptsDir + "vpn_panel.sh", "--disconnect"]
        stdout: SplitParser {
            onRead: function(line) { popup._statusBuf += line }
        }
        onExited: function() {
            popup.actionBusy = false
            popup.disconnectPending = false
            try {
                var d = JSON.parse(popup._statusBuf)
                popup.connectedInfo = d.connected || null
                popup.vpnConnected = d.connected !== null && d.connected !== undefined
                popup.vpnServer = popup.vpnConnected ? (d.connected.name || "") : ""
                popup.vpnCountry = popup.vpnConnected ? (d.connected.country || "") : ""
                popup.profiles = d.profiles || []
            } catch(e) {}
            popup._statusBuf = ""
        }
    }

    // Disconnect optimistic UI timeout
    Timer {
        id: disconnectPendingReset
        interval: 10000
        onTriggered: { popup.disconnectPending = false }
    }

    // Action busy timeout (safety valve)
    Timer {
        id: busyTimeout
        interval: 15000
        running: popup.actionBusy
        onTriggered: { popup.actionBusy = false }
    }

    // Launch ProtonVPN GUI
    Process {
        id: vpnGuiProc
        command: ["protonvpn-app"]
    }

    // ─────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────
    Rectangle {
        id: popupContent
        width: 280
        height: mainColumn.height + 24
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

            // ── Header ─────────────────────────────────────
            Row {
                width: parent.width
                spacing: 8

                Image {
                    source: "proton-vpn-logo.svg"
                    sourceSize: Qt.size(popup.fontSize + 4, popup.fontSize + 4)
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: popup.vpnConnected ? 1.0 : 0.5
                }

                Text {
                    text: "ProtonVPN"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.fgColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { width: 1; height: 1; Layout.fillWidth: true }

                // Disconnect button (only visible when connected)
                Rectangle {
                    visible: popup.vpnConnected || popup.actionBusy
                    width: btnText.width + 16
                    height: 24
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: popup.actionBusy
                           ? Qt.rgba(popup.mutedColor.r, popup.mutedColor.g, popup.mutedColor.b, 0.3)
                           : Qt.rgba(popup.accentRed.r, popup.accentRed.g, popup.accentRed.b, 0.2)

                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: popup.actionBusy ? "\u2026" : "Disconnect"
                        font.pixelSize: popup.fontSize - 2
                        font.family: popup.fontFamily
                        font.bold: true
                        color: popup.actionBusy ? popup.mutedColor : popup.accentRed
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (popup.actionBusy) return
                            popup.actionBusy = true
                            popup.disconnectPending = true
                            popup.connectedInfo = null
                            popup.vpnConnected = false
                            popup.vpnServer = ""
                            popup.vpnCountry = ""
                            disconnectPendingReset.restart()
                            vpnDisconnectProc.running = true
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Connected details ─────────────────────────
            Column {
                visible: popup.vpnConnected && popup.connectedInfo !== null
                width: parent.width
                spacing: 4

                Text {
                    text: "CONNECTED"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }

                Rectangle {
                    width: parent.width
                    height: connDetailsCol.height + 12
                    radius: 4
                    color: Qt.rgba(popup.accentGreen.r, popup.accentGreen.g, popup.accentGreen.b, 0.1)

                    Column {
                        id: connDetailsCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 8
                        }
                        spacing: 3

                        // Server name with flag
                        Text {
                            text: {
                                if (!popup.connectedInfo) return ""
                                var flag = popup.connectedInfo.flag || ""
                                var name = popup.connectedInfo.name || ""
                                return (flag ? flag + "  " : "") + name
                            }
                            font.pixelSize: popup.fontSize
                            font.family: popup.fontFamily
                            font.bold: true
                            color: popup.accentGreen
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        // Protocol
                        Text {
                            visible: popup.connectedInfo !== null && (popup.connectedInfo ? popup.connectedInfo.protocol : "") !== ""
                            text: "   " + (popup.connectedInfo ? popup.connectedInfo.protocol : "")
                            font.pixelSize: popup.fontSize - 2
                            font.family: popup.fontFamily
                            color: popup.fgColor
                        }

                        // IP address
                        Text {
                            visible: popup.connectedInfo !== null && (popup.connectedInfo ? popup.connectedInfo.ip : "") !== ""
                            text: "   " + (popup.connectedInfo ? popup.connectedInfo.ip : "")
                            font.pixelSize: popup.fontSize - 3
                            font.family: popup.fontFamily
                            color: popup.mutedColor
                        }
                    }
                }
            }

            // ── Disconnected state ────────────────────────
            Column {
                visible: !popup.vpnConnected
                width: parent.width
                spacing: 6

                Text {
                    text: "Not connected"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }

                // ── Saved profiles ────────────────────────
                Text {
                    visible: popup.profiles.length > 0
                    text: "SAVED PROFILES"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    topPadding: 4
                }

                Repeater {
                    model: popup.profiles

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 32
                        radius: 4
                        color: profileMouse.containsMouse
                               ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                               : "transparent"

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 8

                            Image {
                                source: "proton-vpn-logo.svg"
                                sourceSize: Qt.size(popup.fontSize, popup.fontSize)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.name
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                elide: Text.ElideRight
                                width: parent.width - profileProtoText.width - profileActionBtn.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: profileProtoText
                                text: modelData.protocol
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: profileActionBtn
                                text: popup.actionBusy ? "\u2026" : "Connect"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentGreen
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: profileMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                if (popup.actionBusy) return
                                popup.actionBusy = true
                                vpnConnectProc.targetProfile = modelData.name
                                vpnConnectProc.running = true
                            }
                        }
                    }
                }

                // No profiles
                Text {
                    visible: popup.profiles.length === 0
                    text: "No VPN profiles saved"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }
            }

            // ── Divider ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Open ProtonVPN GUI button ─────────────────
            Rectangle {
                width: parent.width
                height: 28
                radius: 4
                color: openGuiMouse.containsMouse
                       ? Qt.rgba(popup.accentTeal.r, popup.accentTeal.g, popup.accentTeal.b, 0.15)
                       : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        source: "proton-vpn-logo.svg"
                        sourceSize: Qt.size(popup.fontSize, popup.fontSize)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Open ProtonVPN"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        color: popup.accentTeal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: openGuiMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: {
                        vpnGuiProc.running = true
                        popup.visible = false
                    }
                }
            }
        }
    }
}

