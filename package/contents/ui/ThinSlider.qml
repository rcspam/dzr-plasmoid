import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Thin line in Deezer's purple with a small white handle.
PlasmaComponents.Slider {
    id: control

    readonly property color accent: "#a238ff"

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth
        height: 3
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: control.accent
            visible: control.enabled
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + (control.availableHeight - height) / 2
        implicitWidth: Kirigami.Units.gridUnit * 0.6
        implicitHeight: implicitWidth
        radius: width / 2
        color: "white"
        // Keeps the dot visible on light themes too.
        border.color: Qt.rgba(0, 0, 0, 0.25)
        border.width: 1
        visible: control.enabled
    }
}
