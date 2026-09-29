import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "config/ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Lyrics")
        icon: "view-media-lyrics"
        source: "config/ConfigLyrics.qml"
    }
    ConfigCategory {
        name: i18n("Non-Deezer services")
        icon: "internet-services"
        source: "config/ConfigServices.qml"
    }
    ConfigCategory {
        name: i18n("Storage")
        icon: "drive-harddisk"
        source: "config/ConfigStorage.qml"
    }
}
