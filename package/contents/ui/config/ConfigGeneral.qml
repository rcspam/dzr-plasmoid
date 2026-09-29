import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "../../code/deezer.js" as Deezer

KCM.SimpleKCM {
    id: page

    property string cfg_deezerLanguage
    property alias cfg_wheelStep: wheelStep.value
    property alias cfg_invertWheel: invertWheel.checked

    // The site's languages under their own names; "" follows the system.
    readonly property var languageNames: ({
            fr: "Français", en: "English", de: "Deutsch", es: "Español", it: "Italiano",
            pt: "Português", br: "Português (Brasil)", nl: "Nederlands", pl: "Polski",
            ru: "Русский", tr: "Türkçe", sv: "Svenska", da: "Dansk", fi: "Suomi",
            ro: "Română", hu: "Magyar", cs: "Čeština", ja: "日本語", ar: "العربية"
        })
    readonly property var languages: [{ code: "", name: i18n("Same as the system") }].concat(
        Deezer.siteLanguages.map(code => ({ code: code, name: languageNames[code] || code })))

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
