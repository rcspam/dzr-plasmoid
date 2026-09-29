.pragma library

// QML-side helpers. The page-side logic lives in page.js, injected into the
// Deezer page as window.__dzPlasmoid.

var pageUrl = "https://www.deezer.com/fr/";

// Builds a script calling window.__dzPlasmoid.<name>(...args) in the page.
function call(name, args) {
    var list = (args || []).map(function (a) { return JSON.stringify(a); }).join(",");
    return "window.__dzPlasmoid && window.__dzPlasmoid." + name + "(" + list + ")";
}

// Formats a duration in seconds as m:ss.
function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds || 0));
    var m = Math.floor(s / 60);
    s = s % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
}
