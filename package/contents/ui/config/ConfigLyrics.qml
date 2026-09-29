import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// How the lyrics look. Where they come from and their machine translation
// are in ConfigServices.qml.
KCM.SimpleKCM {
    id: page

    property real cfg_lyricsFontScale
    property alias cfg_lyricsFade: fade.value
    property string cfg_lyricsBackground
    property alias cfg_lyricsBlur: blur.value

    QQC2.ButtonGroup {
        id: backgroundGroup
    }

    // "mode", as a control already has a background property.
    component BackgroundButton: QQC2.RadioButton {
        required property string mode
        QQC2.ButtonGroup.group: backgroundGroup
        checked: page.cfg_lyricsBackground === mode
        onToggled: {
            if (checked) {
                page.cfg_lyricsBackground = mode;
            }
        }
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }

        BackgroundButton {
            Kirigami.FormData.label: i18n("Background:")
            mode: "cover"
            text: i18n("Blurred cover, text color to suit it")
        }

        BackgroundButton {
            mode: "light"
            text: i18n("Black on white")
        }

        BackgroundButton {
            mode: "dark"
            text: i18n("White on black")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Cover blur:")
            enabled: page.cfg_lyricsBackground === "cover"

            QQC2.Slider {
                id: blur
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                from: 0
                to: 100
                stepSize: 10
            }

            QQC2.Label {
                text: i18nc("percentage", "%1 %", blur.value)
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Text size:")

            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                from: 0.8
                to: 1.6
                stepSize: 0.1
                value: page.cfg_lyricsFontScale
                onMoved: page.cfg_lyricsFontScale = Math.round(value * 10) / 10
            }

            QQC2.Label {
                text: i18nc("percentage", "%1 %", Math.round(page.cfg_lyricsFontScale * 100))
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Fade around the sung line:")

            QQC2.Slider {
                id: fade
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                from: 0
                to: 100
                stepSize: 10
            }

            QQC2.Label {
                text: i18nc("percentage", "%1 %", fade.value)
            }
        }
    }
}
