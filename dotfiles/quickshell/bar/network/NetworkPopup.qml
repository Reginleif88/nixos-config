import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth

// Network management popup with WiFi + Bluetooth tabs.
// State comes from Quickshell's native NetworkManager and BlueZ bindings.

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
    required property color accentBlue
    required property color accentLavender
    required property color accentGreen
    required property color accentYellow
    required property color accentRed
    required property color accentTeal
    required property string fontFamily
    required property int fontSize

    property string activeTab: "wifi"
    readonly property color activeAccent: popup.accentBlue

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var wifiDevice: {
        var devices = Networking.devices.values
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        }
        return null
    }

    readonly property string btPower: btAdapter !== null && btAdapter.enabled ? "on" : "off"
    readonly property string wifiPower: Networking.wifiEnabled ? "on" : "off"
    readonly property var btConnected: sortedDevices(function(d) { return d.connected })
    readonly property var btDevices: sortedDevices(function(d) { return !d.connected })
    readonly property string btConnName: btConnected.length > 0 ? deviceDisplayName(btConnected[0]) : ""
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
    readonly property var wifiNetworks: {
        if (wifiDevice === null)
            return []
        var networks = wifiDevice.networks.values.filter(function(n) {
            return !n.connected && n.name && n.name.length > 0
        })
        networks.sort(function(a, b) { return b.signalStrength - a.signalStrength })
        return networks
    }
    readonly property string wifiSsid: wifiConnected !== null ? wifiConnected.name : ""
    readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled
    readonly property bool currentPowerOn:
        activeTab === "bt" ? btPower === "on" : wifiPower === "on"
    readonly property bool powerToggleAllowed:
        activeTab === "bt" ? btAdapter !== null
                           : (wifiDevice !== null && wifiHardwareEnabled)
    property var wifiPasswordNetwork: null
    property string wifiPasswordSsid: ""
    property string wifiPassword: ""
    property string wifiStatus: ""

    onWifiConnectedChanged: {
        if (popup.wifiConnected !== null && popup.wifiPasswordSsid !== "" &&
                popup.wifiConnected.name === popup.wifiPasswordSsid)
            popup.clearWifiPrompt()
    }

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    Binding {
        target: popup.btAdapter
        property: "discovering"
        value: popup.visible && popup.activeTab === "bt" && popup.btPower === "on"
        when: popup.btAdapter !== null
    }

    Binding {
        target: popup.wifiDevice
        property: "scannerEnabled"
        value: popup.visible && popup.activeTab === "wifi" && popup.wifiPower === "on"
        when: popup.wifiDevice !== null
    }

    function sortedDevices(predicate) {
        if (popup.btAdapter === null)
            return []
        var devices = popup.btAdapter.devices.values.filter(predicate)
        devices.sort(function(a, b) {
            return popup.deviceDisplayName(a).localeCompare(popup.deviceDisplayName(b))
        })
        return devices
    }

    function deviceDisplayName(device) {
        return device ? (device.name || device.deviceName || device.address) : ""
    }

    function bluetoothBusy(device) {
        return device && (device.pairing ||
            device.state === BluetoothDeviceState.Connecting ||
            device.state === BluetoothDeviceState.Disconnecting)
    }

    function bluetoothActionText(device) {
        if (!device)
            return ""
        if (device.pairing || device.state === BluetoothDeviceState.Connecting)
            return "Cancel"
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "\u2026"
        return device.paired ? "Connect" : "Pair"
    }

    function bluetoothConnectedHint(device) {
        if (!device)
            return ""
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "   Disconnecting..."
        if (device.state === BluetoothDeviceState.Connecting)
            return "   Connecting..."
        return "   Hold to disconnect"
    }

    function btIcon(iconName) {
        if (iconName === "audio-headphones" || iconName === "audio-headset")
            return "\uF025"
        if (iconName === "input-mouse")
            return "\uF8CC"
        if (iconName === "input-keyboard")
            return "\uF11C"
        if (iconName === "phone")
            return "\uF10B"
        if (iconName === "computer")
            return "\uF109"
        return "\uF294"
    }

    function wifiSignalPercent(signal) {
        var value = Number(signal)
        if (!isFinite(value))
            return 0
        if (value <= 1)
            value *= 100
        return Math.max(0, Math.min(100, value))
    }

    function signalIcon(signal) {
        var pct = popup.wifiSignalPercent(signal)
        if (pct >= 80) return "\uDB82\uDD28"   // wifi-strength-4 (U+F0928)
        if (pct >= 60) return "\uDB82\uDD25"   // wifi-strength-3 (U+F0925)
        if (pct >= 40) return "\uDB82\uDD22"   // wifi-strength-2 (U+F0922)
        if (pct >= 20) return "\uDB82\uDD1F"   // wifi-strength-1 (U+F091F)
        return "\uDB82\uDD2F"                  // wifi-strength-alert (U+F092F)
    }

    function securityText(security) {
        if (security === undefined || security === null)
            return ""
        return WifiSecurityType.toString(security).replace(/([a-z])([A-Z])/g, "$1 $2")
    }

    function wifiUsesPassword(security) {
        return security === WifiSecurityType.WpaPsk ||
               security === WifiSecurityType.Wpa2Psk ||
               security === WifiSecurityType.Sae
    }

    function clearWifiPrompt() {
        popup.wifiPasswordNetwork = null
        popup.wifiPasswordSsid = ""
        popup.wifiPassword = ""
        popup.wifiStatus = ""
    }

    function requestWifiPassword(network, status) {
        popup.wifiPasswordNetwork = network
        popup.wifiPasswordSsid = network ? network.name : ""
        popup.wifiPassword = ""
        popup.wifiStatus = status || "Password required"
        Qt.callLater(function() {
            if (wifiPasswordField.visible)
                wifiPasswordField.forceActiveFocus()
        })
    }

    function connectWifi(network) {
        if (!network || network.stateChanging)
            return
        if (popup.wifiUsesPassword(network.security) && !network.known) {
            popup.requestWifiPassword(network, "Password required")
            return
        }
        popup.clearWifiPrompt()
        network.connect()
    }

    function submitWifiPassword() {
        if (!popup.wifiPasswordNetwork || popup.wifiPasswordNetwork.stateChanging ||
                popup.wifiPassword.length === 0)
            return
        popup.wifiStatus = "Connecting..."
        popup.wifiPasswordNetwork.connectWithPsk(popup.wifiPassword)
    }

    function handleWifiFailure(network, reason) {
        var status = ConnectionFailReason.toString(reason)
        if (popup.wifiUsesPassword(network.security)) {
            popup.requestWifiPassword(network, status)
        } else {
            popup.wifiPasswordNetwork = null
            popup.wifiPasswordSsid = ""
            popup.wifiPassword = ""
            popup.wifiStatus = status
        }
    }

    function powerOffText() {
        if (popup.activeTab === "bt" && popup.btAdapter === null)
            return "No Bluetooth adapter"
        if (popup.activeTab === "wifi" && popup.wifiDevice === null)
            return "No WiFi adapter"
        if (popup.activeTab === "wifi" && !popup.wifiHardwareEnabled)
            return "WiFi hardware switch is off"
        return popup.activeTab === "bt" ? "Bluetooth is off" : "WiFi is off"
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

            Row {
                spacing: 4
                width: parent.width

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "wifi"
                           ? Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uF1EB  WiFi"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "wifi"
                        color: popup.activeTab === "wifi" ? popup.accentBlue : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "wifi"
                    }
                }

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "bt"
                           ? Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uF294  Bluetooth"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "bt"
                        color: popup.activeTab === "bt" ? popup.accentBlue : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "bt"
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            RowLayout {
                width: parent.width
                spacing: 8

                Text {
                    text: "\u23FB  Power"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.fgColor
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true; height: 1 }

                Rectangle {
                    width: 44; height: 22
                    radius: 11
                    Layout.alignment: Qt.AlignVCenter
                    color: popup.currentPowerOn
                           ? Qt.rgba(popup.activeAccent.r, popup.activeAccent.g, popup.activeAccent.b, 0.3)
                           : popup.mutedColor

                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        y: 3
                        x: popup.currentPowerOn ? 25 : 3
                        color: popup.currentPowerOn ? popup.activeAccent : popup.fgColor

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: popup.powerToggleAllowed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!popup.powerToggleAllowed) return
                            if (popup.activeTab === "bt")
                                popup.btAdapter.enabled = !popup.btAdapter.enabled
                            else
                                Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }
                }

                Text {
                    text: popup.currentPowerOn ? "on" : "off"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    color: popup.currentPowerOn ? popup.activeAccent : popup.mutedColor
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
                visible: popup.currentPowerOn
            }

            Column {
                visible: popup.activeTab === "bt" && popup.currentPowerOn
                width: parent.width
                spacing: 6

                Text {
                    visible: popup.btConnected.length > 0
                    text: "CONNECTED"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }

                Repeater {
                    model: popup.btConnected

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: btConnCol.height + 12
                        radius: 4
                        color: Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.1)

                        Column {
                            id: btConnCol
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: 8
                            }
                            spacing: 2

                            Text {
                                text: popup.btIcon(modelData.icon) + "  " + popup.deviceDisplayName(modelData)
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentBlue
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                visible: modelData.batteryAvailable
                                text: "   " + Math.round(modelData.battery * 100) + "%"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.fgColor
                            }

                            Text {
                                text: popup.bluetoothConnectedHint(modelData)
                                font.pixelSize: popup.fontSize - 3
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                font.italic: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressAndHold: {
                                if (!popup.bluetoothBusy(modelData))
                                    modelData.disconnect()
                            }
                        }
                    }
                }

                Text {
                    visible: popup.btDevices.length > 0
                    text: "AVAILABLE DEVICES"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    topPadding: 4
                }

                Repeater {
                    model: popup.btDevices

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 32
                        radius: 4
                        color: btDevMouse.containsMouse
                               ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                               : "transparent"

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 8

                            Text {
                                text: popup.btIcon(modelData.icon) + "  " + popup.deviceDisplayName(modelData)
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                elide: Text.ElideRight
                                width: parent.width - actionBtn.width - 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: actionBtn
                                text: popup.bluetoothActionText(modelData)
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentBlue
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: btDevMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                if (popup.bluetoothBusy(modelData)) return
                                if (modelData.paired)
                                    modelData.connect()
                                else
                                    modelData.pair()
                            }
                            onPressAndHold: {
                                if (!popup.bluetoothBusy(modelData)) return
                                if (typeof modelData.cancelPairing === "function")
                                    modelData.cancelPairing()
                                else
                                    modelData.disconnect()
                            }
                        }
                    }
                }

                Text {
                    visible: popup.btConnected.length === 0 && popup.btDevices.length === 0
                    text: popup.btAdapter === null ? "No Bluetooth adapter" : "No devices found"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }
            }

            Column {
                visible: popup.activeTab === "wifi" && popup.currentPowerOn
                width: parent.width
                spacing: 6

                Text {
                    visible: popup.wifiConnected !== null
                    text: "CONNECTED"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }

                Rectangle {
                    visible: popup.wifiConnected !== null
                    width: parent.width
                    height: wifiConnCol.height + 12
                    radius: 4
                    color: Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.1)

                    Column {
                        id: wifiConnCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 8
                        }
                        spacing: 2

                        Text {
                            text: (popup.wifiConnected ? popup.signalIcon(popup.wifiConnected.signalStrength) : "") + "  " +
                                  (popup.wifiConnected ? popup.wifiConnected.name : "")
                            font.pixelSize: popup.fontSize
                            font.family: popup.fontFamily
                            font.bold: true
                            color: popup.accentBlue
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: {
                                if (!popup.wifiConnected) return ""
                                var parts = []
                                parts.push(Math.round(popup.wifiSignalPercent(popup.wifiConnected.signalStrength)) + "%")
                                parts.push(popup.securityText(popup.wifiConnected.security))
                                return "   " + parts.join(" \u2022 ")
                            }
                            font.pixelSize: popup.fontSize - 2
                            font.family: popup.fontFamily
                            color: popup.fgColor
                        }

                        Text {
                            text: popup.wifiConnected && popup.wifiConnected.stateChanging
                                  ? "   Disconnecting..."
                                  : "   Hold to disconnect"
                            font.pixelSize: popup.fontSize - 3
                            font.family: popup.fontFamily
                            color: popup.mutedColor
                            font.italic: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressAndHold: {
                            if (popup.wifiConnected !== null && !popup.wifiConnected.stateChanging)
                                popup.wifiConnected.disconnect()
                        }
                    }
                }

                Text {
                    visible: popup.wifiNetworks.length > 0
                    text: "AVAILABLE NETWORKS"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    topPadding: 4
                }

                Rectangle {
                    visible: popup.wifiPasswordNetwork !== null
                    width: parent.width
                    height: wifiPasswordCol.height + 12
                    radius: 4
                    color: Qt.rgba(popup.accentYellow.r, popup.accentYellow.g, popup.accentYellow.b, 0.1)
                    border.color: Qt.rgba(popup.accentYellow.r, popup.accentYellow.g, popup.accentYellow.b, 0.45)
                    border.width: 1

                    Column {
                        id: wifiPasswordCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 8
                        }
                        spacing: 6

                        Text {
                            text: (popup.wifiPasswordSsid !== "" ? popup.wifiPasswordSsid : "Network") +
                                  " - " + popup.wifiStatus
                            font.pixelSize: popup.fontSize - 2
                            font.family: popup.fontFamily
                            color: popup.fgColor
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Rectangle {
                            width: parent.width
                            height: 26
                            radius: 4
                            color: Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                            border.color: popup.mutedColor
                            border.width: 1

                            TextInput {
                                id: wifiPasswordField
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    margins: 8
                                }
                                text: popup.wifiPassword
                                echoMode: TextInput.Password
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                selectionColor: popup.accentBlue
                                selectedTextColor: popup.bgColor
                                clip: true
                                onTextChanged: popup.wifiPassword = text
                                Keys.onReturnPressed: popup.submitWifiPassword()
                                Keys.onEscapePressed: popup.clearWifiPrompt()
                            }
                        }

                        Row {
                            spacing: 8
                            anchors.right: parent.right

                            Text {
                                text: "Cancel"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.mutedColor

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.clearWifiPrompt()
                                }
                            }

                            Text {
                                text: popup.wifiPasswordNetwork && popup.wifiPasswordNetwork.stateChanging ? "\u2026" : "Connect"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.wifiPassword.length > 0 ? popup.accentBlue : popup.mutedColor

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: popup.wifiPassword.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: popup.submitWifiPassword()
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: popup.wifiStatus !== "" && popup.wifiPasswordNetwork === null
                    text: popup.wifiStatus
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    color: popup.accentRed
                    elide: Text.ElideRight
                    width: parent.width
                }

                Repeater {
                    model: popup.wifiNetworks

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 32
                        radius: 4
                        color: wifiDevMouse.containsMouse
                               ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                               : "transparent"

                        Connections {
                            target: modelData

                            function onConnectionFailed(reason) {
                                popup.handleWifiFailure(modelData, reason)
                            }

                            function onStateChanged() {
                                if (modelData.state === ConnectionState.Connecting)
                                    popup.wifiStatus = ""
                                if (modelData.connected && popup.wifiPasswordNetwork === modelData)
                                    popup.clearWifiPrompt()
                            }
                        }

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 8

                            Text {
                                text: popup.signalIcon(modelData.signalStrength) + "  " + modelData.name
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                elide: Text.ElideRight
                                width: parent.width - wifiActionBtn.width - wifiSigText.width - 24
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: wifiSigText
                                text: Math.round(popup.wifiSignalPercent(modelData.signalStrength)) + "%"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: wifiActionBtn
                                text: modelData.stateChanging ? "\u2026" : "Connect"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentBlue
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: wifiDevMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: popup.connectWifi(modelData)
                        }
                    }
                }

                Text {
                    visible: popup.wifiConnected === null && popup.wifiNetworks.length === 0
                    text: popup.wifiDevice === null ? "No WiFi adapter" : "No networks found"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }
            }

            Text {
                visible: !popup.currentPowerOn
                text: popup.powerOffText()
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
                topPadding: 4
            }
        }
    }
}
