import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The panel icon's tooltip, as in Radioglobe: the cover and the track, then
// the transport and volume controls. Plasma shows it through
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
    property real volume: 1
    property bool muted: false
    // Shown under the name when there is no track.
    property string emptyText

    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()
    signal muteRequested()
    signal volumeRequested(real value)

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

        // Transport, then mute, volume and its percentage.
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

            PlasmaComponents.ToolButton {
                icon.name: tip.muted || tip.volume <= 0 ? "audio-volume-muted" : "audio-volume-high"
                display: QQC2.AbstractButton.IconOnly
                text: tip.muted ? i18n("Unmute") : i18n("Mute")
                onClicked: tip.muteRequested()
            }

            ThinSlider {
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                from: 0
                to: 1
                value: tip.muted ? 0 : tip.volume
                onMoved: tip.volumeRequested(value)
            }

            TextMetrics {
                id: percentMetrics
                font: percentLabel.font
                text: "100 %"
            }

            PlasmaComponents.Label {
                id: percentLabel
                Layout.minimumWidth: percentMetrics.width
                horizontalAlignment: Text.AlignRight
                opacity: 0.75
                text: i18nc("volume percentage", "%1 %", Math.round((tip.muted ? 0 : tip.volume) * 100))
            }
        }
    }
}
