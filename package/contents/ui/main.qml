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
    // Windows the Deezer page opens (Google or Apple sign-in, outside links).
    readonly property int pagePopup: 3
    property int page: pagePlayer

    // Player state mirrored from the page.
    property string session: "unknown" // "in", "out" or "unknown"
    readonly property bool loggedIn: session === "in"
    // Gives the page a moment to restore the last track after sign-in,
    // so "Nothing playing" does not flash before the player shows up.
    property bool settled: false
    // The page still waits for Deezer to restore the listener's last queue.
    property bool pending: false
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
    // Lyrics of the current track, loaded by the page on each track change:
    // status is "loading", "ready" or "missing".
    property string lyricsStatus: ""
    property var lyrics: null
    property bool lyricsShown: false

    // Change detection, so list models are not rebuilt on every poll.
    property string queueJson: ""
    property string playlistsJson: ""
    property int lastNoticeId: -1
    property string lyricsKey: ""
    property bool playlistsRequested: false

    readonly property bool hasTrack: title !== ""

    preferredRepresentation: compactRepresentation
    hideOnWindowDeactivate: !Plasmoid.configuration.pin
    // deezer.com favicon (240x240), shipped: not every icon theme has a Deezer icon.
    // Packaged images need names no icon theme uses: Kirigami.Icon looks the file's
    // base name up in the icon theme first ("deezer" gave WhiteSur's app icon).
    Plasmoid.icon: Qt.resolvedUrl("../images/dzplasmoid-logo.png")
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
            root.pending = state.pending === true;
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

            const lyricsKey = state.lyricsSongId + ":" + state.lyricsStatus;
            if (lyricsKey !== root.lyricsKey) {
                root.lyricsKey = lyricsKey;
                root.lyricsStatus = state.lyricsStatus;
                root.lyrics = null;
                if (state.lyricsStatus === "ready") {
                    root.refreshLyrics();
                }
            }

            if (root.loggedIn && !root.playlistsRequested) {
                root.playlistsRequested = true;
                root.act("loadPlaylists");
            }
        });
    }

    function refreshLyrics() {
        run(Deezer.call("lyrics"), function (result) {
            try {
                root.lyrics = JSON.parse(result).data;
            } catch (e) {
                console.warn("[deezer] bad lyrics:", result);
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
        // Faster while the lyrics follow the song.
        interval: !root.expanded ? 2000 : root.lyricsShown ? 250 : 500
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
        id: full

        readonly property bool webPage: root.page === root.pageWeb || root.page === root.pagePopup

        // The saved size of the view, so that libplasma, when it follows the
        // preferred size, resizes to the same value as restoreSize() below.
        Layout.preferredWidth: targetWidth
        Layout.preferredHeight: targetHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        // The player and the web page each keep their own popup size. libplasma
        // stores a single size and then ignores preferred size changes, so the
        // popup window is resized by hand when the view changes.
        property bool restoringSize: false
        // Set when the view changes or the popup opens, not bound to the saved
        // sizes: those change while the user resizes, which would loop.
        property int targetWidth: viewWidth(false)
        property int targetHeight: viewHeight(false)

        function viewWidth(web) {
            return (web ? Plasmoid.configuration.webWidth : Plasmoid.configuration.playerWidth)
                || Kirigami.Units.gridUnit * (web ? 56 : 22);
        }

        function viewHeight(web) {
            return (web ? Plasmoid.configuration.webHeight : Plasmoid.configuration.playerHeight)
                || Kirigami.Units.gridUnit * (web ? 40 : 38);
        }

        function saveSize() {
            if (restoringSize || !Window.window || !Window.window.visible) {
                return;
            }
            if (webPage) {
                Plasmoid.configuration.webWidth = Math.round(width);
                Plasmoid.configuration.webHeight = Math.round(height);
            } else {
                Plasmoid.configuration.playerWidth = Math.round(width);
                Plasmoid.configuration.playerHeight = Math.round(height);
            }
        }

        function restoreSize() {
            const popup = Window.window;
            if (!popup) {
                return;
            }
            const w = viewWidth(webPage);
            const h = viewHeight(webPage);
            // Raised first: setting the targets makes libplasma resize at once,
            // which must not be saved as this view's size.
            restoringSize = true;
            targetWidth = w;
            targetHeight = h;
            // Size only: Plasma places the popup itself. The window also holds
            // the popup margins.
            popup.width = Math.round(targetWidth + popup.width - width);
            popup.height = Math.round(targetHeight + popup.height - height);
            restoringSize = false;
        }

        onWebPageChanged: restoreSize()
        onWidthChanged: saveSize()
        onHeightChanged: saveSize()

        Connections {
            target: root
            // The popup reopens at the size it was closed with, which may belong
            // to the other view (the page is not remembered across restarts).
            function onExpandedChanged() {
                if (root.expanded) {
                    full.restoreSize();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                visible: root.page !== root.pagePlayer
                icon.name: "go-previous"
                text: root.page === root.pagePopup ? i18n("Deezer") : i18n("Player")
                onClicked: root.page = root.page === root.pagePopup ? root.pageWeb : root.pagePlayer
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                elide: Text.ElideRight
                text: root.page === root.pageQueue ? i18n("Queue")
                    : root.page === root.pagePopup ? popupView.title
                    : "Deezer"
            }

            PlasmaComponents.ToolButton {
                visible: root.page === root.pagePlayer
                icon.name: "web-browser-symbolic"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Show the Deezer page")
                onClicked: root.page = root.pageWeb

                PlasmaComponents.ToolTip {
                    text: parent.text
                }
            }

            PlasmaComponents.ToolButton {
                checkable: true
                checked: Plasmoid.configuration.pin
                icon.name: "window-pin"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Keep Open")
                onToggled: Plasmoid.configuration.pin = checked

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
                readonly property bool idle: root.pageLoaded && root.loggedIn && root.settled && !root.pending

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
                        icon.name: root.loggedIn ? "web-browser-symbolic" : "user"
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
                            visible: !root.lyricsShown
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.enormous
                            height: width
                            visible: coverImage.status !== Image.Ready && !root.lyricsShown
                            source: "media-album-cover"
                            fallback: "audio-headphones"
                        }

                        // In the cover's place, over the cover blurred.
                        LyricsView {
                            anchors.fill: coverImage
                            visible: root.lyricsShown
                            cover: root.cover
                            status: root.lyricsStatus
                            lyrics: root.lyrics
                            position: root.position
                            onSeekRequested: seconds => {
                                root.position = seconds;
                                root.act("seek", [seconds / root.duration]);
                            }
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

                    // Heart and "+" centred at a fifth of the width from each
                    // edge, the track text between them.
                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        implicitHeight: Math.max(trackText.implicitHeight, addButton.implicitHeight)

                        PlasmaComponents.ToolButton {
                            id: favoriteButton
                            x: Math.round(parent.width / 5 - width / 2)
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: root.favoriteAvailable
                            // Filled heart when the track is in the favorites, outline otherwise.
                            // The filled heart ships with the package: icon themes rarely have a real one.
                            icon.name: root.favorite ? "" : "love-symbolic"
                            icon.source: root.favorite ? Qt.resolvedUrl("../images/dzplasmoid-heart-filled.svg") : ""
                            icon.color: Kirigami.Theme.textColor
                            display: QQC2.AbstractButton.IconOnly
                            text: root.favorite ? i18n("Remove from favorites") : i18n("Add to favorites")
                            onClicked: root.act("toggleFavorite")

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }

                        ColumnLayout {
                            id: trackText
                            anchors.left: favoriteButton.right
                            anchors.right: addButton.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
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
                            x: Math.round(parent.width * 4 / 5 - width / 2)
                            anchors.verticalCenter: parent.verticalCenter
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

                    ThinSlider {
                        id: seekSlider
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        from: 0
                        to: Math.max(root.duration, 1)
                        enabled: root.duration > 0

                        // Where the user asked to go, kept apart from value: on release the
                        // Binding below may reset value before onPressedChanged runs.
                        property real target: -1

                        function seek() {
                            // Shown right away, so the handle does not jump back until the next poll.
                            root.position = target;
                            root.act("seek", [target / root.duration]);
                            target = -1;
                        }

                        // Follows the track, except while the user drags the handle.
                        Binding on value {
                            value: root.position
                            when: !seekSlider.pressed
                            restoreMode: Binding.RestoreNone
                        }
                        // Mouse: seek on release. Keyboard moves come without a press.
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

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: Deezer.formatTime(seekSlider.pressed ? seekSlider.value : root.position)
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
                        id: transportRow
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

                    // Mute and volume, as wide as the transport buttons and centred
                    // under them, between the playlists and the queue buttons.
                    // Layouts fill the width by default: turned off here and below,
                    // or the block stretches past the transport buttons.
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: false
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.ToolButton {
                            Layout.rightMargin: Kirigami.Units.gridUnit * 1.5
                            icon.name: "playlist-symbolic"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Show your playlists")
                            onClicked: {
                                root.run(Deezer.call("showPlaylists"));
                                root.page = root.pageWeb;
                            }

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: false
                            Layout.preferredWidth: transportRow.implicitWidth

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

                            ThinSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: root.muted ? 0 : root.volume
                                onMoved: {
                                    root.volume = value;
                                    root.act("setVolume", [value]);
                                }
                            }
                        }

                        PlasmaComponents.ToolButton {
                            Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
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

                        PlasmaComponents.ToolButton {
                            checkable: true
                            checked: root.lyricsShown
                            // Stays usable while shown, to go back to the cover.
                            enabled: root.lyricsStatus === "ready" || root.lyricsShown
                            icon.name: "audio-input-microphone-symbolic"
                            display: QQC2.AbstractButton.IconOnly
                            text: root.lyricsShown ? i18n("Show the cover") : i18n("Show the lyrics")
                            onToggled: root.lyricsShown = checked

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
                        // Double click, as in most players: a single click is easy to make by accident.
                        onDoubleClicked: root.act("playQueueIndex", [index])

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
                // Sign-in with Google or Apple opens a window that reports back
                // to this page, so it has to be a real view sharing the profile.
                onNewWindowRequested: request => {
                    request.openIn(popupView);
                    root.page = root.pagePopup;
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

            // pagePopup
            WebEngineView {
                id: popupView
                profile: web.profile

                onWindowCloseRequested: {
                    root.page = root.pageWeb;
                    url = "about:blank";
                }
            }
        }
    }
}
