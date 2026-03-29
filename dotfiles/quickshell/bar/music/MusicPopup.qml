import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// MPRIS media player popup for Quickshell bar
// Shows current track info and playback controls via playerctl

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

    // Theme colors (passed from root)
    required property color bgColor
    required property color fgColor
    required property color mutedColor
    required property color accentGreen
    required property color accentYellow
    required property color accentOrange
    required property string fontFamily
    required property int fontSize

    // Expose state to parent for bar pill
    property bool playerAvailable: false
    property string playerStatus: "Stopped"
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackAlbum: ""
    property int trackPosition: 0
    property int trackLength: 0

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    // ─────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────
    property string _buf: ""

    readonly property string scriptsDir:
        Qt.resolvedUrl("../scripts/").toString().replace("file://", "")

    function _parseStatus(buf) {
        try {
            var d = JSON.parse(buf)
            popup.playerAvailable = d.available || false
            popup.playerStatus = d.status || "Stopped"
            popup.trackTitle = d.title || ""
            popup.trackArtist = d.artist || ""
            popup.trackAlbum = d.album || ""
            popup.trackPosition = d.position || 0
            popup.trackLength = d.length || 0
        } catch(e) {}
    }

    function formatTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // ─────────────────────────────────────────────────────
    // Status polling
    // ─────────────────────────────────────────────────────
    Process {
        id: statusProc
        command: ["bash", popup.scriptsDir + "music_panel.sh", "--status"]
        stdout: SplitParser {
            onRead: function(line) { popup._buf += line }
        }
        onExited: function() {
            popup._parseStatus(popup._buf)
            popup._buf = ""
        }
    }

    // Background poll (pill updates when popup closed)
    Timer {
        interval: 5000
        running: !popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    // Foreground poll (faster updates when popup open)
    Timer {
        interval: 2000
        running: popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    // ─────────────────────────────────────────────────────
    // Action processes
    // ─────────────────────────────────────────────────────
    property string _actionBuf: ""

    Process {
        id: playPauseProc
        command: ["bash", popup.scriptsDir + "music_panel.sh", "--play-pause"]
        stdout: SplitParser {
            onRead: function(line) { popup._actionBuf += line }
        }
        onExited: function() {
            popup._parseStatus(popup._actionBuf)
            popup._actionBuf = ""
        }
    }

    Process {
        id: nextProc
        command: ["bash", popup.scriptsDir + "music_panel.sh", "--next"]
        stdout: SplitParser {
            onRead: function(line) { popup._actionBuf += line }
        }
        onExited: function() {
            popup._parseStatus(popup._actionBuf)
            popup._actionBuf = ""
        }
    }

    Process {
        id: prevProc
        command: ["bash", popup.scriptsDir + "music_panel.sh", "--previous"]
        stdout: SplitParser {
            onRead: function(line) { popup._actionBuf += line }
        }
        onExited: function() {
            popup._parseStatus(popup._actionBuf)
            popup._actionBuf = ""
        }
    }

    // ─────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────
    Rectangle {
        id: popupContent
        width: 300
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

            // ── Header ────────────────────────────────────
            Text {
                text: "\uF001  Now Playing"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                font.bold: true
                color: popup.accentGreen
            }

            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Track info (when player available) ────────
            Column {
                visible: popup.playerAvailable
                width: parent.width
                spacing: 4

                Text {
                    width: parent.width
                    text: popup.trackTitle || "Unknown"
                    font.pixelSize: popup.fontSize + 1
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.playerStatus === "Playing" ? popup.accentGreen : popup.fgColor
                    elide: Text.ElideRight
                }

                Text {
                    visible: popup.trackArtist !== ""
                    width: parent.width
                    text: popup.trackArtist
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.fgColor
                    elide: Text.ElideRight
                }

                Text {
                    visible: popup.trackAlbum !== ""
                    width: parent.width
                    text: popup.trackAlbum
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    elide: Text.ElideRight
                }
            }

            // ── Progress bar ──────────────────────────────
            Column {
                visible: popup.playerAvailable && popup.trackLength > 0
                width: parent.width
                spacing: 4

                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.15)

                    Rectangle {
                        width: popup.trackLength > 0
                               ? parent.width * Math.min(popup.trackPosition / popup.trackLength, 1.0)
                               : 0
                        height: parent.height
                        radius: 2
                        color: popup.accentGreen
                    }
                }

                Row {
                    width: parent.width

                    Text {
                        id: posLeft
                        text: popup.formatTime(popup.trackPosition)
                        font.pixelSize: popup.fontSize - 3
                        font.family: popup.fontFamily
                        color: popup.mutedColor
                    }

                    Item { width: parent.width - posLeft.width - posRight.width; height: 1 }

                    Text {
                        id: posRight
                        text: popup.formatTime(popup.trackLength)
                        font.pixelSize: popup.fontSize - 3
                        font.family: popup.fontFamily
                        color: popup.mutedColor
                    }
                }
            }

            // ── Playback controls ─────────────────────────
            Row {
                visible: popup.playerAvailable
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28

                Text {
                    text: "\uF048"
                    font.pixelSize: popup.fontSize + 4
                    font.family: popup.fontFamily
                    color: popup.fgColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: prevProc.running = true
                        onEntered: parent.color = popup.accentOrange
                        onExited: parent.color = popup.fgColor
                    }
                }

                Text {
                    text: popup.playerStatus === "Playing" ? "\uF04C" : "\uF04B"
                    font.pixelSize: popup.fontSize + 8
                    font.family: popup.fontFamily
                    color: popup.accentGreen

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: playPauseProc.running = true
                        onEntered: parent.color = popup.accentYellow
                        onExited: parent.color = popup.accentGreen
                    }
                }

                Text {
                    text: "\uF051"
                    font.pixelSize: popup.fontSize + 4
                    font.family: popup.fontFamily
                    color: popup.fgColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: nextProc.running = true
                        onEntered: parent.color = popup.accentOrange
                        onExited: parent.color = popup.fgColor
                    }
                }
            }

            // ── No player message ─────────────────────────
            Text {
                visible: !popup.playerAvailable
                text: "No media player running"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
            }

            // ── Divider ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Open Spotify button ───────────────────────
            Rectangle {
                width: parent.width
                height: 28
                radius: 4
                color: openSpotifyMa.containsMouse
                       ? Qt.rgba(popup.accentGreen.r, popup.accentGreen.g, popup.accentGreen.b, 0.2)
                       : "transparent"

                Process {
                    id: spotifyProc
                    command: ["/run/current-system/sw/bin/flatpak", "run", "com.spotify.Client"]
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uF1BC  Open Spotify"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.accentGreen
                }

                MouseArea {
                    id: openSpotifyMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: spotifyProc.running = true
                }
            }
        }
    }
}
