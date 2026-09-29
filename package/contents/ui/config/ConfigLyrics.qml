import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import ".." as Ui

KCM.SimpleKCM {
    id: page

    property string cfg_translationEngine
    property alias cfg_libreTranslateUrl: libreTranslateUrl.text
    property alias cfg_ollamaUrl: ollamaUrl.text
    property alias cfg_ollamaModel: ollamaModel.text
    property alias cfg_translateDeezerLyrics: translateDeezerLyrics.checked
    property real cfg_lyricsFontScale
    property alias cfg_lyricsFade: fade.value

    // Same database as the widget: the settings run in its process.
    Ui.TranslationCache {
        id: translationCache
    }
    property int cachedTranslations: translationCache.count()

    component EngineButton: QQC2.RadioButton {
        required property string engine
        checked: page.cfg_translationEngine === engine
        onToggled: {
            if (checked) {
                page.cfg_translationEngine = engine;
            }
        }
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Translation of lyrics Deezer does not translate")
        }

        EngineButton {
            Kirigami.FormData.label: i18n("Translate with:")
            engine: "google"
            text: i18n("Google (online, unofficial service)")
        }

        EngineButton {
            engine: "libretranslate"
            text: i18n("A LibreTranslate server")
        }

        QQC2.TextField {
            id: libreTranslateUrl
            Kirigami.FormData.label: i18n("LibreTranslate address:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: page.cfg_translationEngine === "libretranslate"
            placeholderText: "http://127.0.0.1:5000"
        }

        EngineButton {
            engine: "ollama"
            text: i18n("An Ollama server (better, but slower)")
        }

        QQC2.TextField {
            id: ollamaUrl
            Kirigami.FormData.label: i18n("Ollama address:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: page.cfg_translationEngine === "ollama"
            placeholderText: "http://127.0.0.1:11434"
        }

        QQC2.TextField {
            id: ollamaModel
            Kirigami.FormData.label: i18n("Ollama model:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            enabled: page.cfg_translationEngine === "ollama"
            placeholderText: "translategemma"
        }

        EngineButton {
            engine: "none"
            text: i18n("No machine translation")
        }

        QQC2.CheckBox {
            id: translateDeezerLyrics
            enabled: page.cfg_translationEngine !== "none"
            text: i18n("Also translate the lyrics Deezer provides")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Deezer's lyrics are licensed from LyricFind for personal use: this sends them to the chosen engine. Lyrics from LRCLIB are always translated.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
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

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Cache")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Kept translations:")

            QQC2.Label {
                text: i18np("%1 song", "%1 songs", page.cachedTranslations)
            }

            QQC2.Button {
                enabled: page.cachedTranslations > 0
                icon.name: "edit-clear-history"
                text: i18n("Empty")
                onClicked: {
                    translationCache.clear();
                    page.cachedTranslations = translationCache.count();
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Only translations are kept here. Deezer's lyrics are not kept; those from LRCLIB stay in the web cache (Storage page), like any page the browser loads.")
        }
    }
}
