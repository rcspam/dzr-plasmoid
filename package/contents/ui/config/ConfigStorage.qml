import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property alias cfg_webCacheLimit: limit.value

    // The web engine keeps the cache of the "deezer-plasmoid" profile in the
    // host program's cache folder (plasmashell, or plasmoidviewer in tests),
    // which is the settings' program too.
    readonly property string cacheFolder: StandardPaths.writableLocation(StandardPaths.CacheLocation).toString().replace("file://", "")
                                          + "/QtWebEngine/deezer-plasmoid"
    // In bytes; -1 while measuring.
    property real cacheSize: -1

    function measure() {
        cacheSize = -1;
        du.connectSource("du -sb '" + cacheFolder + "' #" + Date.now());
    }

    P5Support.DataSource {
        id: du
        engine: "executable"
        onNewData: (source, data) => {
            page.cacheSize = parseInt(data.stdout) || 0;
            disconnectSource(source);
        }
    }

    Component.onCompleted: measure()

    // The widget empties its cache when this changes (after a moment: the
    // web engine does it in the background).
    Timer {
        id: measureAgain
        interval: 2000
        onTriggered: page.measure()
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Web cache")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Size now:")

            QQC2.Label {
                text: page.cacheSize < 0 ? i18n("Measuring…") : i18n("%1 MB", Math.round(page.cacheSize / 1048576))
            }

            QQC2.Button {
                icon.name: "edit-clear-history"
                text: i18n("Empty")
                onClicked: {
                    Plasmoid.configuration.webCacheClearRequest = new Date().toISOString();
                    measureAgain.restart();
                }
            }
        }

        QQC2.SpinBox {
            id: limit
            Kirigami.FormData.label: i18n("Limit:")
            from: 50
            to: 5000
            stepSize: 50
            textFromValue: value => i18n("%1 MB", value)
            valueFromText: text => parseInt(text)
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("The Deezer page caches what it loads, mostly tracks (encrypted) and covers, like any browser. Above the limit, the oldest files go. Emptying it does not sign you out.")
        }
    }
}
