import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Lyrics over the blurred cover, like Deezer's own view: the line being sung
// is bright and kept in the upper third, a click on a line seeks there.
Item {
    id: view

    property url cover
    // "loading", "ready" or "missing".
    property string status
    // {synced, lines: [{time, text, translation}], source, writers, licence}
    property var lyrics: null
    property real position: 0
    // Machine translation for lyrics Deezer does not translate: one entry per
    // line, its state ("", "working", "done", "same" or "failed") and engine.
    property var machineTranslations: null
    property string machineState: ""
    property string machineEngine: ""
    // Whether these lyrics may go to the translation engine (settings).
    property bool machineAllowed: true
    // Settings: text size factor, fade strength around the sung line (0 to 1),
    // what is behind the lyrics ("cover", "light" or "dark") and how much the
    // cover is blurred (0 to 1).
    property real fontScale: 1
    property real fadeStrength: 1
    property string background: "cover"
    property real blurStrength: 1

    signal seekRequested(real seconds)
    signal translateRequested()

    readonly property var lines: lyrics ? lyrics.lines : []
    readonly property bool synced: lyrics ? lyrics.synced : false
    // Deezer's own translation, preferred when there is one.
    readonly property bool hasTranslation: lines.some(line => line.translation !== "")
    property bool showTranslation: false
    // Whether to offer Translate: not for lyrics already in the user's language.
    readonly property bool canTranslate: lines.length > 0 && (hasTranslation || (machineAllowed && machineState !== "same"))

    // With Translate on, the lyrics of the next tracks get translated too, and
    // the current ones again when their translation is reset (other engine).
    function translateIfShown() {
        if (showTranslation && lyrics && !hasTranslation && machineState === "") {
            translateRequested();
        }
    }
    onLyricsChanged: translateIfShown()
    // Later: the request sets the state again, from within this change.
    onMachineStateChanged: Qt.callLater(translateIfShown)

    function translationAt(index) {
        if (hasTranslation) {
            return lines[index].translation;
        }
        return machineTranslations ? machineTranslations[index] || "" : "";
    }

    // Index of the line being sung; lines come sorted by time. Looks a little
    // ahead since the position is polled.
    onCurrentLineChanged: list.currentIndex = currentLine

    readonly property int currentLine: {
        if (!synced) {
            return -1;
        }
        const t = position + 0.2;
        let found = -1;
        for (let i = 0; i < lines.length && lines[i].time <= t; i++) {
            found = i;
        }
        return found;
    }

    // A light cover gets dark text over a light veil, any other white text
    // over a dark one, so the lyrics stay readable whatever the cover.
    property real coverBrightness: 0
    readonly property bool lightBackground: background === "light" || (background === "cover" && coverBrightness > 0.6)
    readonly property color textColor: lightBackground ? "black" : "white"

    onCoverChanged: {
        coverBrightness = 0;
        if (cover.toString() !== "") {
            sampler.loadImage(cover);
        }
    }

    // Mean brightness of the cover, from a 16x16 copy of it. The image is
    // unloaded once read: the canvas would keep every cover otherwise, and
    // would not signal a cover coming back as loaded.
    Canvas {
        id: sampler
        width: 16
        height: 16
        opacity: 0
        onImageLoaded: requestPaint()
        onPaint: {
            if (!isImageLoaded(view.cover)) {
                return;
            }
            const ctx = getContext("2d");
            ctx.drawImage(view.cover, 0, 0, width, height);
            const pixels = ctx.getImageData(0, 0, width, height).data;
            let sum = 0;
            for (let i = 0; i < pixels.length; i += 4) {
                sum += 0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2];
            }
            view.coverBrightness = sum / (width * height * 255);
            unloadImage(view.cover);
        }
    }

    Image {
        id: backdrop
        anchors.fill: parent
        source: view.cover
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: backdrop
        source: backdrop
        visible: view.background === "cover"
        blurEnabled: true
        blur: view.blurStrength
        blurMax: 64
        brightness: view.lightBackground ? 0.2 : -0.2
    }

    // The veil over the cover, or the plain background.
    Rectangle {
        anchors.fill: parent
        color: view.background !== "cover" ? (view.lightBackground ? "white" : "black")
             : view.lightBackground ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.25)
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        // Below the top bar rather than under it.
        anchors.topMargin: topBar.visible ? topBar.height + Kirigami.Units.smallSpacing * 2
                                          : Kirigami.Units.largeSpacing
        clip: true
        model: view.lines
        spacing: Kirigami.Units.largeSpacing
        // Set by hand: a new model resets currentIndex, which would drop a binding.
        onCountChanged: currentIndex = view.currentLine
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height / 3
        preferredHighlightEnd: height / 3 + Kirigami.Units.gridUnit * 2
        highlightMoveDuration: 400
        visible: view.status === "ready"

        delegate: Column {
            id: line

            required property int index
            required property var modelData
            readonly property bool current: index === view.currentLine
            // Lines fade out with their distance to the sung one, sung ones faster.
            readonly property int distance: Math.abs(index - view.currentLine)
            readonly property real faded: index < view.currentLine ? Math.max(0.12, 0.35 - 0.08 * (distance - 1))
                                                                   : Math.max(0.15, 0.6 - 0.15 * (distance - 1))

            width: ListView.view.width
            opacity: !view.synced || current ? 1 : 1 - view.fadeStrength * (1 - faded)

            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.InOutQuad
                }
            }

            PlasmaComponents.Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: view.textColor
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * (line.current ? 1.4 : 1.2) * view.fontScale
                // Empty lines are instrumental parts.
                text: line.modelData.text || "♪"
            }

            PlasmaComponents.Label {
                width: parent.width
                visible: view.showTranslation && text !== ""
                wrapMode: Text.WordWrap
                color: Qt.alpha(view.textColor, 0.75)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * view.fontScale
                text: view.translationAt(line.index)
            }

            TapHandler {
                enabled: view.synced
                onTapped: view.seekRequested(line.modelData.time)
            }
        }

        footer: PlasmaComponents.Label {
            width: ListView.view.width
            topPadding: Kirigami.Units.gridUnit
            wrapMode: Text.WordWrap
            color: Qt.alpha(view.textColor, 0.6)
            font: Kirigami.Theme.smallFont
            text: {
                if (!view.lyrics) {
                    return "";
                }
                const credits = [];
                if (view.lyrics.writers) {
                    credits.push(i18n("Writers: %1", view.lyrics.writers));
                }
                if (view.lyrics.licence) {
                    credits.push(view.lyrics.licence);
                }
                if (view.showTranslation && !view.hasTranslation && view.machineState === "failed") {
                    credits.push(i18n("The lyrics could not be translated."));
                }
                return credits.join("\n");
            }
        }
    }

    // Top bar: says where the lyrics and their translation come from when
    // not from Deezer, so nobody takes them for Deezer's; then Translate.
    RowLayout {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        // Not translateButton.visible: a child reads as hidden while its parent
        // is, so the bar would never show without a source to name.
        visible: view.status === "ready" && (sourceLabel.text !== "" || view.canTranslate)
        spacing: Kirigami.Units.smallSpacing
        // Translate in the lyrics' color, which may not be the theme's.
        Kirigami.Theme.textColor: view.textColor

        PlasmaComponents.Label {
            id: sourceLabel
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            color: Qt.alpha(view.textColor, 0.75)
            font: Kirigami.Theme.smallFont
            // Short, e.g. "LRCLIB - No Sync - Trad Google".
            text: {
                const parts = [];
                if (view.lyrics && view.lyrics.source === "lrclib") {
                    parts.push("LRCLIB");
                } else if (view.lyrics && view.lyrics.source === "lrcmux") {
                    // The aggregator, then where its lyrics really come from.
                    parts.push(view.lyrics.origin ? "lrcmux/" + view.lyrics.origin : "lrcmux");
                }
                // Plain text: no timing, so no following, seeking or fade.
                if (view.lyrics && !view.synced) {
                    parts.push(i18n("No sync"));
                }
                if (view.showTranslation && !view.hasTranslation && view.machineState === "done") {
                    parts.push(i18n("Transl. %1", view.machineEngine));
                }
                return parts.join(" - ");
            }
        }

        PlasmaComponents.BusyIndicator {
            Layout.preferredWidth: translateButton.implicitHeight
            Layout.preferredHeight: translateButton.implicitHeight
            visible: view.showTranslation && view.machineState === "working"
            running: visible
        }

        PlasmaComponents.ToolButton {
            id: translateButton
            visible: view.canTranslate
            checkable: true
            checked: view.showTranslation
            icon.name: "translate"
            text: i18n("Translate")
            onToggled: {
                view.showTranslation = checked;
                if (checked && !view.hasTranslation && view.machineState !== "done") {
                    view.translateRequested();
                }
            }
        }
    }

    PlasmaComponents.BusyIndicator {
        anchors.centerIn: parent
        visible: view.status === "loading"
        running: visible
    }

    PlasmaComponents.Label {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: view.status === "missing"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: view.textColor
        text: i18n("No lyrics for this track")
    }
}
