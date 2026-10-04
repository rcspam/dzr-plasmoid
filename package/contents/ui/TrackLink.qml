import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

// A line of the track's text that opens its page on Deezer, as in the site's
// player bar: only as wide as its text, underlined under the mouse.
PlasmaComponents.Label {
    id: link

    // Off when the page has nothing to open, e.g. no album id.
    property bool linked: true
    signal activated()

    Layout.fillWidth: true
    Layout.maximumWidth: implicitWidth
    Layout.alignment: Qt.AlignHCenter
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    font.underline: linked && hover.hovered
    Accessible.role: linked ? Accessible.Link : Accessible.StaticText
    Accessible.onPressAction: {
        if (linked) {
            link.activated();
        }
    }

    HoverHandler {
        id: hover
        enabled: link.linked
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: link.linked
        onTapped: link.activated()
    }
}
