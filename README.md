# Deezer Plasmoid

A Plasma 6 panel widget for Deezer. The Deezer web page runs hidden inside the
widget (QtWebEngine) and plays the audio; the popup shows a native player
(large cover, title, progress, previous / play-pause / next).

The widget drives the page through `window.dzPlayer`, which is not a public
Deezer API. All page-side scripts live in `package/contents/code/deezer.js`.

## Run for development

```sh
cd package
QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:9333 plasmoidviewer -a . -f horizontal -l topedge
```

Open http://127.0.0.1:9333 in Chromium to get DevTools on the hidden page.
`tools/cdp_eval.py` evaluates an expression read from stdin in that page.

## Install

```sh
kpackagetool6 -t Plasma/Applet -i package/   # first time
kpackagetool6 -t Plasma/Applet -u package/   # update
```

Sign in once through the globe button in the popup. The session is stored in
the `deezer-plasmoid` QtWebEngine profile of the host process.
