import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtWebEngine
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels

import "../code/deezer.js" as Deezer
import "../code/translate.js" as Translate

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
    // Updated in place (see syncQueue), so the list keeps its scroll position.
    // Each row carries its queue position, which the page's actions need.
    ListModel {
        id: queueModel
    }
    // A whole new queue: the list goes back to the current track.
    signal queueReset()

    // The queue as listed: only the tracks matching the search, if any.
    // Rows here are not queue positions: delegates read their position role.
    // Mapping a row back to the source from a delegate binding is not an
    // option: on a removal the proxy tells the view before it shifts the
    // source rows, and the binding would keep the old position.
    KItemModels.KSortFilterProxyModel {
        id: queueFilter
        sourceModel: queueModel
        filterRowCallback: (row, parent) => {
            const search = root.foldText(filterString);
            if (search === "") {
                return true;
            }
            const track = queueModel.get(row);
            return root.foldText(track.title + " " + track.artist).includes(search);
        }
    }

    // Lower case, without accents: "Beyoncé" is found by "beyonce".
    function foldText(text) {
        return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
    }

    // Listed row of a queue position (-1 if hidden).
    function listedRow(position) {
        return queueFilter.mapFromSource(queueModel.index(position, 0)).row;
    }
    property var playlists: null
    // Lyrics of the current track, loaded by the page on each track change:
    // status is "loading", "ready" or "missing".
    property string lyricsStatus: ""
    property var lyrics: null
    property bool lyricsShown: false
    property bool toolTipShown: false

    // From the settings.
    readonly property string deezerLanguage: Deezer.siteLanguage(Plasmoid.configuration.deezerLanguage, Qt.locale().name.split("_")[0])
    readonly property string translationEngine: Plasmoid.configuration.translationEngine
    // Whether these lyrics may go to the translation engine: Deezer's own
    // (licensed from LyricFind) only when the settings allow it.
    readonly property bool machineTranslationAllowed: translationEngine !== "none" && lyrics !== null
        && (lyrics.source !== "deezer" || Plasmoid.configuration.translateDeezerLyrics)
    // Machine translation of lyrics Deezer does not translate, one entry per
    // line. State: "", "working", "done", "same" (already in the user's
    // language) or "failed".
    property var lyricsMachine: null
    property string lyricsMachineState: ""
    property string lyricsMachineEngine: ""
    // What a translation depends on besides the lyrics: the engine, and for
    // Ollama its model and prompt. A change translates the current lyrics
    // again, and keeps apart what the cache holds.
    readonly property string translationSetup: translationEngine !== "ollama" ? translationEngine
        : ["ollama", Plasmoid.configuration.ollamaModel, Translate.fingerprint(Plasmoid.configuration.ollamaPrompt)].join("/")
    onTranslationSetupChanged: {
        lyricsMachine = null;
        lyricsMachineState = "";
        lyricsMachineEngine = "";
    }
    // Deezer's audio settings as the page last read them (see AudioMenu).
    property var audio: null

    // Change detection, so list models are not rebuilt on every poll.
    property string queueJson: ""
    property string playlistsJson: ""
    property int lastNoticeId: -1
    property string lyricsKey: ""
    property string audioJson: ""
    property bool playlistsRequested: false

    readonly property bool hasTrack: title !== ""

    preferredRepresentation: compactRepresentation
    hideOnWindowDeactivate: !Plasmoid.configuration.pin
    // deezer.com favicon (240x240), shipped: not every icon theme has a Deezer icon.
    // Packaged images need names no icon theme uses: Kirigami.Icon looks the file's
    // base name up in the icon theme first ("deezer" gave WhiteSur's app icon).
    Plasmoid.icon: Qt.resolvedUrl("../images/dzplasmoid-logo.png")
    // Plain texts: the fallback when the shell ignores toolTipItem.
    toolTipMainText: hasTrack ? title : Plasmoid.title
    toolTipSubText: hasTrack ? artist : i18n("Nothing playing")
    toolTipItem: CompactToolTip {
        hasTrack: root.hasTrack
        title: root.title
        artist: root.artist
        album: root.album
        cover: root.cover
        playing: root.playing
        position: root.position
        duration: root.duration
        emptyText: root.session === "out" ? i18n("Not signed in") : i18n("Nothing playing")
        onPlayPauseRequested: root.act("togglePause")
        onNextRequested: root.act("next")
        onPreviousRequested: root.act("previous")
        onSeekRequested: seconds => {
            root.position = seconds;
            root.act("seek", [seconds / root.duration]);
        }
        // Polled faster while shown, for a progress bar that moves.
        onShownChanged: root.toolTipShown = shown
    }

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

    // Same for an action on the queue, which has its own refresh.
    function actOnQueue(name, args) {
        run(Deezer.call(name, args));
        queueRefreshSoon.restart();
    }

    // Volume change from the panel icon's wheel, shown at once and clamped.
    function changeVolume(delta) {
        const level = Math.max(0, Math.min(1, (muted ? 0 : volume) + delta));
        volume = level;
        act("setVolume", [level]);
    }

    // Keyboard seek, in seconds, kept within the track.
    function seekBy(seconds) {
        if (duration <= 0) {
            return;
        }
        position = Math.max(0, Math.min(duration, position + seconds));
        act("seek", [position / duration]);
    }

    function refresh() {
        run(Deezer.call("snapshot", [{ extendedLyrics: Plasmoid.configuration.extendedLyrics }]), function (result) {
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
                root.lyricsMachine = null;
                root.lyricsMachineState = "";
                root.lyricsMachineEngine = "";
                if (state.lyricsStatus === "ready") {
                    root.refreshLyrics();
                }
            }

            const audio = JSON.stringify(state.audio);
            if (audio !== root.audioJson) {
                root.audioJson = audio;
                root.audio = state.audio;
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

    function applyTranslation(result) {
        if (result.sameLanguage) {
            lyricsMachineState = "same";
        } else {
            lyricsMachine = result.lines;
            lyricsMachineEngine = result.engine;
            lyricsMachineState = "done";
        }
    }

    function translateLyrics() {
        // Checked here: the view can ask while its own flag for Deezer's
        // translation still describes the previous lyrics.
        const deezerTranslated = lyrics !== null && lyrics.lines.some(line => line.translation !== "");
        if (!machineTranslationAllowed || deezerTranslated || lyricsMachineState === "working" || lyricsMachineState === "done") {
            return;
        }
        const key = lyricsKey;
        const target = Qt.locale().name.split("_")[0];
        // Song, lyrics source, language and engine: each gives other lines.
        const setup = translationSetup;
        // Last, the version of what is stored: 2 since lines given back as
        // they were are dropped (French no longer "translated" into French).
        const cacheKey = [key.split(":")[0], lyrics.source, target, setup, "2"].join(":");
        const cached = translationCache.get(cacheKey);
        if (cached && (cached.sameLanguage || cached.lines.length === lyrics.lines.length)) {
            applyTranslation(cached);
            return;
        }
        lyricsMachineState = "working";
        const options = {
            engine: translationEngine,
            libreTranslateUrl: Plasmoid.configuration.libreTranslateUrl,
            ollamaUrl: Plasmoid.configuration.ollamaUrl,
            ollamaModel: Plasmoid.configuration.ollamaModel,
            ollamaPrompt: Plasmoid.configuration.ollamaPrompt,
        };
        Translate.translateLines(lyrics.lines.map(line => line.text), target, options, result => {
            if (key !== root.lyricsKey || setup !== root.translationSetup) {
                return; // Another track, or other translation settings, by now.
            }
            if (!result) {
                root.lyricsMachineState = "failed";
                return;
            }
            translationCache.set(cacheKey, result);
            root.applyTranslation(result);
        });
    }

    // Applies the page's queue to queueModel with the smallest change: a heart
    // updates its row, a removed or added track its own row. Anything else
    // rebuilds the list. Replacing the model outright would reset the view,
    // which jumped back to the top on every heart.
    function syncQueue(tracks) {
        const sameAt = (i, j) => queueModel.get(i).songId === tracks[j].songId;
        const count = queueModel.count;
        if (tracks.length === count && tracks.every((track, i) => sameAt(i, i))) {
            tracks.forEach((track, i) => {
                if (queueModel.get(i).favorite !== track.favorite) {
                    queueModel.setProperty(i, "favorite", track.favorite);
                }
            });
            return;
        }
        // First row that differs, then check the rest only shifted by one.
        let first = 0;
        while (first < Math.min(count, tracks.length) && sameAt(first, first)) {
            first++;
        }
        if (tracks.length === count - 1) {
            let shifted = true;
            for (let j = first; j < tracks.length && shifted; j++) {
                shifted = sameAt(j + 1, j);
            }
            if (shifted) {
                queueModel.remove(first);
                renumberQueue(first);
                return;
            }
        } else if (tracks.length === count + 1) {
            let shifted = true;
            for (let i = first; i < count && shifted; i++) {
                shifted = sameAt(i, i + 1);
            }
            if (shifted) {
                queueModel.insert(first, tracks[first]);
                renumberQueue(first + 1);
                return;
            }
        }
        queueModel.clear();
        tracks.forEach(track => queueModel.append(track));
        queueReset();
    }

    // The rows from this one on moved in the queue.
    function renumberQueue(from) {
        for (let i = from; i < queueModel.count; i++) {
            queueModel.setProperty(i, "position", i);
        }
    }

    function refreshQueue() {
        run(Deezer.call("queue"), function (result) {
            if (typeof result !== "string" || result === root.queueJson) {
                return;
            }
            root.queueJson = result;
            try {
                root.syncQueue(JSON.parse(result).tracks);
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

    TranslationCache {
        id: translationCache
    }

    WebEngineProfilePrototype {
        id: deezerProfile
        storageName: "deezer-plasmoid"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }

    Timer {
        // Faster while the lyrics follow the song.
        interval: root.expanded ? (root.lyricsShown ? 250 : 500) : root.toolTipShown ? 1000 : 2000
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

    Timer {
        id: queueRefreshSoon
        interval: 300
        onTriggered: root.refreshQueue()
    }

    compactRepresentation: MouseArea {
        property bool wasExpanded: false
        // Wheel travel not yet turned into volume steps (touchpads send bits).
        property real wheelDelta: 0

        // The shell hosts this icon in its ToolTipArea, which shows toolTipItem
        // but closes it as soon as the pointer leaves the icon. As in
        // Radioglobe, walk up to it and make it interactive, so the tooltip's
        // controls can be used.
        function makeToolTipAreaInteractive() {
            let item = parent;
            for (let depth = 0; item && depth < 8; depth++) {
                if ("interactive" in item && "mainItem" in item) {
                    item.interactive = true;
                    return;
                }
                item = item.parent;
            }
        }
        onParentChanged: makeToolTipAreaInteractive()
        Component.onCompleted: makeToolTipAreaInteractive()

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
        // Wheel up raises the volume. angleDelta.y is positive when the wheel
        // turns up, and flipped by natural scrolling, which wheel.inverted
        // tells. One notch (120) is 5 %.
        onWheel: wheel => {
            const delta = (wheel.inverted ? -1 : 1) * (Plasmoid.configuration.invertWheel ? -1 : 1) * wheel.angleDelta.y;
            if (delta === 0) {
                wheel.accepted = false;
                return;
            }
            wheelDelta += delta;
            let steps = 0;
            while (Math.abs(wheelDelta) >= 120) {
                const step = wheelDelta > 0 ? 1 : -1;
                steps += step;
                wheelDelta -= step * 120;
            }
            if (steps !== 0) {
                root.changeVolume(steps * Plasmoid.configuration.wheelStep / 100);
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

        // Keyboard, as in most players. Off on the Deezer page, where keys
        // belong to the site; a text field keeps the keys it uses.
        readonly property bool keysEnabled: !webPage && root.hasTrack

        function withKey(text, shortcut) {
            return i18nc("@info:tooltip a button's name, then its keyboard shortcut", "%1 (%2)", text, shortcut.nativeText);
        }

        Shortcut {
            id: playPauseShortcut
            sequence: "Space"
            enabled: full.keysEnabled
            autoRepeat: false
            onActivated: root.act("togglePause")
        }
        Shortcut {
            id: seekBackShortcut
            sequence: "Left"
            enabled: full.keysEnabled
            onActivated: root.seekBy(-5)
        }
        Shortcut {
            id: seekForwardShortcut
            sequence: "Right"
            enabled: full.keysEnabled
            onActivated: root.seekBy(5)
        }
        Shortcut {
            id: previousShortcut
            sequence: "Shift+Left"
            enabled: full.keysEnabled
            autoRepeat: false
            onActivated: root.act("previous")
        }
        Shortcut {
            id: nextShortcut
            sequence: "Shift+Right"
            enabled: full.keysEnabled
            autoRepeat: false
            onActivated: root.act("next")
        }
        Shortcut {
            id: volumeUpShortcut
            sequence: "Up"
            enabled: full.keysEnabled
            onActivated: root.changeVolume(Plasmoid.configuration.wheelStep / 100)
        }
        Shortcut {
            id: volumeDownShortcut
            sequence: "Down"
            enabled: full.keysEnabled
            onActivated: root.changeVolume(-Plasmoid.configuration.wheelStep / 100)
        }
        Shortcut {
            id: muteShortcut
            sequence: "M"
            enabled: full.keysEnabled
            autoRepeat: false
            onActivated: root.act("toggleMute")
        }
        // From the queue too: back on the player, with the lyrics.
        Shortcut {
            id: lyricsShortcut
            sequence: "L"
            enabled: full.keysEnabled && (root.lyricsStatus === "ready" || root.lyricsShown)
            autoRepeat: false
            onActivated: {
                root.lyricsShown = root.page !== root.pagePlayer || !root.lyricsShown;
                root.page = root.pagePlayer;
            }
        }
        Shortcut {
            id: favoriteShortcut
            sequence: "F"
            enabled: full.keysEnabled && root.favoriteAvailable
            autoRepeat: false
            onActivated: root.act("toggleFavorite")
        }

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

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                elide: Text.ElideRight
                text: root.page === root.pageQueue ? i18n("Queue")
                    : root.page === root.pagePopup ? popupView.title
                    : "Deezer"
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
                            machineTranslations: root.lyricsMachine
                            machineState: root.lyricsMachineState
                            machineEngine: root.lyricsMachineEngine
                            machineAllowed: root.machineTranslationAllowed
                            fontScale: Plasmoid.configuration.lyricsFontScale
                            fadeStrength: Plasmoid.configuration.lyricsFade / 100
                            background: Plasmoid.configuration.lyricsBackground
                            blurStrength: Plasmoid.configuration.lyricsBlur / 100
                            onTranslateRequested: root.translateLyrics()
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
                                text: full.withKey(parent.text, favoriteShortcut)
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

                            PlasmaComponents.ToolTip {
                                text: full.withKey(parent.text, previousShortcut)
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: root.playing ? "media-playback-pause" : "media-playback-start"
                            icon.width: Kirigami.Units.iconSizes.large
                            icon.height: Kirigami.Units.iconSizes.large
                            display: QQC2.AbstractButton.IconOnly
                            text: root.playing ? i18n("Pause") : i18n("Play")
                            onClicked: root.act("togglePause")

                            PlasmaComponents.ToolTip {
                                text: full.withKey(parent.text, playPauseShortcut)
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "media-skip-forward"
                            icon.width: Kirigami.Units.iconSizes.medium
                            icon.height: Kirigami.Units.iconSizes.medium
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Next track")
                            onClicked: root.act("next")

                            PlasmaComponents.ToolTip {
                                text: full.withKey(parent.text, nextShortcut)
                            }
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
                            id: audioButton
                            icon.name: "media-eq-symbolic"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Audio settings")
                            onClicked: {
                                // Read again: the settings may have changed in another player.
                                root.act("readAudio");
                                audioMenu.popup(audioButton, 0, audioButton.height);
                            }

                            PlasmaComponents.ToolTip {
                                text: parent.text
                            }

                            AudioMenu {
                                id: audioMenu
                                audio: root.audio
                                onQualityRequested: quality => root.act("setQuality", [quality])
                                onNormalizeToggled: root.act("toggleNormalize")
                                onQueueSyncToggled: root.act("toggleQueueSync")
                            }
                        }

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

                                PlasmaComponents.ToolTip {
                                    text: full.withKey(parent.text, muteShortcut)
                                }
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

                        // Not checkable: a shown state is told by the purple icon,
                        // without the checked button's grey background.
                        PlasmaComponents.ToolButton {
                            // Stays usable while shown, to go back to the cover.
                            enabled: root.lyricsStatus === "ready" || root.lyricsShown
                            // Karaoke microphone: purple while shown, else in the theme's shade.
                            icon.source: root.lyricsShown ? Qt.resolvedUrl("../images/dzplasmoid-lyrics-active.svg")
                                : Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.resolvedUrl("../images/dzplasmoid-lyrics-dark.svg")
                                : Qt.resolvedUrl("../images/dzplasmoid-lyrics.svg")
                            display: QQC2.AbstractButton.IconOnly
                            text: root.lyricsShown ? i18n("Show the cover") : i18n("Show the lyrics")
                            Accessible.checkable: true
                            Accessible.checked: root.lyricsShown
                            onClicked: root.lyricsShown = !root.lyricsShown

                            PlasmaComponents.ToolTip {
                                text: full.withKey(parent.text, lyricsShortcut)
                            }
                        }
                    }
                }
            }

            // pageQueue
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.SearchField {
                    id: queueSearch
                    Layout.fillWidth: true
                    onTextChanged: {
                        queueFilter.filterString = text;
                        // Back on the current track when the search is cleared.
                        if (text === "") {
                            queueView.showCurrent();
                        }
                    }
                    Keys.onEscapePressed: event => {
                        if (text !== "") {
                            text = "";
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: queueView
                        clip: true
                        model: queueFilter
                        currentIndex: root.listedRow(root.queueIndex)

                        function showCurrent() {
                            const row = root.listedRow(root.queueIndex);
                            if (row >= 0) {
                                positionViewAtIndex(row, ListView.Center);
                            }
                        }

                        // On the current track when a new queue comes or the page opens,
                        // not when a track is removed.
                        onVisibleChanged: {
                            if (visible) {
                                showCurrent();
                            }
                        }

                        Connections {
                            target: root
                            function onQueueReset() {
                                queueView.showCurrent();
                            }
                        }

                        delegate: PlasmaComponents.ItemDelegate {
                            id: trackDelegate
                            // The row's place in the queue, which the page's actions need.
                            required property int position
                            required property string title
                            required property string artist
                            required property string cover
                            required property real duration
                            required property bool favorite
                            readonly property bool current: position === root.queueIndex

                            width: ListView.view.width
                            highlighted: current
                            // A click plays the track; on the current one it only resumes,
                            // so the double click that goes back to the cover never restarts it.
                            onClicked: {
                                if (!current) {
                                    root.act("playQueueIndex", [position]);
                                } else if (!root.playing) {
                                    root.act("togglePause");
                                }
                            }
                            onDoubleClicked: root.page = root.pagePlayer

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Image {
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                                    source: trackDelegate.cover
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
                                        text: trackDelegate.title
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        opacity: 0.7
                                        font: Kirigami.Theme.smallFont
                                        text: trackDelegate.artist
                                    }
                                }

                                PlasmaComponents.Label {
                                    opacity: 0.7
                                    font: Kirigami.Theme.smallFont
                                    text: Deezer.formatTime(trackDelegate.duration)
                                }

                                // Heart and removal, as in deezer.com's queue.
                                PlasmaComponents.ToolButton {
                                    icon.name: trackDelegate.favorite ? "" : "love-symbolic"
                                    icon.source: trackDelegate.favorite ? Qt.resolvedUrl("../images/dzplasmoid-heart-filled.svg") : ""
                                    display: QQC2.AbstractButton.IconOnly
                                    text: trackDelegate.favorite ? i18n("Remove from favorites") : i18n("Add to favorites")
                                    onClicked: root.actOnQueue("toggleQueueFavorite", [trackDelegate.position])

                                    PlasmaComponents.ToolTip {
                                        text: parent.text
                                    }
                                }

                                PlasmaComponents.ToolButton {
                                    icon.name: "window-close-symbolic"
                                    display: QQC2.AbstractButton.IconOnly
                                    text: i18n("Remove from the queue")
                                    onClicked: root.actOnQueue("removeFromQueue", [trackDelegate.position])

                                    PlasmaComponents.ToolTip {
                                        text: parent.text
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // pageWeb: the Deezer page, audio engine, also shown for sign-in.
            WebEngineView {
                id: web
                profile: deezerProfile.instance()
                // Changing the language reloads the page, which stops the music.
                url: Deezer.pageUrl(root.deezerLanguage)
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

                Component.onCompleted: {
                    root.webView = web;
                    profile.httpCacheMaximumSize = Plasmoid.configuration.webCacheLimit * 1024 * 1024;
                }

                // Web cache limit, and the settings' "empty" button.
                Connections {
                    target: Plasmoid.configuration
                    function onWebCacheLimitChanged() {
                        web.profile.httpCacheMaximumSize = Plasmoid.configuration.webCacheLimit * 1024 * 1024;
                    }
                    function onWebCacheClearRequestChanged() {
                        web.profile.clearHttpCache();
                    }
                }
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
