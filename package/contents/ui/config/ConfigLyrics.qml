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
    property alias cfg_extendedLyrics: extendedLyrics.checked
    property real cfg_lyricsFontScale
    property alias cfg_lyricsFade: fade.value
    property string cfg_lyricsBackground
    property alias cfg_lyricsBlur: blur.value

    // Same database as the widget: the settings run in its process.
    Ui.TranslationCache {
        id: translationCache
    }
    property real cacheSize: translationCache.size()

    function formatSize(bytes) {
        if (bytes < 1024) {
            return i18np("%1 byte", "%1 bytes", bytes);
        }
        if (bytes < 1048576) {
            return i18n("%1 KB", Math.round(bytes / 1024));
        }
        return i18n("%1 MB", (bytes / 1048576).toFixed(1));
    }

    // Radio buttons in one parent all exclude each other: one group per setting.
    QQC2.ButtonGroup {
        id: engineGroup
    }
    QQC2.ButtonGroup {
        id: backgroundGroup
    }

    component EngineButton: QQC2.RadioButton {
        required property string engine
        QQC2.ButtonGroup.group: engineGroup
        checked: page.cfg_translationEngine === engine
        onToggled: {
            if (checked) {
                page.cfg_translationEngine = engine;
            }
        }
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
            Kirigami.FormData.label: i18n("Sources")
        }

        QQC2.CheckBox {
            id: extendedLyrics
            Kirigami.FormData.label: i18n("Lyrics:")
            text: i18n("Extended sources (lrcmux)")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("When Deezer and LRCLIB have no synced lyrics, asks lrcmux, which gathers them from YouTube Music, KuGou, Musixmatch and others. These are unofficial, unlicensed sources: for personal use, and the service may stop at any time.")
        }

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

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Cache")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Kept translations:")

            QQC2.Label {
                text: page.formatSize(page.cacheSize)
            }

            QQC2.Button {
                enabled: page.cacheSize > 0
                icon.name: "edit-clear-history"
                text: i18n("Empty")
                onClicked: {
                    translationCache.clear();
                    page.cacheSize = translationCache.size();
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Only the translations are kept, never the lyrics themselves.")
        }
    }
}
