import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

// MPRIS media player popup for Quickshell bar
// Shows current track info and playback controls via Quickshell's native MPRIS service.

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
    required property color accentGreen
    required property color accentYellow
    required property color accentOrange
    required property string fontFamily
    required property int fontSize

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    readonly property var activePlayer: {
        var players = Mpris.players.values
        if (players.length === 0)
            return null
        for (var i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players[0]
    }

    readonly property bool playerAvailable: activePlayer !== null
    readonly property string playerStatus: !activePlayer
        ? "Stopped"
        : MprisPlaybackState.toString(activePlayer.playbackState)
    readonly property string playerName: activePlayer?.identity || activePlayer?.desktopEntry || ""
    readonly property string trackTitle: activePlayer?.trackTitle ?? ""
    readonly property string trackArtist: activePlayer?.trackArtist ?? ""
    readonly property string trackAlbum: activePlayer?.trackAlbum ?? ""
    readonly property int trackPosition: Math.max(0, Math.floor(activePlayer?.position ?? 0))
    readonly property int trackLength: Math.max(0, Math.floor(activePlayer?.length ?? 0))

    readonly property string scriptsDir:
        Qt.resolvedUrl("../scripts/").toString().replace("file://", "")

    function formatTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Process {
        id: spotifyProc
        command: ["bash", "-c",
            "rm -f ~/.var/app/com.spotify.Client/cache/spotify/Singleton{Lock,Socket,Cookie} 2>/dev/null; " +
            "exec bash '" + popup.scriptsDir + "tray_pill.sh' --toggle --class Spotify " +
            "--launch 'flatpak run com.spotify.Client'"]
    }

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
                    color: popup.activePlayer?.isPlaying ? popup.accentGreen : popup.fgColor
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
                        width: parent.width * Math.min(popup.trackPosition / popup.trackLength, 1.0)
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

            Row {
                visible: popup.playerAvailable
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28

                Text {
                    text: "\uF048"
                    font.pixelSize: popup.fontSize + 4
                    font.family: popup.fontFamily
                    color: popup.activePlayer?.canGoPrevious ? popup.fgColor : popup.mutedColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: popup.activePlayer?.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: popup.activePlayer?.canGoPrevious ?? false
                        onClicked: if (popup.activePlayer?.canGoPrevious) popup.activePlayer.previous()
                        onEntered: parent.color = popup.accentOrange
                        onExited: parent.color = popup.activePlayer?.canGoPrevious ? popup.fgColor : popup.mutedColor
                    }
                }

                Text {
                    text: popup.activePlayer?.isPlaying ? "\uF04C" : "\uF04B"
                    font.pixelSize: popup.fontSize + 8
                    font.family: popup.fontFamily
                    color: popup.activePlayer?.canTogglePlaying ? popup.accentGreen : popup.mutedColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: popup.activePlayer?.canTogglePlaying ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: popup.activePlayer?.canTogglePlaying ?? false
                        onClicked: if (popup.activePlayer?.canTogglePlaying) popup.activePlayer.togglePlaying()
                        onEntered: parent.color = popup.accentYellow
                        onExited: parent.color = popup.activePlayer?.canTogglePlaying ? popup.accentGreen : popup.mutedColor
                    }
                }

                Text {
                    text: "\uF051"
                    font.pixelSize: popup.fontSize + 4
                    font.family: popup.fontFamily
                    color: popup.activePlayer?.canGoNext ? popup.fgColor : popup.mutedColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: popup.activePlayer?.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: popup.activePlayer?.canGoNext ?? false
                        onClicked: if (popup.activePlayer?.canGoNext) popup.activePlayer.next()
                        onEntered: parent.color = popup.accentOrange
                        onExited: parent.color = popup.activePlayer?.canGoNext ? popup.fgColor : popup.mutedColor
                    }
                }
            }

            Text {
                visible: !popup.playerAvailable
                text: "No media player running"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
            }

            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            Rectangle {
                visible: popup.playerName === "" || popup.playerName.toLowerCase().indexOf("spotify") !== -1
                width: parent.width
                height: 28
                radius: 4
                color: openSpotifyMa.containsMouse
                       ? Qt.rgba(popup.accentGreen.r, popup.accentGreen.g, popup.accentGreen.b, 0.2)
                       : "transparent"

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
