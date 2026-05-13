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

    property string activeTab: "bt"
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
        var networks = wifiDevice.networks.values.filter(function(n) { return !n.connected })
        networks.sort(function(a, b) { return b.signalStrength - a.signalStrength })
        return networks
    }
    readonly property string wifiSsid: wifiConnected !== null ? wifiConnected.name : ""
    readonly property string displayBtPower: btPower
    readonly property string displayWifiPower: wifiPower
    readonly property bool currentPowerOn:
        activeTab === "bt" ? displayBtPower === "on" : displayWifiPower === "on"

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    Binding {
        target: popup.btAdapter
        property: "discovering"
        value: popup.visible && popup.activeTab === "bt" && popup.displayBtPower === "on"
        when: popup.btAdapter !== null
    }

    Binding {
        target: popup.wifiDevice
        property: "scannerEnabled"
        value: popup.visible && popup.activeTab === "wifi" && popup.displayWifiPower === "on"
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

    function signalIcon(signal) {
        if (signal >= 80) return "\uF1EB"
        if (signal >= 60) return "\uF1EB"
        if (signal >= 40) return "\uF1EB"
        if (signal >= 20) return "\uF1EB"
        return "\uF6AC"
    }

    function securityText(security) {
        return WifiSecurityType.toString(security).replace(/([a-z])([A-Z])/g, "$1 $2")
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
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (popup.activeTab === "bt") {
                                if (popup.btAdapter !== null)
                                    popup.btAdapter.enabled = !popup.btAdapter.enabled
                            } else {
                                Networking.wifiEnabled = !Networking.wifiEnabled
                            }
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
                                text: "   Hold to disconnect"
                                font.pixelSize: popup.fontSize - 3
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                font.italic: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressAndHold: modelData.disconnect()
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
                                text: modelData.pairing ? "\u2026" : (modelData.paired ? "Connect" : "Pair")
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
                                if (modelData.pairing) return
                                if (modelData.paired)
                                    modelData.connect()
                                else
                                    modelData.pair()
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
                                parts.push(Math.round(popup.wifiConnected.signalStrength) + "%")
                                parts.push(popup.securityText(popup.wifiConnected.security))
                                return "   " + parts.join(" \u2022 ")
                            }
                            font.pixelSize: popup.fontSize - 2
                            font.family: popup.fontFamily
                            color: popup.fgColor
                        }

                        Text {
                            text: "   Hold to disconnect"
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
                            if (popup.wifiConnected !== null)
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
                                text: Math.round(modelData.signalStrength) + "%"
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
                            onClicked: if (!modelData.stateChanging) modelData.connect()
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
                text: popup.activeTab === "bt" ? "Bluetooth is off" : "WiFi is off"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
                topPadding: 4
            }
        }
    }
}
