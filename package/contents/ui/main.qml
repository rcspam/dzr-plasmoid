import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtWebEngine
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/deezer.js" as Deezer

PlasmoidItem {
    id: root

    // The Deezer page runs in a WebEngineView living in the full
    // representation; it plays the audio and keeps the session.
    // Everything the user sees is native QML fed by polling that page.
    property var webView: null
    property bool pageLoaded: false

    // Pages of the popup, in StackLayout order.
    readonly property int pagePlayer: 0
    readonly property int pageQueue: 1
    readonly property int pageWeb: 2
    property int page: pagePlayer

    // Player state mirrored from the page.
    property string session: "unknown" // "in", "out" or "unknown"
    readonly property bool loggedIn: session === "in"
    // Gives the page a moment to restore the last track after sign-in,
    // so "Nothing playing" does not flash before the player shows up.
    property bool settled: false
    property bool playing: false
    property string songId: ""
    property string title: ""
    property string artist: ""
    property string album: ""
    property string cover: ""
    property real position: 0
    property real duration: 0
    property bool shuffle: false
    property int repeat: 0 // 0 off, 1 all, 2 one
    property real volume: 1
    property bool muted: false
    property bool favorite: false
    property bool favoriteAvailable: false
    property int queueIndex: 0
    property var queueTracks: []
    property var playlists: null

    // Change detection, so list models are not rebuilt on every poll.
    property string queueJson: ""
    property string playlistsJson: ""
    property int lastNoticeId: -1
    property bool playlistsRequested: false

    readonly property bool hasTrack: title !== ""

    preferredRepresentation: compactRepresentation
    toolTipMainText: hasTrack ? title : Plasmoid.title
    toolTipSubText: hasTrack ? artist : i18n("Nothing playing")

    signal notice(string kind, string text)

    function run(script, callback) {
        if (!webView) {
            return;
        }
        if (callback) {
            webView.runJavaScript(script, callback);
        } else {
            webView.runJavaScript(script);
        }
    }

    // Runs an action in the page, then refreshes the state shortly after.
    function act(name, args) {
        run(Deezer.call(name, args));
        refreshSoon.restart();
    }

    function refresh() {
        run(Deezer.call("snapshot"), function (result) {
            if (typeof result !== "string") {
                return;
            }
            let state;
            try {
                state = JSON.parse(result);
            } catch (e) {
                console.warn("[deezer] bad snapshot:", result);
                return;
            }
            root.session = state.session;
            if (!state.ready) {
                return;
            }
            root.playing = state.playing;
            root.songId = state.songId;
            root.title = state.title;
            root.artist = state.artist;
            root.album = state.album;
            root.cover = state.cover;
            root.position = state.position;
            root.duration = state.duration;
            root.shuffle = state.shuffle;
            root.repeat = state.repeat;
            root.volume = state.volume;
            root.muted = state.muted;
            root.favorite = state.favorite;
            root.favoriteAvailable = state.favoriteAvailable;
            root.queueIndex = state.queueIndex;

            const lists = JSON.stringify(state.playlists);
            if (lists !== root.playlistsJson) {
                root.playlistsJson = lists;
                root.playlists = state.playlists;
            }
            if (root.lastNoticeId >= 0 && state.notice.id !== root.lastNoticeId) {
                root.notice(state.notice.kind, state.notice.text);
            }
            root.lastNoticeId = state.notice.id;

            if (root.loggedIn && !root.playlistsRequested) {
                root.playlistsRequested = true;
                root.act("loadPlaylists");
            }
        });
    }

    function refreshQueue() {
        run(Deezer.call("queue"), function (result) {
            if (typeof result !== "string" || result === root.queueJson) {
                return;
            }
            root.queueJson = result;
            try {
                root.queueTracks = JSON.parse(result).tracks;
            } catch (e) {
                console.warn("[deezer] bad queue:", result);
            }
        });
    }

    onSessionChanged: {
        settled = false;
        if (session === "in") {
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: 4000
        onTriggered: root.settled = true
    }

    onSongIdChanged: {
        if (page === root.pageQueue) {
            refreshQueue();
        }
    }

    WebEngineProfilePrototype {
        id: deezerProfile
        storageName: "deezer-plasmoid"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }

    Timer {
        interval: root.expanded ? 500 : 2000
        running: root.webView !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 2000
        running: root.webView !== null && root.expanded && root.page === root.pageQueue
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshQueue()
    }

    Timer {
        id: refreshSoon
        interval: 250
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        property bool wasExpanded: false

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onPressed: wasExpanded = root.expanded
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.act("togglePause");
            } else {
                root.expanded = !wasExpanded;
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: parent.containsMouse
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * (root.page === root.pageWeb ? 56 : 22)
        Layout.preferredHeight: Kirigami.Units.gridUnit * (root.page === root.pageWeb ? 40 : 38)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                visible: root.page !== root.pagePlayer
                icon.name: "go-previous"
                text: i18n("Player")
                onClicked: root.page = root.pagePlayer
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: root.page === root.pageQueue ? i18n("Queue") : "Deezer"
            }

            PlasmaComponents.ToolButton {
                visible: root.page === root.pagePlayer
                icon.name: "internet-web-browser"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Show the Deezer page")
                onClicked: root.page = root.pageWeb

                PlasmaComponents.ToolTip {
                    text: parent.text
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.page

            // pagePlayer
            Item {
                // Only states we are sure about get a message; anything
                // still loading or being checked gets the spinner.
                readonly property bool signedOut: root.pageLoaded && root.session === "out"
                readonly property bool idle: root.pageLoaded && root.loggedIn && root.settled

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    width: Kirigami.Units.gridUnit * 4
                    height: width
                    visible: !root.hasTrack && !parent.signedOut && !parent.idle
                    running: visible
                }

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    visible: !root.hasTrack && (parent.signedOut || parent.idle)
                    iconName: "audio-headphones"
                    text: parent.signedOut ? i18n("Not signed in") : i18n("Nothing playing")
                    helpfulAction: QQC2.Action {
                        icon.name: root.loggedIn ? "internet-web-browser" : "user"
                        text: root.loggedIn ? i18n("Open Deezer") : i18n("Sign in")
                        onTriggered: root.page = root.pageWeb
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    visible: root.hasTrack
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Kirigami.ShadowedImage {
                            id: coverImage
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            source: root.cover
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            radius: Kirigami.Units.cornerRadius
                            shadow.size: Kirigami.Units.largeSpacing
                            shadow.color: Qt.rgba(0, 0, 0, 0.4)
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.enormous
                            height: width
                            visible: coverImage.status !== Image.Ready
                            source: "media-album-cover"
                            fallback: "audio-headphones"
                        }

                        // Short-lived feedback, e.g. after adding to a playlist.
                        Rectangle {
                            id: noticeBubble
                            property string text: ""
                            anchors.horizontalCenter: coverImage.horizontalCenter
                            anchors.bottom: coverImage.bottom
                            anchors.bottomMargin: Kirigami.Units.largeSpacing
                            width: Math.min(noticeLabel.implicitWidth + Kirigami.Units.largeSpacing * 2, coverImage.width - Kirigami.Units.largeSpacing * 2)
                            height: noticeLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.75)
                            visible: noticeTimer.running

                            PlasmaComponents.Label {
                                id: noticeLabel
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.largeSpacing * 2
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                color: "white"
                                text: noticeBubble.text
                            }

                            Timer {
                                id: noticeTimer
                                interval: 3000
                            }

                            Connections {
                                target: root
                                function onNotice(kind, text) {
                                    noticeBubble.text = kind === "added" ? i18n("Added to %1", text)
                                                                         : i18n("Could not add to %1", text);
                                    noticeTimer.restart();
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing

                        PlasmaComponents.ToolButton {
                            enabled: root.favoriteAvailable
                            // Filled heart when the track is in the favorites, outline otherwise.
                            // The filled heart ships with the package: icon themes rarely have a real one.
                            icon.name: root.favorite ? "" : "love-symbolic"
                            icon.source: root.favorite ? Qt.resolvedUrl("../images/heart-filled.svg") : ""
                            icon.color: Kirigami.Theme.textColor
                            display: QQC2.AbstractButton.IconOnly
                            text: root.favorite ? i18n("Remove from favorites") : i18n("Add to favorites")
                            onClicked: root.act("toggleFavorite")

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Kirigami.Heading {
                                Layout.fillWidth: true
                                level: 3
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: root.title
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: root.artist
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                opacity: 0.7
                                text: root.album
                            }
                        }

                        PlasmaComponents.ToolButton {
                            id: addButton
                            icon.name: "list-add"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Add to a playlist")
                            onClicked: {
                                root.act("loadPlaylists");
                                playlistMenu.popup(addButton, 0, addButton.height);
                            }

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }

                            PlasmaComponents.Menu {
                                id: playlistMenu

                                PlasmaComponents.MenuItem {
                                    enabled: false
                                    visible: !root.playlists || root.playlists.length === 0
                                    height: visible ? implicitHeight : 0
                                    text: root.playlists ? i18n("No playlist") : i18n("Loading playlists…")
                                }

                                Instantiator {
                                    model: root.playlists || []
                                    delegate: PlasmaComponents.MenuItem {
                                        required property var modelData
                                        text: i18np("%2 (%1 track)", "%2 (%1 tracks)", modelData.count, modelData.title)
                                        onTriggered: root.act("addToPlaylist", [modelData.id, modelData.title])
                                    }
                                    onObjectAdded: (index, object) => playlistMenu.insertItem(index + 1, object)
                                    onObjectRemoved: (index, object) => playlistMenu.removeItem(object)
                                }
                            }
                        }
                    }

                    PlasmaComponents.ProgressBar {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        from: 0
                        to: Math.max(root.duration, 1)
                        value: root.position
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: Deezer.formatTime(root.position)
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: Deezer.formatTime(root.duration)
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.ToolButton {
                            checkable: true
                            checked: root.shuffle
                            icon.name: "media-playlist-shuffle"
                            display: QQC2.AbstractButton.IconOnly
                            text: root.shuffle ? i18n("Shuffle: on") : i18n("Shuffle: off")
                            onClicked: root.act("toggleShuffle")

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "media-skip-backward"
                            icon.width: Kirigami.Units.iconSizes.medium
                            icon.height: Kirigami.Units.iconSizes.medium
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Previous track")
                            onClicked: root.act("previous")
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: root.playing ? "media-playback-pause" : "media-playback-start"
                            icon.width: Kirigami.Units.iconSizes.large
                            icon.height: Kirigami.Units.iconSizes.large
                            display: QQC2.AbstractButton.IconOnly
                            text: root.playing ? i18n("Pause") : i18n("Play")
                            onClicked: root.act("togglePause")
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "media-skip-forward"
                            icon.width: Kirigami.Units.iconSizes.medium
                            icon.height: Kirigami.Units.iconSizes.medium
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Next track")
                            onClicked: root.act("next")
                        }

                        PlasmaComponents.ToolButton {
                            checkable: true
                            checked: root.repeat > 0
                            icon.name: root.repeat === 2 ? "media-playlist-repeat-song" : "media-playlist-repeat"
                            display: QQC2.AbstractButton.IconOnly
                            text: root.repeat === 2 ? i18n("Repeat: current track")
                                : root.repeat === 1 ? i18n("Repeat: all")
                                : i18n("Repeat: off")
                            onClicked: root.act("cycleRepeat")

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.ToolButton {
                            readonly property real level: root.muted ? 0 : root.volume
                            icon.name: level <= 0 ? "audio-volume-muted"
                                : level < 0.34 ? "audio-volume-low"
                                : level < 0.67 ? "audio-volume-medium"
                                : "audio-volume-high"
                            display: QQC2.AbstractButton.IconOnly
                            text: root.muted ? i18n("Unmute") : i18n("Mute")
                            onClicked: root.act("toggleMute")
                        }

                        PlasmaComponents.Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: 1
                            value: root.muted ? 0 : root.volume
                            onMoved: {
                                root.volume = value;
                                root.act("setVolume", [value]);
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "view-media-playlist"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Show the queue")
                            onClicked: {
                                root.page = root.pageQueue;
                                root.refreshQueue();
                            }

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }
                    }
                }
            }

            // pageQueue
            PlasmaComponents.ScrollView {
                ListView {
                    id: queueView
                    clip: true
                    model: root.queueTracks
                    currentIndex: root.queueIndex
                    onCountChanged: positionViewAtIndex(root.queueIndex, ListView.Center)

                    delegate: PlasmaComponents.ItemDelegate {
                        id: trackDelegate
                        required property int index
                        required property var modelData
                        readonly property bool current: index === root.queueIndex

                        width: ListView.view.width
                        highlighted: current
                        onClicked: root.act("playQueueIndex", [index])

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Image {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                                source: trackDelegate.modelData.cover
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: trackDelegate.current
                                    text: trackDelegate.modelData.title
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    opacity: 0.7
                                    font: Kirigami.Theme.smallFont
                                    text: trackDelegate.modelData.artist
                                }
                            }

                            PlasmaComponents.Label {
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                text: Deezer.formatTime(trackDelegate.modelData.duration)
                            }
                        }
                    }
                }
            }

            // pageWeb: the Deezer page, audio engine, also shown for sign-in.
            WebEngineView {
                id: web
                profile: deezerProfile.instance()
                url: Deezer.pageUrl
                settings.playbackRequiresUserGesture: false
                userScripts.collection: [{
                    name: "dzPlasmoid",
                    sourceUrl: Qt.resolvedUrl("../code/page.js"),
                    injectionPoint: WebEngineScript.DocumentReady,
                    worldId: WebEngineScript.MainWorld
                }]

                onLoadingChanged: request => {
                    if (request.status === WebEngineLoadingInfo.LoadSucceededStatus) {
                        root.pageLoaded = true;
                        refreshSoon.restart();
                    }
                }
                onRenderProcessTerminated: (status, code) => {
                    console.warn("[deezer] render process terminated", status, code, "- reloading");
                    root.pageLoaded = false;
                    reload();
                }

                Component.onCompleted: root.webView = web
                Component.onDestruction: {
                    if (root.webView === web) {
                        root.webView = null;
                    }
                }
            }
        }
    }
}
