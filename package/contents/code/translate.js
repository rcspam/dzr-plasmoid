.pragma library

// Machine translation of lyrics that Deezer does not translate.
//
// Each line goes as its own item, so a translation always lands on its line:
// Google's translate_a/t returns one [text, detected language] per q, and
// LibreTranslate one translatedText per entry of a q list. Google first (the
// service translate-shell uses, called in POST), the local LibreTranslate
// if Google fails.

var GOOGLE_URL = "https://translate.googleapis.com/translate_a/t?client=gtx&sl=auto&tl=";
var LIBRE_URL = "http://127.0.0.1:5000/translate";
// Lines per Google request; the chunks go in parallel.
var CHUNK = 50;

function post(url, contentType, body, callback) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return;
        }
        var data = null;
        if (xhr.status === 200) {
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                data = null;
            }
        }
        callback(data);
    };
    xhr.open("POST", url);
    xhr.setRequestHeader("Content-Type", contentType);
    xhr.send(body);
}

// Calls back with {texts, languages} (one entry per text) or null.
function google(texts, target, callback) {
    var chunks = [];
    for (var i = 0; i < texts.length; i += CHUNK) {
        chunks.push(texts.slice(i, i + CHUNK));
    }
    var results = [];
    var pending = chunks.length;
    var failed = false;
    chunks.forEach(function (chunk, n) {
        var body = chunk.map(function (text) { return "q=" + encodeURIComponent(text); }).join("&");
        post(GOOGLE_URL + target, "application/x-www-form-urlencoded;charset=utf-8", body, function (data) {
            if (failed) {
                return;
            }
            if (!Array.isArray(data) || data.length !== chunk.length) {
                failed = true;
                callback(null);
                return;
            }
            results[n] = data;
            if (--pending === 0) {
                var entries = [].concat.apply([], results);
                callback({
                    texts: entries.map(function (e) { return Array.isArray(e) ? e[0] : e; }),
                    languages: entries.map(function (e) { return Array.isArray(e) ? e[1] : ""; }),
                });
            }
        });
    });
}

function libre(texts, target, callback) {
    var body = JSON.stringify({ q: texts, source: "auto", target: target, format: "text" });
    post(LIBRE_URL, "application/json", body, function (data) {
        if (!data || !Array.isArray(data.translatedText) || data.translatedText.length !== texts.length) {
            callback(null);
            return;
        }
        callback({
            texts: data.translatedText,
            languages: (data.detectedLanguage || []).map(function (d) { return d.language; }),
        });
    });
}

// Translates lyric lines into target (e.g. "fr"). Calls back with null on
// failure, else {engine, sameLanguage, lines}: lines has one translation per
// input line ("" for empty ones), sameLanguage is true when the lyrics are
// mostly in the target language already.
function translateLines(lines, target, callback) {
    var indexes = [];
    var texts = [];
    lines.forEach(function (line, i) {
        if (line.trim() !== "") {
            indexes.push(i);
            texts.push(line);
        }
    });
    if (texts.length === 0) {
        callback(null);
        return;
    }
    function finish(engine, result) {
        var translated = lines.map(function () { return ""; });
        indexes.forEach(function (lineIndex, n) {
            translated[lineIndex] = result.texts[n] || "";
        });
        var same = result.languages.filter(function (lang) { return lang === target; }).length;
        callback({ engine: engine, sameLanguage: same > texts.length / 2, lines: translated });
    }
    google(texts, target, function (result) {
        if (result) {
            finish("Google", result);
            return;
        }
        libre(texts, target, function (fallback) {
            if (fallback) {
                finish("LibreTranslate", fallback);
            } else {
                callback(null);
            }
        });
    });
}
