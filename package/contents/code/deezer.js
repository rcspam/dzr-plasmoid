.pragma library

// QML-side helpers. The page-side logic lives in page.js, injected into the
// Deezer page as window.__dzPlasmoid.

// Languages the Deezer site takes in its address (checked on 2026-09-29);
// others get a redirect to English or a 404.
var siteLanguages = ["fr", "en", "de", "es", "it", "pt", "br", "nl", "pl", "ru", "tr", "sv", "da", "fi", "ro", "hu", "cs", "ja", "ar"];

// The configured language, else the system's when Deezer has it, else English.
function siteLanguage(configured, system) {
    if (configured) {
        return configured;
    }
    return siteLanguages.indexOf(system) >= 0 ? system : "en";
}

// The Deezer site in a language, e.g. "fr".
function pageUrl(language) {
    return "https://www.deezer.com/" + language + "/";
}

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
