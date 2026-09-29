import QtQuick
import org.kde.plasma.components as PlasmaComponents

// Deezer's audio settings: quality, volume normalisation, queue sync.
// The page stays the reference: items only show what it last reported.
PlasmaComponents.Menu {
    id: menu

    // {quality, qualities: {standard, high, lossless}, normalize, queueSync} or null.
    property var audio: null

    signal qualityRequested(string quality)
    signal normalizeToggled()
    signal queueSyncToggled()

    component QualityItem: PlasmaComponents.MenuItem {
        id: qualityItem

        required property string quality
        readonly property bool current: menu.audio !== null && menu.audio.quality === quality

        checkable: true
        autoExclusive: true
        checked: current
        enabled: menu.audio !== null && menu.audio.qualities[quality] === true
        onTriggered: menu.qualityRequested(quality)

        // A click checks this item and unchecks the others by itself, which
        // drops their bindings; the page answers shortly after.
        Connections {
            target: menu
            function onQualityRequested() {
                qualityItem.checked = Qt.binding(() => qualityItem.current);
            }
        }
    }

    PlasmaComponents.MenuItem {
        enabled: false
        text: i18n("Audio quality")
    }

    QualityItem {
        quality: "standard"
        text: i18n("Standard (128 kb/s)")
    }

    QualityItem {
        quality: "high"
        text: i18n("High Quality (320 kb/s)")
    }

    QualityItem {
        quality: "lossless"
        text: i18n("High Fidelity (FLAC)")
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        checkable: true
        checked: menu.audio !== null && menu.audio.normalize
        enabled: menu.audio !== null
        text: i18n("Normalize volume")
        onTriggered: {
            menu.normalizeToggled();
            checked = Qt.binding(() => menu.audio !== null && menu.audio.normalize);
        }
    }

    PlasmaComponents.MenuItem {
        visible: menu.audio !== null && menu.audio.queueSync !== null
        height: visible ? implicitHeight : 0
        checkable: true
        checked: menu.audio !== null && menu.audio.queueSync === true
        text: i18n("Sync the queue")
        onTriggered: {
            menu.queueSyncToggled();
            checked = Qt.binding(() => menu.audio !== null && menu.audio.queueSync === true);
        }
    }
}
