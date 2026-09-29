# dzr-plasmoid

An unofficial Plasma 6 panel widget to listen to Deezer with your own account.

> **Not affiliated with Deezer.** This is a personal project. It is not made,
> endorsed or supported by Deezer SA, and has no link with the company.
> "Deezer" is a trademark of Deezer SA; the name only says which service the
> widget works with.

## What it is

The widget is a small web browser. It opens the regular Deezer website,
https://www.deezer.com, in an embedded Chromium view (QtWebEngine), where you
sign in with your own Deezer account. The website plays the music, as it
would in a browser tab, under your subscription and with its own protection
of the streams. The popup shows what that page offers (cover, title, queue,
lyrics) in native Plasma controls, and presses the page's buttons for you.

What it does not do:

- It does not download, record or convert music, and does not touch the
  protection of the streams.
- It contains no code or content from Deezer. Covers and lyrics are fetched
  by the page for your session and are not kept on disk; only the optional
  machine translations of lyrics are, on your computer.
- It does not give access to anything your Deezer plan does not include.

Using it, you remain bound by Deezer's Terms of Use, which allow personal,
private use only. The widget relies on the website's internal interfaces,
which are not a public API: Deezer may change them at any time, and the
widget may then stop working. Should Deezer ask for it, this project will be
taken down.

Lyrics come from Deezer (licensed by LyricFind) or, when Deezer has none or
no synced version, from LRCLIB, whose lyrics are contributed by its users.
Machine translation is optional: it sends the lyrics to the engine chosen in
the settings (Google, or your own LibreTranslate or Ollama server).

The panel icon is deezer.com's favicon, used here for personal use; it has
to be replaced before any public distribution.

This software is provided as is, without any warranty.

## How it works

The Deezer page runs hidden inside the widget and plays the audio; the popup
shows a native player fed by polling the page. The widget drives the page
through `window.dzPlayer` and the site's own calls, none of which is a public
Deezer API. All page-side scripts live in `package/contents/code/page.js`.

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

Sign in once through the Deezer page button at the top of the popup. The
session is stored in the `deezer-plasmoid` QtWebEngine profile of the host
process.

## Translations

`tools/i18n.sh` extracts the `i18n()` strings into `po/template.pot`, merges
them into each `po/<lang>.po` and compiles the `.mo` files into
`package/contents/locale`. Plasma only loads them from an installed package,
not when `plasmoidviewer` runs the source folder.

## Settings

General: the Deezer site language (the system's by default, English when
Deezer does not have it) and the panel icon's wheel. Lyrics: the machine
translation engine (Google, a LibreTranslate or an Ollama server, or none),
whether Deezer's own lyrics may be sent to it, the lyrics look, and the
translation cache. Storage: the web engine's HTTP cache, its limit and a
button to empty it.
