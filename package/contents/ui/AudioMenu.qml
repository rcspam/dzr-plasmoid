import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Deezer's audio settings: quality, volume normalisation, queue sync.
// The page stays the reference: items only show what it last reported.
PlasmaComponents.Menu {
    id: menu

    // {quality, qualities: {standard, high, lossless}, normalize, queueSync} or null.
    property var audio: null

    signal qualityRequested(string quality)
    signal normalizeToggled()
    signal queueSyncToggled()

    // A menu line with a plain check icon, as in Radioglobe: Plasma's own
    // indicator draws its hover frame over the mark, which hides it. Not
    // checkable either: a checkable item flips its own state on click, before
    // the page has applied anything. `active` follows the page alone.
    component CheckedItem: PlasmaComponents.MenuItem {
        id: line

        property bool active: false

        // Room for the mark, which a non-checkable item does not reserve.
        leftPadding: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 3
        indicator: Kirigami.Icon {
            x: line.mirrored ? line.width - width - Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing * 2
            y: line.topPadding + Math.round((line.availableHeight - height) / 2)
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            source: "checkmark"
            visible: line.active
        }
    }

    component QualityItem: CheckedItem {
        required property string quality

        active: menu.audio !== null && menu.audio.quality === quality
        enabled: menu.audio !== null && menu.audio.qualities[quality] === true
        onTriggered: menu.qualityRequested(quality)
    }

    CheckedItem {
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

    CheckedItem {
        active: menu.audio !== null && menu.audio.normalize
        enabled: menu.audio !== null
        text: i18n("Normalize volume")
        onTriggered: menu.normalizeToggled()
    }

    CheckedItem {
        visible: menu.audio !== null && menu.audio.queueSync !== null
        height: visible ? implicitHeight : 0
        active: menu.audio !== null && menu.audio.queueSync === true
        text: i18n("Sync the queue")
        onTriggered: menu.queueSyncToggled()
    }
}
