import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dankRazer"

    StyledText {
        width: parent.width
        text: "Razer Device Manager"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Control your Razer peripherals via OpenRazer. Requires openrazer-daemon to be running."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to poll device state (seconds)"
        defaultValue: 30
        minimum: 5
        maximum: 120
        unit: "s"
        leftIcon: "schedule"
    }

    StringSetting {
        settingKey: "staticColor"
        label: "Default Static Color"
        description: "Hex color for static effect (e.g. 00ff00)"
        defaultValue: "00ff00"
        leftIcon: "palette"
    }

    StringSetting {
        settingKey: "reactiveColor"
        label: "Default Reactive Color"
        description: "Hex color for reactive effect (e.g. 00ffff)"
        defaultValue: "00ffff"
        leftIcon: "touch_app"
    }

    ToggleSetting {
        settingKey: "syncAll"
        label: "Sync All Devices"
        description: "Apply brightness, effects, and DPI to all connected devices"
        defaultValue: true
        leftIcon: "sync"
    }

    ToggleSetting {
        settingKey: "autoLightsOff"
        label: "Auto Lights Off"
        description: "Turn off device lighting on screen lock, sleep, or monitor off"
        defaultValue: true
        leftIcon: "bedtime"
    }
}
