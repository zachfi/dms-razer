import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 400
    popoutHeight: 600

    property string cliPath: pluginService.pluginDirectory + "/dankRazer/dankrazer-cli/dankrazer"

    // Device data
    property var devices: []
    property int deviceCount: 0
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
    property var supportedEffects: []
    property int dpi: 0
    property int maxDpi: 0
    property int selectedDeviceMaxDpi: 0

    // Color picker state
    property string staticColor: pluginData.staticColor || "00ff00"
    property string reactiveColor: pluginData.reactiveColor || "00ffff"

    // Sync all devices
    property bool syncAll: pluginData.syncAll !== false

    // Auto lights-off state
    property bool autoLightsOff: pluginData.autoLightsOff !== false
    property var _savedState: null
    property bool _isDark: false
    property var _lastEffectArgs: []

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
                root.deviceCount = 0
                return
            }
            try {
                var parsed = JSON.parse(root._jsonOutput.trim())
                root.devices = parsed
                root.deviceCount = parsed.length
                root.hasError = false
                if (parsed.length > 0) {
                    var d = parsed[root.selectedDevice] || parsed[0]
                    root.deviceName = d.name || ""
                    root.deviceType = d.type || ""
                    root.brightness = d.brightness || 0
                    root.serial = d.serial || ""
                    root.battery = d.battery || -1
                    root.isCharging = d.is_charging || false
                    root.supportedEffects = d.effects || []
                    root.selectedDeviceMaxDpi = d.max_dpi || 0
                    // Find best max_dpi across all devices (for when syncAll is on and selected device isn't a mouse)
                    var bestMaxDpi = 0
                    var bestDpi = 0
                    for (var i = 0; i < parsed.length; i++) {
                        if ((parsed[i].max_dpi || 0) > bestMaxDpi) {
                            bestMaxDpi = parsed[i].max_dpi
                            bestDpi = (parsed[i].dpi && parsed[i].dpi.length > 0) ? parsed[i].dpi[0] : 0
                        }
                    }
                    root.dpi = root.selectedDeviceMaxDpi > 0 ? ((d.dpi && d.dpi.length > 0) ? d.dpi[0] : 0) : bestDpi
                    root.maxDpi = bestMaxDpi
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
        command: []
        running: false
        onExited: (exitCode, exitStatus) => {
            refresh()
        }
    }

    Process {
        id: effectProcess
        command: []
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
        var cmd = [root.cliPath, "brightness"]
        if (root.syncAll) cmd.push("--all")
        cmd.push(String(Math.round(level)))
        brightnessProcess.command = cmd
        brightnessProcess.running = true
    }

    function setEffect(args) {
        root._lastEffectArgs = args
        var cmd = [root.cliPath, "effect"]
        if (root.syncAll) cmd.push("--all")
        effectProcess.command = cmd.concat(args)
        effectProcess.running = true
    }

    Process {
        id: dpiProcess
        command: []
        running: false
        onExited: (exitCode, exitStatus) => {
            refresh()
        }
    }

    function setDpi(value) {
        var cmd = [root.cliPath, "dpi"]
        if (root.syncAll) cmd.push("--all")
        cmd.push(String(Math.round(value)))
        dpiProcess.command = cmd
        dpiProcess.running = true
    }

    function sliderToDpi(val) {
        if (root.maxDpi <= 0) return 100
        var minLog = Math.log(100)
        var maxLog = Math.log(root.maxDpi)
        var dpi = Math.exp(minLog + (val / 1000) * (maxLog - minLog))
        return Math.round(dpi / 100) * 100
    }

    function dpiToSlider(dpiVal) {
        if (root.maxDpi <= 0 || dpiVal <= 0) return 0
        var minLog = Math.log(100)
        var maxLog = Math.log(root.maxDpi)
        return Math.round((Math.log(dpiVal) - minLog) / (maxLog - minLog) * 1000)
    }

    function hasEffect(name) {
        return root.supportedEffects.indexOf(name) !== -1
    }

    // --- Color Picker ---

    property string _pendingColorEffect: ""

    function colorToHex(c) {
        var r = Math.round(c.r * 255)
        var g = Math.round(c.g * 255)
        var b = Math.round(c.b * 255)
        return ("0" + r.toString(16)).slice(-2) + ("0" + g.toString(16)).slice(-2) + ("0" + b.toString(16)).slice(-2)
    }

    function openColorPicker(effectType) {
        var picker = PopoutService.colorPickerModal
        if (!picker) return
        root._pendingColorEffect = effectType
        var currentHex = effectType === "static" ? root.staticColor : root.reactiveColor
        picker.selectedColor = Qt.color("#" + currentHex)
        picker.pickerTitle = effectType === "static" ? "Static Effect Color" : "Reactive Effect Color"
        picker.onColorSelectedCallback = function() {}
        picker.show()
    }

    Connections {
        target: PopoutService.colorPickerModal || null
        enabled: root._pendingColorEffect !== ""

        function onColorSelected(selectedColor) {
            var hex = root.colorToHex(selectedColor)
            if (root._pendingColorEffect === "static") {
                root.staticColor = hex
                root.setEffect(["static", hex])
            } else if (root._pendingColorEffect === "reactive") {
                root.reactiveColor = hex
                root.setEffect(["reactive", hex])
            }
            root._pendingColorEffect = ""
        }
    }

    // --- Auto Lights Off ---

    Process {
        id: darkProcess
        command: []
        running: false
    }

    function saveAndDark() {
        if (root._isDark) return
        root._savedState = {
            brightness: root.brightness,
            lastEffectArgs: root._lastEffectArgs
        }
        root._isDark = true
        darkProcess.command = [root.cliPath, "effect", "--all", "static", "000000"]
        darkProcess.running = true
    }

    Process {
        id: restoreProcess
        command: []
        running: false
        onExited: (exitCode, exitStatus) => {
            refresh()
        }
    }

    function restoreState() {
        if (!root._isDark || !root._savedState) return
        root._isDark = false
        if (root._savedState.brightness > 0) {
            root.setBrightness(root._savedState.brightness)
        }
        // Use OpenRazer's restoreLastEffect which remembers the device's previous state
        Qt.callLater(function() {
            restoreProcess.command = [root.cliPath, "effect", "--all", "restore"]
            restoreProcess.running = true
            root._savedState = null
        })
    }

    Connections {
        target: SessionService

        function onPreparingForSleepChanged() {
            if (SessionService.preparingForSleep) {
                root.saveAndDark()
            } else if (root._isDark) {
                root.restoreState()
            }
        }

        function onSessionLocked() {
            if (root.autoLightsOff) root.saveAndDark()
        }

        function onSessionUnlocked() {
            root.restoreState()
        }
    }

    Connections {
        target: IdleService

        function onRequestMonitorOff() {
            if (root.autoLightsOff) root.saveAndDark()
        }

        function onRequestMonitorOn() {
            root.restoreState()
        }
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
                text: root.hasError ? "No Razer" : (root.deviceCount + " device" + (root.deviceCount !== 1 ? "s" : ""))
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
                text: root.deviceCount.toString()
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

            Component.onCompleted: root.refresh()

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
                    visible: !root.hasError && !root.isLoading && root.deviceCount > 0
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

                    // Sync all toggle
                    DankToggle {
                        visible: root.deviceCount > 1
                        width: parent.width
                        text: "Sync All Devices"
                        description: "Apply changes to all connected devices"
                        checked: root.syncAll
                        onToggled: (value) => {
                            root.syncAll = value
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

                    // DPI section
                    Rectangle {
                        visible: root.maxDpi > 0 && (root.syncAll || root.selectedDeviceMaxDpi > 0)
                        width: parent.width
                        height: dpiCol.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surface

                        Column {
                            id: dpiCol
                            width: parent.width - Theme.spacingM * 2
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width

                                StyledText {
                                    text: "DPI"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                Item { width: parent.width - parent.children[0].width - parent.children[2].width; height: 1 }

                                Row {
                                    spacing: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: Theme.cornerRadius
                                        color: dpiMinusArea.containsMouse ? Theme.primary : Theme.surfaceVariant
                                        anchors.verticalCenter: parent.verticalCenter

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "remove"
                                            size: 14
                                            color: dpiMinusArea.containsMouse ? Theme.onPrimary : Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: dpiMinusArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var currentDpi = root.sliderToDpi(dpiSlider.value)
                                                var step = currentDpi <= 800 ? 100 : currentDpi <= 3200 ? 200 : 400
                                                var newDpi = Math.max(100, currentDpi - step)
                                                dpiSlider.value = root.dpiToSlider(newDpi)
                                                root.setDpi(newDpi)
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: root.sliderToDpi(dpiSlider.value)
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: Theme.cornerRadius
                                        color: dpiPlusArea.containsMouse ? Theme.primary : Theme.surfaceVariant
                                        anchors.verticalCenter: parent.verticalCenter

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "add"
                                            size: 14
                                            color: dpiPlusArea.containsMouse ? Theme.onPrimary : Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: dpiPlusArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var currentDpi = root.sliderToDpi(dpiSlider.value)
                                                var step = currentDpi < 800 ? 100 : currentDpi < 3200 ? 200 : 400
                                                var newDpi = Math.min(root.maxDpi, currentDpi + step)
                                                dpiSlider.value = root.dpiToSlider(newDpi)
                                                root.setDpi(newDpi)
                                            }
                                        }
                                    }
                                }
                            }

                            DankSlider {
                                id: dpiSlider
                                width: parent.width
                                minimum: 0
                                maximum: 1000
                                value: root.dpiToSlider(root.dpi)
                                step: 1
                                showValue: false
                                onIsDraggingChanged: {
                                    if (!isDragging) {
                                        root.setDpi(root.sliderToDpi(value))
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
                                        { label: "Static",    icon: "palette",           picker: true,  effectType: "static",   requires: "static" },
                                        { label: "Breath",    icon: "air",               picker: false, args: ["breath"],       requires: "breath" },
                                        { label: "Wave",      icon: "waves",             picker: false, args: ["wave"],         requires: "wave" },
                                        { label: "Spectrum",  icon: "looks",             picker: false, args: ["spectrum"],      requires: "spectrum" },
                                        { label: "Reactive",  icon: "touch_app",         picker: true,  effectType: "reactive", requires: "reactive" },
                                        { label: "Off",       icon: "lightbulb_outline", picker: false, args: ["static", "000000"], requires: "static" }
                                    ]

                                    delegate: Rectangle {
                                        visible: root.hasEffect(modelData.requires)
                                        width: visible ? (effectCol.width - Theme.spacingS * 2) / 3 : 0
                                        height: visible ? 56 : 0
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

                                            Rectangle {
                                                visible: modelData.picker || false
                                                width: 12
                                                height: 12
                                                radius: 6
                                                color: "#" + (modelData.effectType === "static" ? root.staticColor : root.reactiveColor)
                                                border.color: effectMouse.containsMouse ? Theme.onPrimary : Theme.surfaceText
                                                border.width: 1
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: effectMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.picker) {
                                                    root.openColorPicker(modelData.effectType)
                                                } else {
                                                    root.setEffect(modelData.args)
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
    }
}
