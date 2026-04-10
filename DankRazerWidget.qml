import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 400
    popoutHeight: 520

    property string cliPath: pluginService.pluginDirectory + "/dankRazer/dankrazer-cli/dankrazer"

    // Device data
    property var devices: []
    property int selectedDevice: 0
    property bool isLoading: true
    property bool hasError: false
    property string errorText: ""

    // Current device state
    property string deviceName: ""
    property string deviceType: ""
    property real brightness: 0
    property string serial: ""
    property real battery: -1
    property bool isCharging: false

    property int refreshInterval: (pluginData.refreshInterval || 30) * 1000

    // JSON output accumulator
    property string _jsonOutput: ""

    // --- Processes ---

    Process {
        id: listProcess
        command: [root.cliPath, "list", "--json"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                root._jsonOutput += data
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.hasError = true
                root.errorText = "Failed to list devices"
                root.isLoading = false
                root.devices = []
                return
            }
            try {
                var parsed = JSON.parse(root._jsonOutput.trim())
                root.devices = parsed
                root.hasError = false
                if (parsed.length > 0) {
                    var d = parsed[root.selectedDevice] || parsed[0]
                    root.deviceName = d.name || ""
                    root.deviceType = d.type || ""
                    root.brightness = d.brightness || 0
                    root.serial = d.serial || ""
                    root.battery = d.battery || -1
                    root.isCharging = d.is_charging || false
                }
            } catch (e) {
                root.hasError = true
                root.errorText = "Parse error"
            }
            root.isLoading = false
        }
    }

    Process {
        id: brightnessProcess
        property real targetBrightness: 0
        command: [root.cliPath, "brightness", String(targetBrightness)]
        running: false
        onExited: (exitCode, exitStatus) => {
            refresh()
        }
    }

    Process {
        id: effectProcess
        property var effectArgs: []
        command: [root.cliPath, "effect"].concat(effectArgs)
        running: false
        onExited: (exitCode, exitStatus) => {
            refresh()
        }
    }

    // --- Refresh ---

    function refresh() {
        if (listProcess.running) return
        root._jsonOutput = ""
        listProcess.running = true
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // --- Actions ---

    function setBrightness(level) {
        brightnessProcess.targetBrightness = Math.round(level)
        brightnessProcess.running = true
    }

    function setEffect(args) {
        effectProcess.effectArgs = args
        effectProcess.running = true
    }

    // --- Bar Pill ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.deviceType === "mouse" ? "mouse" : root.deviceType === "headset" ? "headset" : "keyboard"
                size: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.hasError ? "No Razer" : (root.devices.length + " device" + (root.devices.length !== 1 ? "s" : ""))
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "keyboard"
                size: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.devices.length.toString()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            headerText: "Razer Devices"
            detailsText: root.deviceName || "No devices"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingL

                // Error state
                StyledText {
                    visible: root.hasError
                    width: parent.width
                    text: root.errorText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Loading state
                StyledText {
                    visible: root.isLoading
                    width: parent.width
                    text: "Loading..."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }

                // Device info section
                Column {
                    visible: !root.hasError && !root.isLoading && root.devices.length > 0
                    width: parent.width
                    spacing: Theme.spacingM

                    // Device name + type
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.deviceType === "mouse" ? "mouse" : root.deviceType === "headset" ? "headset" : "keyboard"
                            size: Theme.fontSizeLarge
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: root.deviceName
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: root.deviceType + " — " + root.serial
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }

                    // Battery (if wireless)
                    Row {
                        visible: root.battery >= 0
                        width: parent.width
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.isCharging ? "battery_charging_full" : root.battery > 50 ? "battery_full" : root.battery > 20 ? "battery_3_bar" : "battery_alert"
                            size: Theme.fontSizeMedium
                            color: root.battery <= 20 ? Theme.error : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: Math.round(root.battery) + "%" + (root.isCharging ? " (charging)" : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Brightness section
                    Rectangle {
                        width: parent.width
                        height: brightnessCol.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surface

                        Column {
                            id: brightnessCol
                            width: parent.width - Theme.spacingM * 2
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width

                                StyledText {
                                    text: "Brightness"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Item { width: parent.width - parent.children[0].width - parent.children[2].width; height: 1 }

                                StyledText {
                                    text: Math.round(brightnessSlider.value) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            DankSlider {
                                id: brightnessSlider
                                width: parent.width
                                minimum: 0
                                maximum: 100
                                value: root.brightness
                                step: 5
                                unit: "%"
                                showValue: false
                                onValueChanged: {
                                    if (!isDragging) return
                                }
                                onIsDraggingChanged: {
                                    if (!isDragging) {
                                        root.setBrightness(value)
                                    }
                                }
                            }
                        }
                    }

                    // Effect buttons
                    Rectangle {
                        width: parent.width
                        height: effectCol.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surface

                        Column {
                            id: effectCol
                            width: parent.width - Theme.spacingM * 2
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            StyledText {
                                text: "Lighting Effect"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            Grid {
                                width: parent.width
                                columns: 3
                                spacing: Theme.spacingS

                                Repeater {
                                    model: [
                                        { label: "Static",    icon: "palette",       args: ["static", pluginData.staticColor || "00ff00"] },
                                        { label: "Breath",    icon: "air",           args: ["breath"] },
                                        { label: "Wave",      icon: "waves",         args: ["wave"] },
                                        { label: "Spectrum",  icon: "looks",         args: ["spectrum"] },
                                        { label: "Reactive",  icon: "touch_app",     args: ["reactive", pluginData.reactiveColor || "00ffff"] },
                                        { label: "Off",       icon: "lightbulb_outline", args: ["none"] }
                                    ]

                                    delegate: Rectangle {
                                        width: (effectCol.width - Theme.spacingS * 2) / 3
                                        height: 56
                                        radius: Theme.cornerRadius
                                        color: effectMouse.containsMouse ? Theme.primary : Theme.surfaceVariant

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 2

                                            DankIcon {
                                                name: modelData.icon
                                                size: Theme.fontSizeMedium
                                                color: effectMouse.containsMouse ? Theme.onPrimary : Theme.surfaceText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            StyledText {
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: effectMouse.containsMouse ? Theme.onPrimary : Theme.surfaceVariantText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: effectMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setEffect(modelData.args)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
