import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes

import "../../code/deezer.js" as Deezer

KCM.SimpleKCM {
    id: page

    property string cfg_deezerLanguage
    property alias cfg_wheelStep: wheelStep.value
    property alias cfg_invertWheel: invertWheel.checked
    property string cfg_panelIcon
    property string cfg_panelIconCustom

    // The site's languages under their own names; "" follows the system.
    readonly property var languageNames: ({
            fr: "Français", en: "English", de: "Deutsch", es: "Español", it: "Italiano",
            pt: "Português", br: "Português (Brasil)", nl: "Nederlands", pl: "Polski",
            ru: "Русский", tr: "Türkçe", sv: "Svenska", da: "Dansk", fi: "Suomi",
            ro: "Română", hu: "Magyar", cs: "Čeština", ja: "日本語", ar: "العربية"
        })
    readonly property var languages: [{ code: "", name: i18n("Same as the system") }].concat(
        Deezer.siteLanguages.map(code => ({ code: code, name: languageNames[code] || code })))

    QQC2.ButtonGroup {
        id: panelIconGroup
    }

    component PanelIconButton: QQC2.RadioButton {
        required property string choice
        QQC2.ButtonGroup.group: panelIconGroup
        checked: page.cfg_panelIcon === choice
        onToggled: {
            if (checked) {
                page.cfg_panelIcon = choice;
            }
        }
    }

    // Any icon of the theme, or an image file.
    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: iconName => {
            if (iconName !== "") {
                page.cfg_panelIconCustom = iconName;
                page.cfg_panelIcon = "custom";
                customIcon.checked = true;
            }
        }
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Deezer language:")
            model: page.languages
            textRole: "name"
            valueRole: "code"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_deezerLanguage))
            onActivated: page.cfg_deezerLanguage = currentValue
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("The language of the Deezer page and its menus, which can differ from the system's. Changing it reloads the page, which stops the music.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel icon")
        }

        PanelIconButton {
            Kirigami.FormData.label: i18n("Icon:")
            choice: "widget"
            text: i18n("Widget icon")
        }

        PanelIconButton {
            choice: "favicon"
            text: i18n("Deezer site icon")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Loaded with the Deezer page, as in a browser tab. The widget icon stands in until then.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            visible: page.cfg_panelIcon === "favicon"
            type: Kirigami.MessageType.Warning
            text: i18n("The Deezer logo is a trademark of Deezer SA, and this widget is not made by Deezer. Show it for your own use only.")
        }

        RowLayout {
            PanelIconButton {
                id: customIcon
                choice: "custom"
                text: i18n("Custom icon:")
                // Nothing picked yet: ask for one.
                onToggled: {
                    if (checked && page.cfg_panelIconCustom === "") {
                        iconDialog.open();
                    }
                }
            }

            QQC2.Button {
                id: chooseIcon
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 4
                Layout.preferredHeight: Layout.preferredWidth
                Accessible.name: i18n("Choose an icon")
                QQC2.ToolTip.text: Accessible.name
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: iconDialog.open()

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    source: page.cfg_panelIconCustom !== "" ? page.cfg_panelIconCustom : "document-open"
                }
            }
        }

        QQC2.SpinBox {
            id: wheelStep
            Kirigami.FormData.label: i18n("Volume change per wheel notch:")
            from: 1
            to: 25
            textFromValue: value => i18nc("percentage", "%1 %", value)
            valueFromText: text => parseInt(text)
        }

        QQC2.CheckBox {
            id: invertWheel
            text: i18n("Invert the wheel direction")
        }
    }
}
