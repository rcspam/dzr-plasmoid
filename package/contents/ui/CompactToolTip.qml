import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/deezer.js" as Deezer

// The panel icon's tooltip, as in Radioglobe: the cover and the track, then
// the transport controls and the track's progress. Plasma shows it through
// PlasmoidItem.toolTipItem; the icon makes the hosting tooltip area
// interactive so the controls can be used.
Item {
    id: tip

    property bool hasTrack: false
    property string title
    property string artist
    property string album
    property url cover
    property bool playing: false
    property real position: 0
    property real duration: 0
    // Shown under the name when there is no track.
    property string emptyText

    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()
    signal seekRequested(real seconds)

    // Whether the tooltip is on screen: the item alone always reads as visible.
    readonly property bool shown: Window.window !== null && Window.window.visible

    implicitWidth: Math.max(column.implicitWidth, Kirigami.Units.gridUnit * 18) + Kirigami.Units.smallSpacing * 2
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Image {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                visible: tip.hasTrack
                source: tip.cover
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                spacing: 0

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.bold: true
                    text: tip.hasTrack ? tip.title : "Deezer"
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tip.hasTrack ? tip.artist : tip.emptyText
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: tip.hasTrack && tip.album !== ""
                    elide: Text.ElideRight
                    opacity: 0.7
                    text: tip.album
                }
            }
        }

        // Transport, then the track's progress.
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents.ToolButton {
                enabled: tip.hasTrack
                icon.name: "media-skip-backward"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Previous track")
                onClicked: tip.previousRequested()
            }

            PlasmaComponents.ToolButton {
                enabled: tip.hasTrack
                icon.name: tip.playing ? "media-playback-pause" : "media-playback-start"
                display: QQC2.AbstractButton.IconOnly
                text: tip.playing ? i18n("Pause") : i18n("Play")
                onClicked: tip.playPauseRequested()
            }

            PlasmaComponents.ToolButton {
                enabled: tip.hasTrack
                icon.name: "media-skip-forward"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Next track")
                onClicked: tip.nextRequested()
            }

            // Seeks on release, or on keyboard moves, as the player's own bar.
            ThinSlider {
                id: progress

                // Where the user asked to go: on release the Binding below may
                // reset value before onPressedChanged runs.
                property real target: -1

                function seek() {
                    tip.seekRequested(target);
                    target = -1;
                }

                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                from: 0
                to: Math.max(tip.duration, 1)
                enabled: tip.hasTrack && tip.duration > 0

                Binding on value {
                    value: tip.position
                    when: !progress.pressed
                    restoreMode: Binding.RestoreNone
                }
                onMoved: {
                    target = value;
                    if (!pressed) {
                        seek();
                    }
                }
                onPressedChanged: {
                    if (!pressed && target >= 0) {
                        seek();
                    }
                }
            }

            PlasmaComponents.Label {
                opacity: 0.75
                font: Kirigami.Theme.smallFont
                text: Deezer.formatTime(progress.pressed ? progress.value : tip.position) + " / " + Deezer.formatTime(tip.duration)
            }
        }
    }
}
