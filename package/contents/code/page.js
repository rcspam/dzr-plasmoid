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
        // Feature switches of the account (__DZR_GATEKEEPS__ of getUserData).
        gatekeeps: {},
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
            h.gatekeeps = data.results.__DZR_GATEKEEPS__ || {};
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
                h.gatekeeps = data.results.__DZR_GATEKEEPS__ || {};
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

    // Lyrics of the current track: Deezer's own first (the web app's GetLyrics
    // query, lines translated into the page language when Deezer has it), then
    // LRCLIB, a free lyrics database. Loaded on each track change.
    const LYRICS_QUERY = 'query GetLyrics($trackId: String!) { track(trackId: $trackId) { id lyrics { id text '
        + 'synchronizedLines { line lineTranslated milliseconds } licence copyright writers } } }';
    const JWT_LIFETIME = 3 * 60 * 1000;
    let pipeJwt = '';
    let pipeJwtTime = 0;

    // Short-lived token for pipe.deezer.com, renewed like the web app does.
    async function pipeToken(renew) {
        if (renew || !pipeJwt || Date.now() - pipeJwtTime > JWT_LIFETIME) {
            const response = await fetch('https://auth.deezer.com/login/renew?jo=p&rto=c&i=c',
                                         { method: 'POST', credentials: 'include' });
            pipeJwt = (await response.json()).jwt || '';
            pipeJwtTime = Date.now();
        }
        return pipeJwt;
    }

    const plainLines = text => text.split(/\r?\n/).map(line => ({ time: -1, text: line, translation: '' }));

    async function deezerLyrics(song) {
        const request = async renew => fetch('https://pipe.deezer.com/api', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                // Deezer only translates the lines when told the language.
                'Accept-Language': navigator.language,
                Authorization: 'Bearer ' + await pipeToken(renew),
            },
            body: JSON.stringify({ operationName: 'GetLyrics', query: LYRICS_QUERY, variables: { trackId: String(song.SNG_ID) } }),
        });
        let response = await request(false);
        if (response.status === 401) {
            response = await request(true);
        }
        const data = await response.json();
        const lyrics = data.data && data.data.track && data.data.track.lyrics;
        if (!lyrics) {
            return null;
        }
        const credits = { source: 'deezer', writers: lyrics.writers || '', licence: lyrics.licence || '' };
        const synced = lyrics.synchronizedLines || [];
        if (synced.length) {
            return Object.assign(credits, {
                synced: true,
                lines: synced.map(l => ({ time: l.milliseconds / 1000, text: l.line || '', translation: l.lineTranslated || '' })),
            });
        }
        return lyrics.text ? Object.assign(credits, { synced: false, lines: plainLines(lyrics.text) }) : null;
    }

    async function lrclibLyrics(song) {
        const params = new URLSearchParams({
            artist_name: song.ART_NAME || '',
            track_name: song.SNG_TITLE || '',
            album_name: song.ALB_TITLE || '',
            duration: String(song.DURATION || ''),
        });
        const response = await fetch('https://lrclib.net/api/get?' + params);
        if (!response.ok) {
            return null;
        }
        const data = await response.json();
        const credits = { source: 'lrclib', writers: '', licence: '' };
        const lines = [];
        for (const raw of (data.syncedLyrics || '').split('\n')) {
            const m = /^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/.exec(raw);
            if (m) {
                lines.push({ time: Number(m[1]) * 60 + Number(m[2]), text: m[3], translation: '' });
            }
        }
        if (lines.length) {
            return Object.assign(credits, { synced: true, lines });
        }
        return data.plainLyrics ? Object.assign(credits, { synced: false, lines: plainLines(data.plainLyrics) }) : null;
    }

    // Resolves to the lyrics of a dzPlayer song object, or null. Synced lyrics
    // come first, whatever the source: Deezer sometimes only has the text,
    // which cannot follow the song, when LRCLIB has it synced. Also handy
    // from the dev tools.
    h.fetchLyrics = async song => {
        let deezer = null;
        try {
            deezer = await deezerLyrics(song);
        } catch (e) {
            console.warn('[dzPlasmoid] Deezer lyrics failed', e);
        }
        if (deezer && deezer.synced) {
            return deezer;
        }
        let lrclib = null;
        try {
            lrclib = await lrclibLyrics(song);
        } catch (e) {
            console.warn('[dzPlasmoid] LRCLIB lyrics failed', e);
        }
        if (lrclib && lrclib.synced) {
            return lrclib;
        }
        return deezer || lrclib;
    };

    // status: 'loading', 'ready' or 'missing'.
    h.lyricsState = { songId: '', status: '', data: null };
    function loadLyrics(song) {
        const songId = String(song.SNG_ID || '');
        if (!songId || songId === h.lyricsState.songId) {
            return;
        }
        h.lyricsState = { songId, status: 'loading', data: null };
        h.fetchLyrics(song).then(data => {
            if (h.lyricsState.songId === songId) {
                h.lyricsState = { songId, status: data ? 'ready' : 'missing', data };
            }
        });
    }
    h.lyrics = () => JSON.stringify(h.lyricsState);

    // Audio settings, read and changed through Deezer's own "Audio" panel: it
    // saves the choices to the account and only offers what the plan allows.
    // Null until read; queueSync is null when the account has no such option.
    h.audio = null;
    let audioReadAt = 0;
    const AUDIO_QUALITIES = { standard: 'quality_standard', high: 'quality_hq', lossless: 'quality_loseless' };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

    function readAudioPanel(menu) {
        const input = prefix => menu.querySelector(`[data-testid^="${prefix}"] input`);
        const audio = { quality: '', qualities: {}, normalize: false, queueSync: null };
        for (const [name, prefix] of Object.entries(AUDIO_QUALITIES)) {
            const radio = input(prefix);
            audio.qualities[name] = !!radio && !radio.disabled;
            if (radio && radio.checked) {
                audio.quality = name;
            }
        }
        const normalize = input('normalize_button');
        audio.normalize = !!normalize && normalize.checked;
        const queueSync = input('synchronised_button');
        audio.queueSync = queueSync ? queueSync.checked : null;
        return audio;
    }

    // Opens the panel if needed, runs change(menu), reads it back, restores it.
    async function withAudioPanel(change) {
        const button = document.querySelector('[data-testid="audio_settings_button"]');
        if (!button) {
            return;
        }
        const openMenu = () => document.querySelector('[data-testid="audio_settings_menu"]');
        const wasOpen = !!openMenu();
        if (!wasOpen) {
            button.click();
        }
        for (let i = 0; i < 20 && !openMenu(); i++) {
            await sleep(50);
        }
        const menu = openMenu();
        if (menu) {
            if (change) {
                change(menu);
                await sleep(300);
            }
            h.audio = readAudioPanel(menu);
        }
        if (!wasOpen && openMenu()) {
            button.click();
        }
    }

    h.readAudio = () => withAudioPanel(null);
    h.setQuality = quality => withAudioPanel(menu => {
        const radio = menu.querySelector(`[data-testid^="${AUDIO_QUALITIES[quality]}"] input`);
        if (radio && !radio.disabled && !radio.checked) {
            radio.click();
        }
    });
    const toggleAudioSwitch = prefix => withAudioPanel(menu => {
        const checkbox = menu.querySelector(`[data-testid^="${prefix}"] input`);
        if (checkbox) {
            checkbox.click();
        }
    });
    h.toggleNormalize = () => toggleAudioSwitch('normalize_button');
    h.toggleQueueSync = () => toggleAudioSwitch('synchronised_button');

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
        if (fav && song.SNG_ID) {
            // The heart may have changed on the page or in another player.
            setFavorite(String(song.SNG_ID), !/_off$/.test(fav.dataset.testid));
        }
        if (session === 'in') {
            loadLyrics(song);
            // The player bar may not be there yet: retried until read.
            if (!h.audio && Date.now() - audioReadAt > 5000) {
                audioReadAt = Date.now();
                h.readAudio();
            }
        }
        return JSON.stringify({
            ready: true,
            session,
            lyricsSongId: h.lyricsState.songId,
            lyricsStatus: h.lyricsState.status,
            audio: h.audio,
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

    // Loved tracks, for the hearts of the queue. Same calls as the site, which
    // picks them from the account's unlimited_favorite_tracks gatekeep.
    h.favorites = new Set();
    let favoritesAt = 0;
    const unlimitedFavorites = () => h.gatekeeps.unlimited_favorite_tracks !== false;

    async function loadFavorites() {
        favoritesAt = Date.now();
        try {
            if (!h.user) {
                await gw('deezer.getUserData', {});
            }
            const results = unlimitedFavorites()
                ? await gw('song.getFavoriteIds', { start: 0, nb: 10000 })
                : await gw('playlist.getSongs', { playlist_id: String(h.user.LOVEDTRACKS_ID), start: 0, nb: 10000 });
            h.favorites = new Set((results.data || []).map(song => String(song.SNG_ID)));
        } catch (e) {
            console.warn('[dzPlasmoid] loadFavorites failed', e);
        }
    }

    function setFavorite(id, loved) {
        if (loved) {
            h.favorites.add(id);
        } else {
            h.favorites.delete(id);
        }
    }

    h.toggleQueueFavorite = async index => {
        const p = player();
        const song = (p.getTrackList() || [])[index];
        if (!song) {
            return;
        }
        const id = String(song.SNG_ID);
        const loved = h.favorites.has(id);
        // Shown at once, undone if Deezer refuses.
        setFavorite(id, !loved);
        try {
            if (index === Number(p.getIndexSong())) {
                // The player's own heart keeps Deezer's page in step.
                h.toggleFavorite();
            } else if (unlimitedFavorites()) {
                await gw(loved ? 'song.removeFavorites' : 'song.addFavorites', { IDS: [id] });
            } else {
                await gw(loved ? 'favorite_song.remove' : 'favorite_song.add', { SNG_ID: id });
            }
        } catch (e) {
            console.warn('[dzPlasmoid] toggleQueueFavorite failed', e);
            setFavorite(id, loved);
        }
    };

    h.removeFromQueue = index => player().removeTracks(index, 1);

    h.queue = () => {
        const p = player();
        const tracks = (p && p.getTrackList()) || [];
        if (h.session === 'in' && Date.now() - favoritesAt > 60000) {
            loadFavorites();
        }
        return JSON.stringify({
            index: p ? Number(p.getIndexSong()) || 0 : 0,
            tracks: tracks.map(s => ({
                favorite: h.favorites.has(String(s.SNG_ID)),
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

    // Goes through the web app's own router: loading the URL would reload the
    // page and stop the music.
    h.showPlaylists = () => {
        const link = document.querySelector('a[href$="/library/playlists"]');
        if (link) {
            link.click();
            return;
        }
        const lang = location.pathname.split('/')[1] || 'fr';
        history.pushState(null, '', `/${lang}/library/playlists`);
        window.dispatchEvent(new PopStateEvent('popstate'));
    };

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
