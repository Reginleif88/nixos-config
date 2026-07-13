//@ pragma UseQApplication
// Quickshell status bar for Hyprland
// Entry point: ~/.config/quickshell/shell.qml
// Tested against Quickshell v0.3.0
//
// Features:
//   - Hyprland workspace switcher (clickable, left side)
//   - Clock with date (center)
//   - System tray with right-click menu (right side)
//   - Volume level via native PipeWire bindings (right side)
//   - Active window title (left side, after workspaces)
//
// Dependencies:
//   - quickshell
//   - hyprland (IPC via Quickshell.Hyprland)
//   - pipewire (native PipeWire bindings via Quickshell.Services.Pipewire)
//
// nerd font for icons

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "sidebar"
import "network"
import "audio"
import "sysmon"
import "music"

ShellRoot {
    id: root

    // ---------------------
    // Theme / font settings
    // ---------------------
    readonly property color bgColor:        "#282828"   // Gruvbox Dark bg
    readonly property color fgColor:        "#ebdbb2"   // fg
    readonly property color mutedColor:     "#504945"   // bg2
    readonly property color accentBlue:     "#83a598"   // bright blue
    readonly property color accentLavender: "#d3869b"   // bright purple
    readonly property color accentGreen:    "#b8bb26"   // bright green
    readonly property color accentYellow:   "#fabd2f"   // bright yellow
    readonly property color accentRed:      "#fb4934"   // bright red
    readonly property color accentMauve:    "#d3869b"   // bright purple
    readonly property color accentTeal:     "#8ec07c"   // bright aqua
    readonly property color accentOrange:   "#fe8019"   // bright orange

    readonly property string fontFamily:    "FiraCode Nerd Font"
    readonly property int    fontSize:      15
    readonly property int    barHeight:     32
    readonly property int    barGap:        8    // top gap
    readonly property int    barBottomGap:  0    // bottom gap (below bar)
    readonly property int    barSideMargin: 8    // left + right inset

    // Pill capsule theming
    readonly property color pillColor:   Qt.rgba(0.157, 0.157, 0.157, 0.88)  // #282828 at 88% opacity
    readonly property int  pillRadius:   14    // full capsule end-caps
    readonly property int  pillHPad:     10    // horizontal padding
    readonly property int  pillVPad:     4     // vertical padding
    readonly property int  pillSpacing:  6     // gap between pills

    // ---------------------
    // Global state
    // ---------------------
    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property real volumeRaw: defaultSink?.audio?.volume ?? 0
    readonly property int volumeLevel: Math.round(volumeRaw * 100)
    readonly property bool volumeMuted: defaultSink?.audio?.muted ?? false
    readonly property string activeWindowTitle: Hyprland.activeToplevel?.title ?? ""
    readonly property var activeMusicPlayer: {
        var players = Mpris.players.values
        if (players.length === 0)
            return null
        for (var i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players[0]
    }
    readonly property string musicPlayerStatus: activeMusicPlayer === null
        ? "Stopped" : MprisPlaybackState.toString(activeMusicPlayer.playbackState)
    readonly property string musicTrackTitle: activeMusicPlayer?.trackTitle ?? ""
    readonly property string musicTrackArtist: activeMusicPlayer?.trackArtist ?? ""
    readonly property var wifiDevice: {
        var devices = Networking.devices.values
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        }
        return null
    }
    readonly property var wifiConnected: {
        if (wifiDevice === null)
            return null
        var networks = wifiDevice.networks.values
        for (var i = 0; i < networks.length; i++) {
            if (networks[i].connected)
                return networks[i]
        }
        return null
    }
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothConnected: bluetoothAdapter === null
        ? [] : bluetoothAdapter.devices.values.filter(function(device) { return device.connected })
    readonly property string wifiPower: Networking.wifiEnabled ? "on" : "off"
    readonly property string bluetoothPower: bluetoothAdapter !== null && bluetoothAdapter.enabled ? "on" : "off"
    property real cpuPercent: 0
    property real ramGb: 0
    property var _cpuPrev: null

    readonly property var fallbackWorkspaceIdsByMonitor: ({
        "DP-3": [1, 2],
        "HDMI-A-1": [3, 4],
        "eDP-1": [1, 2],
        "DP-1": [1, 2]
    })

    function workspaceIdsForMonitor(monitor) {
        if (monitor !== null && monitor !== undefined) {
            var ids = []
            var workspaces = Hyprland.workspaces.values
            for (var i = 0; i < workspaces.length; i++) {
                var ws = workspaces[i]
                if (ws.id > 0 && ws.monitor !== null && ws.monitor.name === monitor.name)
                    ids.push(ws.id)
            }
            if (ids.length > 0)
                return ids.sort(function(a, b) { return a - b })

            if (root.fallbackWorkspaceIdsByMonitor[monitor.name] !== undefined)
                return root.fallbackWorkspaceIdsByMonitor[monitor.name]
        }

        return [1, 2, 3, 4]
    }

    // Monitor that owns workspace 1. Gemini is intentionally available only
    // while that workspace is active on this monitor.
    readonly property string workspaceOneMonitorName: {
        var workspaces = Hyprland.workspaces.values
        for (var i = 0; i < workspaces.length; i++) {
            if (workspaces[i].id === 1 && workspaces[i].monitor !== null)
                return workspaces[i].monitor.name
        }
        return ""
    }

    readonly property bool workspaceOneActive: Hyprland.activeWorkspace?.id === 1

    function wifiSignalPercent(signal) {
        var value = Number(signal)
        if (!isFinite(value))
            return 0
        if (value <= 1)
            value *= 100
        return Math.max(0, Math.min(100, value))
    }

    function wifiSignalIcon(signal) {
        var pct = root.wifiSignalPercent(signal)
        if (pct >= 80) return "\uDB82\uDD28"
        if (pct >= 60) return "\uDB82\uDD25"
        if (pct >= 40) return "\uDB82\uDD22"
        if (pct >= 20) return "\uDB82\uDD1F"
        return "\uDB82\uDD2F"
    }

    // Active tab for the network popup — lifted to root so all monitor
    // instances share the view and the choice persists across opens.
    property string networkActiveTab: "wifi"

    // ---------------------
    // Weather state (populated from weather.sh script)
    // ---------------------
    property string weatherIcon: ""
    property string weatherTemp: "0"
    property string weatherFeelsLike: "0"
    property color weatherHex: "#8ec07c"
    property string weatherDesc: ""
    property bool weatherReady: false
    property string weatherError: ""
    property var weatherForecast: []
    property int weatherSelectedDay: 0

    // ---------------------
    // Mail (Proton Mail desktop) state
    // ---------------------
    readonly property color protonPurple: "#6D4AFF"  // Proton brand purple

    property bool mailRunning: false
    property int mailUnread: 0
    property string mailAddress: ""
    property string mailWorkspace: ""
    property bool mailMinimized: false
    property string _mailBuf: ""

    readonly property string mailScript:
        Qt.resolvedUrl("scripts/mail_panel.sh").toString().replace("file://", "")

    Process {
        id: mailStatusProc
        command: ["bash", root.mailScript, "--status"]
        stdout: SplitParser {
            onRead: function(line) { root._mailBuf += line }
        }
        onExited: function() {
            try {
                var d = JSON.parse(root._mailBuf)
                root.mailRunning = d.running || false
                root.mailUnread = d.unread || 0
                root.mailAddress = d.address || ""
                root.mailWorkspace = d.workspace || ""
                root.mailMinimized = d.workspace === "special:minimized"
            } catch(e) {}
            root._mailBuf = ""
        }
    }

    Process {
        id: mailToggleProc
        command: ["bash", root.mailScript, "--toggle"]
        onExited: function() {
            // Quick re-poll to update state after toggle
            mailPostToggleTimer.restart()
        }
    }

    // Delay re-poll slightly so hyprctl state settles
    Timer {
        id: mailPostToggleTimer
        interval: 300
        onTriggered: mailStatusProc.running = true
    }

    // Fast poll at startup (every 2s for the first 30s) then settle to 15s
    property int _mailPollCount: 0

    Timer {
        id: mailPollTimer
        interval: root._mailPollCount < 15 ? 2000 : 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._mailPollCount++
            mailStatusProc.running = true
        }
    }

    // ---------------------
    // Obsidian state
    // ---------------------
    readonly property color obsidianPurple: "#7C3AED"  // Obsidian brand purple
    readonly property var obsWindow: {
        var windows = Hyprland.toplevels.values
        for (var i = 0; i < windows.length; i++) {
            var state = windows[i].lastIpcObject || {}
            var appClass = (state.class || state.initialClass || "").toLowerCase()
            if (appClass === "obsidian" || windows[i].title === "Obsidian")
                return windows[i]
        }
        return null
    }
    readonly property bool obsRunning: obsWindow !== null
    readonly property bool obsMinimized: obsWindow !== null
        && obsWindow.workspace !== null
        && obsWindow.workspace.name === "special:minimized"

    readonly property string trayScript:
        Qt.resolvedUrl("scripts/tray_pill.sh").toString().replace("file://", "")

    Process {
        id: obsToggleProc
        command: ["bash", root.trayScript, "--toggle", "--title", "Obsidian", "--launch", "obsidian"]
    }

    // ---------------------
    // Claude provider state (Anthropic / ZLM toggle)
    // ---------------------
    property string claudeProvider: "anthropic"
    property string claudeLabel: "API"
    property string _claudeToggleBuf: ""

    readonly property string claudeProviderScript:
        Qt.resolvedUrl("scripts/claude_provider.sh").toString().replace("file://", "")

    function refreshClaudeProvider() {
        var provider = claudeProviderState.text().trim()
        root.claudeProvider = provider === "zlm" ? "zlm" : "anthropic"
        root.claudeLabel = root.claudeProvider === "zlm" ? "ZLM" : "API"
    }

    FileView {
        id: claudeProviderState
        path: "/home/reginleif88/.config/claude-provider/active"
        watchChanges: true
        onTextChanged: root.refreshClaudeProvider()
        Component.onCompleted: root.refreshClaudeProvider()
    }

    Process {
        id: claudeToggleProc
        command: ["bash", root.claudeProviderScript, "--toggle"]
        stdout: SplitParser {
            onRead: function(line) { root._claudeToggleBuf += line }
        }
        onExited: function() {
            root.refreshClaudeProvider()
            root._claudeToggleBuf = ""
        }
    }

    // ---------------------
    // Notification center (SwayNC) state
    // ---------------------
    property int notifCount: 0
    property bool dndEnabled: false

    Process {
        id: notifSubscribeProc
        running: true
        command: ["swaync-client", "--subscribe-waybar"]
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var d = JSON.parse(line)
                    root.notifCount = parseInt(d.text) || 0
                    root.dndEnabled = (d.alt || "").indexOf("dnd") !== -1
                } catch(e) {}
            }
        }
        onExited: function() { notifRestartTimer.running = true }
    }

    // Restart subscribe if it exits unexpectedly
    Timer {
        id: notifRestartTimer
        interval: 3000
        onTriggered: notifSubscribeProc.running = true
    }

    Process {
        id: notifToggleProc
        command: ["swaync-client", "-t"]
    }

    // ---------------------
    // Track all PipeWire nodes for full property access
    // ---------------------
    PwObjectTracker {
        objects: [root.defaultSink].concat(Pipewire.nodes.values)
    }

    // ---------------------
    // System clock (built-in, no process needed)
    // ---------------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------------------
    // Screenshot via grimblast
    // ---------------------
    Process {
        id: screenshotProc
        // copysave: copies to clipboard AND saves to ~/Pictures/<timestamp>.png
        // bash wrapper: notify on success, silent on cancel (Escape key)
        command: ["bash", "-c",
            "FILE=$(grimblast copysave area) && " +
            "notify-send -i camera-photo -t 3000 'Screenshot' \"Saved & copied:\\n$(basename \"$FILE\")\""
        ]
    }

    // ---------------------
    // Refresh Hyprland models when compositor state changes.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow" ||
                event.name === "movewindow" || event.name === "moveworkspace" ||
                event.name === "workspace" || event.name === "focusedmon") {
                Hyprland.refreshWorkspaces()
                Hyprland.refreshToplevels()
            }
            if (event.name === "monitoradded" || event.name === "monitorremoved")
                Hyprland.refreshMonitors()
        }
    }

    // ---------------------
    // CPU and RAM sampler (one /proc read every 2 s)
    // ---------------------
    property int _ramTotalKb: 0
    property int _ramAvailableKb: 0
    Process {
        id: systemStatsProc
        command: ["cat", "/proc/stat", "/proc/meminfo"]
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split(/\s+/)
                if (parts[0] === "cpu") {
                    var total = 0
                    for (var i = 1; i <= 7 && i < parts.length; i++)
                        total += parseInt(parts[i]) || 0
                    var idle = parseInt(parts[4]) || 0
                    if (root._cpuPrev !== null) {
                        var dt = total - root._cpuPrev.total
                        var di = idle - root._cpuPrev.idle
                        root.cpuPercent = dt > 0 ? Math.round((dt - di) / dt * 100) : root.cpuPercent
                    }
                    root._cpuPrev = { total: total, idle: idle }
                } else if (parts[0] === "MemTotal:") {
                    root._ramTotalKb = parseInt(parts[1]) || 0
                } else if (parts[0] === "MemAvailable:") {
                    root._ramAvailableKb = parseInt(parts[1]) || 0
                }
            }
        }
        onExited: {
            if (root._ramTotalKb > 0)
                root.ramGb = (root._ramTotalKb - root._ramAvailableKb) / 1024 / 1024
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!systemStatsProc.running) systemStatsProc.running = true
    }

    // Weather current conditions and forecast share one request and one cache.
    property string _weatherBuf: ""
    Process {
        id: weatherProc
        command: ["quickshell-weather", "--json"]
        stdout: SplitParser {
            onRead: function(line) { root._weatherBuf += line }
        }
        onExited: {
            try {
                var d = JSON.parse(root._weatherBuf)
                if (d.current) {
                    root.weatherIcon = d.current.icon || ""
                    root.weatherTemp = String(Math.round(d.current.temp))
                    root.weatherFeelsLike = String(Math.round(d.current.feels_like))
                    root.weatherHex = d.current.hex || root.weatherHex
                    root.weatherDesc = d.current.desc || ""
                    root.weatherReady = true
                    root.weatherError = ""
                }
                if (d.forecast)
                    root.weatherForecast = d.forecast
            } catch(e) {
                root.weatherError = "Weather data unavailable"
            }
            root._weatherBuf = ""
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!weatherProc.running) weatherProc.running = true
    }

    // ---------------------
    // One PanelWindow per screen via Variants
    // ---------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            property bool weatherPopupOpen: false
            property bool sysMonOpen: false
            property string sysMonTab: "cpu"
            property bool networkPopupOpen: false
            property bool audioPopupOpen: false
            property bool musicPopupOpen: false

            // Hyprland monitor object for this bar's screen
            readonly property var hyprMonitor: Hyprland.monitorFor(bar.screen)

            readonly property var monitorWsIds: root.workspaceIdsForMonitor(bar.hyprMonitor)
            readonly property bool hideForWindowsWorkspace: bar.hyprMonitor !== null
                && bar.hyprMonitor.activeWorkspace !== null
                && bar.hyprMonitor.activeWorkspace.id === 2

            // Anchor to the top edge, spanning full width
            anchors {
                top:   true
                left:  true
                right: true
            }

            // Reserve space so windows don't overlap the bar
            visible: !bar.hideForWindowsWorkspace
            exclusiveZone: bar.hideForWindowsWorkspace ? 0 : root.barHeight + root.barGap + root.barBottomGap

            implicitHeight: bar.hideForWindowsWorkspace ? 0 : root.barHeight + root.barGap + root.barBottomGap
            color: "transparent"   // background painted by inner Rectangle

            // -------------------------------------------------------
            // Root bar container (transparent — pills provide bg)
            // -------------------------------------------------------
            Item {
                anchors {
                    fill:         parent
                    topMargin:    root.barGap
                    bottomMargin: root.barBottomGap
                    leftMargin:   root.barSideMargin
                    rightMargin:  root.barSideMargin
                }

                // Clock + weather pill: true-centered, shifts right if left pills overlap
                Pill {
                    id: clockPill
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(
                        (parent.width - width) / 2,
                        musicPill.x + musicPill.width + root.pillSpacing
                    )
                    z: 1
                    innerSpacing: 16

                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd d MMM   HH:mm")
                        color: root.accentOrange
                        font.pixelSize: root.fontSize; font.family: root.fontFamily
                        font.bold: true
                    }

                    Text {
                        id: weatherBtn
                        visible: root.weatherReady
                        text: root.weatherIcon + " " + root.weatherTemp +
                              "\u00B0(" + root.weatherFeelsLike + ")"
                        color: root.weatherHex
                        font.pixelSize: root.fontSize; font.family: root.fontFamily
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.weatherForecast.length === 0 && !weatherProc.running) {
                                    root._weatherBuf = ""
                                    weatherProc.running = true
                                }
                                bar.weatherPopupOpen = !bar.weatherPopupOpen
                            }
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: root.pillSpacing

                    // ======================
                    // LEFT SECTION
                    // ======================

                    // ---- Workspaces pill ----
                    Pill {
                        innerSpacing: 2

                        Repeater {
                            model: bar.monitorWsIds

                            delegate: Item {
                                id: wsItem
                                required property int modelData

                                readonly property int  wsId:     modelData
                                readonly property var  wsObj:    Hyprland.workspaces.values.find(function(ws) { return ws.id === wsId }) ?? null
                                readonly property bool isFocused: bar.hyprMonitor !== null && bar.hyprMonitor.activeWorkspace !== null && bar.hyprMonitor.activeWorkspace.id === wsId
                                readonly property bool hasWindows: wsObj !== null && wsObj.toplevels.values.length > 0

                                Layout.preferredWidth:  24
                                Layout.preferredHeight: root.barHeight - root.pillVPad * 2

                                // Highlight pill behind the active workspace number
                                Rectangle {
                                    visible: wsItem.isFocused
                                    anchors.centerIn: parent
                                    width:  20
                                    height: 20
                                    radius: 4
                                    color:  Qt.rgba(
                                        root.accentBlue.r,
                                        root.accentBlue.g,
                                        root.accentBlue.b,
                                        0.2
                                    )
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: wsItem.wsId
                                    font.pixelSize: root.fontSize
                                    font.family:    root.fontFamily
                                    font.bold:      wsItem.isFocused
                                    color: wsItem.isFocused
                                           ? root.accentBlue
                                           : (wsItem.hasWindows ? root.fgColor : root.mutedColor)
                                }

                                // Dot indicator at the bottom for occupied (but unfocused) workspaces
                                Rectangle {
                                    visible: wsItem.hasWindows && !wsItem.isFocused
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width:  4
                                    height: 4
                                    radius: 2
                                    color:  root.accentMauve
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: wsItem.wsObj !== null
                                        ? wsItem.wsObj.activate()
                                        : Hyprland.dispatch("workspace " + wsItem.wsId)
                                }
                            }
                        }
                    }

                    // ---- Window title pill ----
                    Pill {
                        Text {
                            text: "\uF2D0 " + (root.activeWindowTitle.length > 0
                                  ? root.activeWindowTitle
                                  : "Desktop")
                            color:           root.fgColor
                            font.pixelSize:  root.fontSize
                            font.family:     root.fontFamily
                            elide:           Text.ElideRight
                            maximumLineCount: 1
                            Layout.maximumWidth: 300
                        }
                    }

                    // ---- CPU + RAM pill ----
                    Pill {
                        innerSpacing: 8

                        Text {
                            id: cpuText
                            text: "\uF4BC " + root.cpuPercent + "%"
                            color: bar.sysMonOpen && bar.sysMonTab === "cpu" ? root.accentYellow
                                 : root.cpuPercent > 85 ? root.accentRed
                                 : root.cpuPercent > 60 ? root.accentYellow
                                 : root.accentTeal
                            font.pixelSize: root.fontSize
                            font.family:    root.fontFamily
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bar.sysMonTab = "cpu"
                                    bar.sysMonOpen = !bar.sysMonOpen
                                }
                            }
                        }

                        Text {
                            text: "\uF2DB " + root.ramGb.toFixed(1) + "G"
                            color: bar.sysMonOpen && bar.sysMonTab === "ram" ? root.accentYellow
                                 : root.ramGb > 16 ? root.accentRed
                                 : root.ramGb > 8  ? root.accentYellow
                                 : root.accentBlue
                            font.pixelSize: root.fontSize
                            font.family:    root.fontFamily
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bar.sysMonTab = "ram"
                                    bar.sysMonOpen = !bar.sysMonOpen
                                }
                            }
                        }
                    }

                    // ---- Music pill (MPRIS media controls) ----
                    Pill {
                        id: musicPill

                        Text {
                            id: musicIcon
                            text: "\uF001"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: bar.musicPopupOpen ? root.accentYellow
                                 : root.musicPlayerStatus === "Playing" ? root.accentGreen
                                 : root.mutedColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.musicPopupOpen = !bar.musicPopupOpen
                            }
                        }

                        Text {
                            visible: root.musicTrackArtist !== "" || root.musicTrackTitle !== ""
                            text: {
                                var info = ""
                                if (root.musicTrackArtist !== "")
                                    info = root.musicTrackArtist + " - "
                                info += root.musicTrackTitle
                                return info.length > 30 ? info.substring(0, 28) + "\u2026" : info
                            }
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: root.musicPlayerStatus === "Playing" ? root.accentGreen : root.mutedColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.musicPopupOpen = !bar.musicPopupOpen
                            }
                        }
                    }

                    // ======================
                    // CENTER SECTION (spacer)
                    // ======================
                    Item { Layout.fillWidth: true }

                    // ======================
                    // RIGHT SECTION
                    // ======================

                    // ---- System tray pill ----
                    Pill {
                        innerSpacing: 4

                        Repeater {
                            model: SystemTray.items.values

                            delegate: Item {
                                id: trayIcon
                                required property var modelData
                                required property int index
                                Layout.preferredWidth:  20
                                Layout.preferredHeight: 20

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 16
                                    source: trayIcon.modelData.icon
                                    mipmap: true
                                }

                                QsMenuAnchor {
                                    id: trayMenu
                                    anchor.item: trayIcon
                                    menu: trayIcon.modelData.menu
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            if (trayIcon.modelData.hasMenu) {
                                                trayMenu.open()
                                            } else {
                                                trayIcon.modelData.activate()
                                            }
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            trayIcon.modelData.secondaryActivate()
                                        } else {
                                            if (trayIcon.modelData.onlyMenu && trayIcon.modelData.hasMenu) {
                                                trayMenu.open()
                                            } else {
                                                trayIcon.modelData.activate()
                                            }
                                        }
                                    }
                                    onWheel: function(wheel) {
                                        trayIcon.modelData.scroll(wheel.angleDelta.y / 120, false)
                                    }
                                }
                            }
                        }
                    }

                    // ---- Audio pill (sink switch + volume) ----
                    Pill {
                        innerSpacing: 8

                        Text {
                            id: sinkSwitchBtn
                            text: "\uF025"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: bar.audioPopupOpen ? root.accentYellow : root.accentGreen
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.audioPopupOpen = !bar.audioPopupOpen
                            }
                        }

                        Item {
                            id: volumeGroup
                            implicitWidth: volRow.width
                            implicitHeight: volRow.height

                            Row {
                                id: volRow
                                spacing: 4
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: speakerIcon
                                    text: root.volumeMuted ? "\uF026" :
                                          (root.volumeLevel > 66 ? "\uF028" :
                                           root.volumeLevel > 33 ? "\uF027" : "\uF027")
                                    font.pixelSize: root.fontSize
                                    font.family: root.fontFamily
                                    color: root.volumeMuted ? root.mutedColor : root.accentGreen
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                if (root.defaultSink)
                                                    root.defaultSink.audio.muted = !root.defaultSink.audio.muted
                                            } else
                                                bar.audioPopupOpen = !bar.audioPopupOpen
                                        }
                                    }
                                }

                                Text {
                                    text: root.volumeMuted ? "mute" : root.volumeLevel + "%"
                                    font.pixelSize: root.fontSize
                                    font.family:    root.fontFamily
                                    color: root.volumeMuted ? root.mutedColor : root.accentGreen
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                if (root.defaultSink)
                                                    root.defaultSink.audio.muted = !root.defaultSink.audio.muted
                                            } else
                                                bar.audioPopupOpen = !bar.audioPopupOpen
                                        }
                                    }
                                }
                            }

                            // Scroll-wheel volume control over the volume area
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: function(wheel) {
                                    if (!root.defaultSink) return
                                    var step = root.volumeRaw < 0.1 ? 0.01 : 0.02
                                    if (wheel.angleDelta.y > 0)
                                        root.defaultSink.audio.volume = Math.min(1.0, root.volumeRaw + step)
                                    else
                                        root.defaultSink.audio.volume = Math.max(0, root.volumeRaw - step)
                                }
                            }
                        }
                    }

                    // ---- Network pill (WiFi + Bluetooth side-by-side) ----
                    Pill {
                        id: networkBtn
                        innerSpacing: 6

                        Text {
                            id: wifiIcon
                            text: root.wifiConnected !== null
                                ? root.wifiSignalIcon(root.wifiConnected.signalStrength)
                                : "\uDB82\uDD2F"  // wifi-strength-alert (U+F092F)
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: bar.networkPopupOpen && root.networkActiveTab === "wifi" ? root.accentYellow
                                 : root.wifiConnected !== null ? root.accentGreen
                                 : root.wifiPower === "on" ? root.accentBlue
                                 : root.mutedColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (bar.networkPopupOpen && root.networkActiveTab === "wifi") {
                                        bar.networkPopupOpen = false
                                    } else {
                                        root.networkActiveTab = "wifi"
                                        bar.networkPopupOpen = true
                                    }
                                }
                            }
                        }

                        Text {
                            id: btIcon
                            text: root.bluetoothPower === "on" ? "\uF294" : "\uF293"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: bar.networkPopupOpen && root.networkActiveTab === "bt" ? root.accentYellow
                                 : root.bluetoothConnected.length > 0 ? root.accentGreen
                                 : root.bluetoothPower === "on" ? root.accentBlue
                                 : root.mutedColor
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (bar.networkPopupOpen && root.networkActiveTab === "bt") {
                                        bar.networkPopupOpen = false
                                    } else {
                                        root.networkActiveTab = "bt"
                                        bar.networkPopupOpen = true
                                    }
                                }
                            }
                        }
                    }

                    // ---- Mail pill (Proton Mail) ----
                    Pill {
                        Item {
                            Layout.preferredWidth: mailIcon.width
                            Layout.preferredHeight: mailIcon.height

                            Text {
                                id: mailIcon
                                // Open envelope when visible, closed when minimized/off
                                text: root.mailRunning && !root.mailMinimized
                                    ? "\uF2B6"   // nf-fa-envelope_open
                                    : "\uF0E0"   // nf-fa-envelope
                                font.pixelSize: root.fontSize
                                font.family: root.fontFamily
                                color: root.mailUnread > 0 ? root.accentRed
                                     : root.mailRunning ? root.protonPurple
                                     : root.mutedColor
                            }

                            // Unread dot badge
                            Rectangle {
                                visible: root.mailUnread > 0
                                width: 7; height: 7; radius: 3.5
                                color: root.accentRed
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -2
                                anchors.rightMargin: -2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mailToggleProc.running = true
                            }
                        }
                        Text {
                            visible: root.mailUnread > 0
                            text: root.mailUnread.toString()
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: root.accentRed
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mailToggleProc.running = true
                            }
                        }
                    }

                    // ---- Obsidian pill ----
                    Pill {
                        color: root.obsRunning && !root.obsMinimized
                            ? Qt.rgba(root.obsidianPurple.r, root.obsidianPurple.g, root.obsidianPurple.b, 0.55)
                            : root.pillColor
                        Image {
                            id: obsIcon
                            source: "obsidian-logo.svg"
                            sourceSize: Qt.size(root.fontSize, root.fontSize)
                            opacity: root.obsRunning
                                ? (root.obsMinimized ? 0.6 : 1.0)
                                : 0.4
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: obsToggleProc.running = true
                            }
                        }
                    }

                    // ---- Claude provider pill (Anthropic / ZLM) ----
                    Pill {
                        Text {
                            text: root.claudeLabel
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            font.bold: true
                            color: root.claudeProvider === "zlm" ? root.accentOrange : root.accentTeal
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.claudeProvider === "zlm") {
                                        root.claudeProvider = "anthropic"
                                        root.claudeLabel = "API"
                                    } else {
                                        root.claudeProvider = "zlm"
                                        root.claudeLabel = "ZLM"
                                    }
                                    claudeToggleProc.running = true
                                }
                            }
                        }
                    }

                    // ---- Dockur Windows disconnect/shutdown pill (right-click) ----
                    Pill {
                        Text {
                            id: dockurButton
                            text: "󰍲"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: dockurPopup.busy
                                ? root.accentYellow : root.accentBlue

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton)
                                        dockurPopup.toggleConfirmation()
                                }
                            }
                        }
                    }

                    // ---- Screenshot pill ----
                    Pill {
                        Text {
                            id: screenshotBtn
                            text: "\uF030"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: root.accentTeal
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: screenshotProc.running = true
                            }
                        }
                    }

                    // ---- Notification bell pill ----
                    Pill {
                        Item {
                            Layout.preferredWidth: notifBellText.width
                            Layout.preferredHeight: notifBellText.height

                            Text {
                                id: notifBellText
                                text: root.dndEnabled ? "\uF1F6"   // fa-bell-slash
                                    : root.notifCount > 0 ? "\uF0F3" // fa-bell (active)
                                    : "\uF0A2"                       // fa-bell-o (empty)
                                font.pixelSize: root.fontSize
                                font.family: root.fontFamily
                                color: root.notifCount > 0 ? root.accentYellow : root.mutedColor
                            }

                            // Unread dot
                            Rectangle {
                                visible: root.notifCount > 0 && !root.dndEnabled
                                width: 7; height: 7; radius: 3.5
                                color: root.accentRed
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -2
                                anchors.rightMargin: -2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notifToggleProc.running = true
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------
            // Weather forecast popup (native 5-day forecast)
            // -------------------------------------------------------
            LazyLoader {
                id: weatherPopupLoader
                active: bar.weatherPopupOpen

                PopupWindow {
                    id: weatherPopup
                    visible: bar.weatherPopupOpen
                grabFocus: true

                anchor.window: bar
                anchor.item: weatherBtn
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                anchor.adjustment: PopupAdjustment.Slide

                implicitWidth: weatherPopupContent.width
                implicitHeight: weatherPopupContent.height

                color: root.bgColor

                Rectangle {
                    id: weatherPopupContent
                    width: 392
                    height: forecastColumn.implicitHeight + 24
                    color: root.bgColor
                    border.color: root.mutedColor
                    border.width: 1
                    radius: 6

                    Column {
                        id: forecastColumn
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 8

                        // ── Day selector tabs ──
                        Row {
                            spacing: 4

                            Repeater {
                                model: root.weatherForecast

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: 72; height: 52
                                    radius: 4
                                    color: index === root.weatherSelectedDay
                                           ? root.mutedColor : "transparent"

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            text: modelData.day || ""
                                            color: root.fgColor
                                            font.pixelSize: 13
                                            font.family: root.fontFamily
                                            font.bold: index === root.weatherSelectedDay
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: modelData.icon || ""
                                            font.pixelSize: 20
                                            font.family: root.fontFamily
                                            color: modelData.hex || root.fgColor
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: Math.round(modelData.max) + "\u00B0/" +
                                                  Math.round(modelData.min) + "\u00B0"
                                            color: root.fgColor
                                            font.pixelSize: 12
                                            font.family: root.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.weatherSelectedDay = index
                                    }
                                }
                            }
                        }

                        // ── Divider ──
                        Rectangle {
                            width: parent.width; height: 1
                            color: root.mutedColor
                        }

                        // ── Selected day detail ──
                        Column {
                            spacing: 4
                            visible: root.weatherForecast.length > 0

                            property var day: root.weatherForecast[root.weatherSelectedDay] || {}

                            Text {
                                text: (parent.day.day || "") + "  " + (parent.day.date || "")
                                color: root.fgColor
                                font.pixelSize: 15
                                font.family: root.fontFamily
                                font.bold: true
                            }

                            Row {
                                spacing: 16
                                Text {
                                    text: "\uE37D " + Math.round(parent.parent.day.wind || 0) + " km/h"
                                    color: root.fgColor
                                    font.pixelSize: 13; font.family: root.fontFamily
                                }
                                Text {
                                    text: "\uE373 " + Math.round(parent.parent.day.humidity || 0) + "%"
                                    color: root.fgColor
                                    font.pixelSize: 13; font.family: root.fontFamily
                                }
                                Text {
                                    text: "\uE371 " + Math.round(parent.parent.day.pop || 0) + "%"
                                    color: root.fgColor
                                    font.pixelSize: 13; font.family: root.fontFamily
                                }
                            }
                        }

                        // ── Divider ──
                        Rectangle {
                            width: parent.width; height: 1
                            color: root.mutedColor
                        }

                        // ── Hourly forecast (scrollable) ──
                        Flickable {
                            width: parent.width
                            height: 64
                            contentWidth: hourlyRow.implicitWidth
                            clip: true

                            Row {
                                id: hourlyRow
                                spacing: 6

                                Repeater {
                                    model: (root.weatherForecast[root.weatherSelectedDay] || {}).hourly || []

                                    delegate: Column {
                                        required property var modelData
                                        width: 44
                                        spacing: 1

                                        Text {
                                            text: modelData.time || ""
                                            color: root.mutedColor
                                            font.pixelSize: 11; font.family: root.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: modelData.icon || ""
                                            font.pixelSize: 18; font.family: root.fontFamily
                                            color: modelData.hex || root.fgColor
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: Math.round(modelData.temp) + "\u00B0"
                                            color: root.fgColor
                                            font.pixelSize: 12; font.family: root.fontFamily
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }

                        // ── Error / loading fallback ──
                        Text {
                            visible: root.weatherForecast.length === 0
                            text: root.weatherError || "Loading forecast\u2026"
                            color: root.fgColor
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                        }
                    }
                }
                }
            }

            // -------------------------------------------------------
            // System monitor popup (top processes by CPU / RAM)
            // -------------------------------------------------------
            LazyLoader {
                id: sysMonPopupLoader
                active: bar.sysMonOpen

                SysMonPopup {
                    id: sysMonPopup
                    visible: bar.sysMonOpen
                    anchorWindow: bar
                    anchorItem: cpuText

                    Binding {
                        target: sysMonPopup
                        property: "activeTab"
                        value: bar.sysMonTab
                    }
                    onActiveTabChanged: bar.sysMonTab = activeTab

                    bgColor: root.bgColor
                    fgColor: root.fgColor
                    mutedColor: root.mutedColor
                    accentBlue: root.accentBlue
                    accentTeal: root.accentTeal
                    accentYellow: root.accentYellow
                    accentRed: root.accentRed
                    fontFamily: root.fontFamily
                    fontSize: root.fontSize
                }
            }

            // -------------------------------------------------------
            // Network popup (WiFi + Bluetooth)
            // -------------------------------------------------------
            LazyLoader {
                id: networkPopupLoader
                active: bar.networkPopupOpen

                NetworkPopup {
                    id: networkPopup
                    visible: bar.networkPopupOpen
                    anchorWindow: bar
                    anchorItem: networkBtn

                // Managed binding survives imperative assignments inside the
                // popup (tab MouseAreas write popup.activeTab directly).
                    Binding {
                        target: networkPopup
                        property: "activeTab"
                        value: root.networkActiveTab
                    }
                    onActiveTabChanged: root.networkActiveTab = activeTab

                    bgColor: root.bgColor
                    fgColor: root.fgColor
                    mutedColor: root.mutedColor
                    accentBlue: root.accentBlue
                    accentLavender: root.accentLavender
                    accentGreen: root.accentGreen
                    accentYellow: root.accentYellow
                    accentRed: root.accentRed
                    accentTeal: root.accentTeal
                    fontFamily: root.fontFamily
                    fontSize: root.fontSize
                }
            }

            // -------------------------------------------------------
            // Audio mixer popup (master + sinks + per-app streams)
            // -------------------------------------------------------
            LazyLoader {
                id: audioPopupLoader
                active: bar.audioPopupOpen

                AudioMixerPopup {
                    id: audioMixerPopup
                    visible: bar.audioPopupOpen
                    anchorWindow: bar
                    anchorItem: speakerIcon

                    bgColor: root.bgColor
                    fgColor: root.fgColor
                    mutedColor: root.mutedColor
                    accentGreen: root.accentGreen
                    accentLavender: root.accentLavender
                    accentRed: root.accentRed
                    accentYellow: root.accentYellow
                    fontFamily: root.fontFamily
                    fontSize: root.fontSize
                }
            }

            // -------------------------------------------------------
            // Music popup (MPRIS media controls)
            // -------------------------------------------------------
            LazyLoader {
                id: musicPopupLoader
                active: bar.musicPopupOpen

                MusicPopup {
                    id: musicPopup
                    visible: bar.musicPopupOpen
                    anchorWindow: bar
                    anchorItem: musicIcon

                    bgColor: root.bgColor
                    fgColor: root.fgColor
                    mutedColor: root.mutedColor
                    accentGreen: root.accentGreen
                    accentYellow: root.accentYellow
                    accentOrange: root.accentOrange
                    fontFamily: root.fontFamily
                    fontSize: root.fontSize
                }
            }

            // -------------------------------------------------------
            // Dockur Windows shutdown confirmation
            // -------------------------------------------------------
            DockurPopup {
                id: dockurPopup
                anchorWindow: bar
                anchorItem: dockurButton

                bgColor: root.bgColor
                fgColor: root.fgColor
                mutedColor: root.mutedColor
                accentRed: root.accentRed
                accentBlue: root.accentBlue
                accentYellow: root.accentYellow
                fontFamily: root.fontFamily
                fontSize: root.fontSize
            }
        }
    }

    // Gemini sidebar — auto-hide on the left edge of the monitor that
    // owns workspaces 1+2 (DP-3 on hyacinth, the only screen elsewhere).
    GeminiSidebar {
        bgColor: root.bgColor
        borderColor: root.mutedColor
        targetScreen: root.workspaceOneMonitorName
        targetWorkspaceActive: root.workspaceOneActive
    }
}
