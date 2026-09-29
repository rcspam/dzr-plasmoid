// Injected into the Deezer web page (main world) by the plasmoid.
// Exposes window.__dzPlasmoid, the only surface the QML side talks to.
// It relies on window.dzPlayer and on Deezer's internal gw-light API, neither
// of which is public: when Deezer changes them, this file is the one to fix.

(() => {
    if (window.__dzPlasmoid) {
        return;
    }

    const COVER_URL = 'https://cdn-images.dzcdn.net/images/cover/';
    const GW_URL = 'https://www.deezer.com/ajax/gw-light.php';

    const h = window.__dzPlasmoid = {
        // 'in', 'out' or 'unknown' (not checked yet, or the check failed).
        session: 'unknown',
        playlists: null,
        notice: { id: 0, kind: '', text: '' },
        token: '',
        user: null,
    };

    const player = () => window.dzPlayer;
    const coverUrl = (picture, size) => picture ? COVER_URL + picture + '/' + size + 'x' + size + '.jpg' : '';
    const favoriteButton = () => document.querySelector('[data-testid^="add_to_favorite_button"]');

    function notify(kind, text) {
        h.notice = { id: h.notice.id + 1, kind, text };
    }

    async function rawCall(name, token, payload) {
        const url = `${GW_URL}?method=${name}&input=3&api_version=1.0&api_token=${token}`;
        const response = await fetch(url, { method: 'POST', credentials: 'include', body: JSON.stringify(payload || {}) });
        return response.json();
    }

    async function gw(method, body) {
        if (!h.token) {
            const data = await rawCall('deezer.getUserData', '', {});
            h.token = data.results.checkForm;
            h.user = data.results.USER;
        }
        const data = await rawCall(method, h.token, body);
        if (data.error && Object.keys(data.error).length) {
            h.token = '';
            throw new Error(JSON.stringify(data.error));
        }
        return data.results;
    }

    // Asks Deezer who is signed in; a user id of 0 means nobody.
    let lastSessionCheck = 0;
    async function checkSession() {
        lastSessionCheck = Date.now();
        if (location.hostname !== 'www.deezer.com') {
            // account.deezer.com only shows up while signing in.
            h.session = 'out';
            return;
        }
        try {
            const data = await rawCall('deezer.getUserData', '', {});
            const user = data.results && data.results.USER;
            if (user && Number(user.USER_ID) > 0) {
                h.session = 'in';
                h.user = user;
                h.token = data.results.checkForm;
            } else {
                h.session = 'out';
            }
        } catch (e) {
            h.session = 'unknown';
        }
    }
    checkSession();

    // On load Deezer first queues a placeholder (the account's welcome playlist,
    // context player_default_playlist), then swaps in the listener's last queue
    // a couple of seconds later. The placeholder is only shown if nothing better
    // comes (an account without history) or if the user plays it.
    const RESTORE_TIMEOUT = 10000;
    let playerSince = 0;
    let restored = false;
    function queueRestored(p, song) {
        if (!restored) {
            playerSince = playerSince || Date.now();
            const context = p.getContext() || {};
            const placeholder = !song.SNG_ID || context.TYPE === 'player_default_playlist';
            restored = !placeholder || p.isPlaying() || Date.now() - playerSince > RESTORE_TIMEOUT;
        }
        return restored;
    }

    h.snapshot = () => {
        const p = player();
        if (document.querySelector('[data-testid="topbar-profile"]')) {
            h.session = 'in';
        } else if (h.session !== 'in' && Date.now() - lastSessionCheck > 5000) {
            checkSession();
        }
        const session = h.session;
        if (!p || typeof p.getCurrentSong !== 'function') {
            return JSON.stringify({ ready: false, session });
        }
        const song = p.getCurrentSong() || {};
        if (session === 'in' && !queueRestored(p, song)) {
            return JSON.stringify({ ready: false, pending: true, session });
        }
        const meta = navigator.mediaSession && navigator.mediaSession.metadata;
        let cover = coverUrl(song.ALB_PICTURE, 1000);
        if (!cover && meta && meta.artwork && meta.artwork.length) {
            cover = meta.artwork[meta.artwork.length - 1].src;
        }
        let title = (meta && meta.title) || song.SNG_TITLE || '';
        if (song.VERSION && title && title.indexOf(song.VERSION) < 0) {
            title += ' ' + song.VERSION;
        }
        const fav = favoriteButton();
        return JSON.stringify({
            ready: true,
            session,
            playing: p.isPlaying(),
            songId: String(song.SNG_ID || ''),
            title,
            artist: (meta && meta.artist) || song.ART_NAME || '',
            album: (meta && meta.album) || song.ALB_TITLE || '',
            cover,
            position: Number(p.getPosition()) || 0,
            duration: Number(p.getDuration()) || 0,
            shuffle: !!p.isShuffle(),
            repeat: Number(p.getRepeat()) || 0,
            volume: Number(p.getVolume()),
            muted: !!p.isMuted(),
            favorite: !!fav && !/_off$/.test(fav.dataset.testid),
            favoriteAvailable: !!fav,
            queueIndex: Number(p.getIndexSong()) || 0,
            playlists: h.playlists,
            notice: h.notice,
        });
    };

    h.queue = () => {
        const p = player();
        const tracks = (p && p.getTrackList()) || [];
        return JSON.stringify({
            index: p ? Number(p.getIndexSong()) || 0 : 0,
            tracks: tracks.map(s => ({
                title: s.SNG_TITLE + (s.VERSION ? ' ' + s.VERSION : ''),
                artist: s.ART_NAME || '',
                cover: coverUrl(s.ALB_PICTURE, 120),
                duration: Number(s.DURATION) || 0,
            })),
        });
    };

    h.togglePause = () => player().control.togglePause();
    h.next = () => player().control.nextSong();
    h.previous = () => player().control.prevSong();
    h.toggleShuffle = () => player().control.setShuffle(!player().isShuffle());
    // Deezer cycles 0 (off) -> 1 (repeat all) -> 2 (repeat one).
    h.cycleRepeat = () => player().control.setRepeat((Number(player().getRepeat()) + 1) % 3);
    h.setVolume = volume => {
        const p = player();
        p.control.setVolume(Math.max(0, Math.min(1, volume)));
        if (p.isMuted() && volume > 0) {
            p.control.mute(false);
        }
    };
    h.toggleMute = () => player().control.mute(!player().isMuted());
    // Deezer's player takes a fraction of the track (seek({percent}), capped at 1).
    h.seek = fraction => player().control.seek(Math.max(0, Math.min(1, fraction)));
    h.playQueueIndex = index => player().playTrackAtIndex(index);

    // Clicking Deezer's own heart lets the page pick the right API
    // (song.addFavorites or favorite_song.add) and keeps its UI in sync.
    h.toggleFavorite = () => {
        const fav = favoriteButton();
        if (fav) {
            fav.click();
        }
    };

    h.loadPlaylists = async () => {
        try {
            if (!h.user) {
                await gw('deezer.getUserData', {});
            }
            const me = String(h.user.USER_ID);
            const loved = String(h.user.LOVEDTRACKS_ID);
            const results = await gw('deezer.pageProfile', { USER_ID: me, tab: 'playlists', nb: 500 });
            const data = (results.TAB && results.TAB.playlists && results.TAB.playlists.data) || [];
            h.playlists = data
                .filter(pl => String(pl.PARENT_USER_ID) === me && String(pl.PLAYLIST_ID) !== loved)
                .map(pl => ({ id: String(pl.PLAYLIST_ID), title: pl.TITLE, count: Number(pl.NB_SONG) || 0 }));
        } catch (e) {
            console.warn('[dzPlasmoid] loadPlaylists failed', e);
        }
    };

    h.addToPlaylist = async (playlistId, playlistTitle) => {
        const song = player().getCurrentSong();
        if (!song || !song.SNG_ID) {
            return;
        }
        try {
            // Same payload as the web app: [songId, 0] appended at the end (offset -1).
            await gw('playlist.addSongs', { playlist_id: playlistId, songs: [[String(song.SNG_ID), 0]], offset: -1 });
            notify('added', playlistTitle);
            h.loadPlaylists();
        } catch (e) {
            console.warn('[dzPlasmoid] addToPlaylist failed', e);
            notify('error', playlistTitle);
        }
    };
})();
