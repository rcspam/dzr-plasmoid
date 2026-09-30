import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import ".." as Ui
import "../../code/translate.js" as Translate

// Everything that goes to a service other than Deezer: lyrics sources,
// machine translation, and the translations kept from it.
KCM.SimpleKCM {
    id: page

    property string cfg_translationEngine
    property alias cfg_libreTranslateUrl: libreTranslateUrl.text
    property alias cfg_ollamaUrl: ollamaUrl.text
    property alias cfg_ollamaModel: ollamaModel.text
    // Empty for the default prompt, shown in the field all the same.
    property string cfg_ollamaPrompt
    property alias cfg_translateDeezerLyrics: translateDeezerLyrics.checked
    property alias cfg_extendedLyrics: extendedLyrics.checked

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

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Lyrics")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Lyrics:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("When Deezer has no synced lyrics, they are looked up on LRCLIB (lrclib.net), a free database made by its users.")
        }

        QQC2.CheckBox {
            id: extendedLyrics
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

        QQC2.TextArea {
            id: ollamaPrompt
            Kirigami.FormData.label: i18n("Ollama prompt:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            enabled: page.cfg_translationEngine === "ollama"
            wrapMode: TextEdit.Wrap
            text: page.cfg_ollamaPrompt || Translate.OLLAMA_PROMPT
            onTextChanged: page.cfg_ollamaPrompt = text === Translate.OLLAMA_PROMPT ? "" : text
        }

        RowLayout {
            enabled: page.cfg_translationEngine === "ollama"

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                text: i18n("{language} and {code} become the language to translate into (français, fr), {lines} the lyrics as numbered lines. The answer must keep the numbers, as \"number| translation\".")
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignTop
                icon.name: "edit-undo"
                text: i18n("Default")
                enabled: page.cfg_ollamaPrompt !== ""
                onClicked: ollamaPrompt.text = Translate.OLLAMA_PROMPT
            }
        }

        EngineButton {
            engine: "none"
            text: i18n("No machine translation")
        }

        QQC2.CheckBox {
            id: translateDeezerLyrics
            enabled: page.cfg_translationEngine === "google"
            text: i18n("Also send the lyrics Deezer provides to Google")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Deezer's lyrics are licensed from LyricFind for personal use. The LibreTranslate or Ollama server you set up always translates them, Google only with this option. Lyrics from LRCLIB are always translated.")
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
