import QtQuick
import QtQuick.Effects
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

    signal seekRequested(real seconds)

    readonly property var lines: lyrics ? lyrics.lines : []
    readonly property bool synced: lyrics ? lyrics.synced : false
    readonly property bool hasTranslation: lines.some(line => line.translation !== "")
    property bool showTranslation: false

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
        blurEnabled: true
        blur: 1
        blurMax: 64
        brightness: -0.2
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        // Below the translate button rather than under it.
        anchors.topMargin: translateButton.visible ? translateButton.height + Kirigami.Units.smallSpacing * 2
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

            width: ListView.view.width
            opacity: !view.synced || current ? 1 : index < view.currentLine ? 0.45 : 0.7

            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.shortDuration
                }
            }

            PlasmaComponents.Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "white"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * (line.current ? 1.4 : 1.2)
                // Empty lines are instrumental parts.
                text: line.modelData.text || "♪"
            }

            PlasmaComponents.Label {
                width: parent.width
                visible: view.showTranslation && line.modelData.translation !== ""
                wrapMode: Text.WordWrap
                color: Qt.rgba(1, 1, 1, 0.75)
                text: line.modelData.translation
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
            color: Qt.rgba(1, 1, 1, 0.6)
            font: Kirigami.Theme.smallFont
            text: {
                if (!view.lyrics) {
                    return "";
                }
                if (view.lyrics.source === "lrclib") {
                    return i18n("Lyrics from LRCLIB");
                }
                const credits = [];
                if (view.lyrics.writers) {
                    credits.push(i18n("Writers: %1", view.lyrics.writers));
                }
                if (view.lyrics.licence) {
                    credits.push(view.lyrics.licence);
                }
                return credits.join("\n");
            }
        }
    }

    PlasmaComponents.ToolButton {
        id: translateButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        visible: view.status === "ready" && view.hasTranslation
        checkable: true
        checked: view.showTranslation
        icon.name: "translate"
        text: i18n("Translate")
        onToggled: view.showTranslation = checked
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
        color: "white"
        text: i18n("No lyrics for this track")
    }
}
