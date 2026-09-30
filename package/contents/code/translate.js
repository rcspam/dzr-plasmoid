.pragma library

// Machine translation of lyrics that Deezer does not translate, with the
// engine picked in the settings. Each translation must land on its line:
// - Google (translate_a/t, the service translate-shell uses, called in POST)
//   returns one [text, detected language] per q, one q per line;
// - LibreTranslate returns one translatedText per entry of a q list;
// - Ollama gets numbered lines and its answers are matched by number, so a
//   line the model adds or drops does not shift the others.

var GOOGLE_URL = "https://translate.googleapis.com/translate_a/t?client=gtx&sl=auto&tl=";
// Lines per Google request; the chunks go in parallel.
var GOOGLE_CHUNK = 50;
// Lines per Ollama request; the chunks go one after the other.
var OLLAMA_CHUNK = 20;
// How long a whole translation may take, in ms: QML's XMLHttpRequest has no
// timeout, and a server that takes the request without answering would
// leave it working for ever. Ollama on a CPU is slow, hence its margin.
var TIME_LIMITS = { google: 30000, libretranslate: 60000, ollama: 300000 };

function timeLimit(engine) {
    return TIME_LIMITS[engine] || 60000;
}
// Ollama prompt when the settings give none. {language} and {code} are the
// target language's name and code ("français", "fr"), {lines} the lines to
// translate, numbered as "1| text"; the answer must keep these numbers.
var OLLAMA_PROMPT = "Translate these song lyrics into {language}. Answer with one line per input "
    + "line, keeping its number, as \"number| translation\", and nothing else.\n\n{lines}";

// Short fingerprint of a text (djb2), to tell prompts apart in cache keys.
function fingerprint(text) {
    var h = 5381;
    for (var i = 0; i < text.length; i++) {
        h = (h * 33 + text.charCodeAt(i)) >>> 0;
    }
    return h.toString(36);
}

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

// The engines call back with {texts, languages} (one entry per text; languages
// may be empty) or null.
function google(texts, target, options, callback) {
    var chunks = [];
    for (var i = 0; i < texts.length; i += GOOGLE_CHUNK) {
        chunks.push(texts.slice(i, i + GOOGLE_CHUNK));
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

function libreTranslate(texts, target, options, callback) {
    var body = JSON.stringify({ q: texts, source: "auto", target: target, format: "text" });
    post(options.libreTranslateUrl.replace(/\/+$/, "") + "/translate", "application/json", body, function (data) {
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

function ollama(texts, target, options, callback) {
    var url = options.ollamaUrl.replace(/\/+$/, "") + "/api/generate";
    var language = Qt.locale(target).nativeLanguageName || target;
    var template = options.ollamaPrompt || OLLAMA_PROMPT;
    // Without {lines} the prompt would come with nothing to translate.
    if (template.indexOf("{lines}") < 0) {
        template += "\n\n{lines}";
    }
    var translated = texts.map(function () { return ""; });
    var start = 0;
    function next() {
        if (start >= texts.length) {
            callback({ texts: translated, languages: [] });
            return;
        }
        var chunkStart = start;
        var chunk = texts.slice(start, start + OLLAMA_CHUNK);
        start += OLLAMA_CHUNK;
        var prompt = template.split("{language}").join(language).split("{code}").join(target)
            .split("{lines}").join(chunk.map(function (text, i) { return (i + 1) + "| " + text; }).join("\n"));
        var body = JSON.stringify({ model: options.ollamaModel, prompt: prompt, stream: false, options: { temperature: 0 } });
        post(url, "application/json", body, function (data) {
            if (!data || typeof data.response !== "string") {
                callback(null);
                return;
            }
            data.response.split("\n").forEach(function (line) {
                var m = /^\s*(\d+)\s*[|:.)]\s?(.*)$/.exec(line);
                var k = m ? Number(m[1]) - 1 : -1;
                if (k >= 0 && k < chunk.length) {
                    translated[chunkStart + k] = m[2].trim();
                }
            });
            next();
        });
    }
    next();
}

var ENGINES = {
    google: { name: "Google", run: google },
    libretranslate: { name: "LibreTranslate", run: libreTranslate },
    ollama: { name: "Ollama", run: ollama },
};

// Translates lyric lines into target (e.g. "fr") with options.engine
// ("google", "libretranslate" or "ollama"; see the settings for the other
// options). Calls back with null on failure, else {engine, sameLanguage,
// lines}: lines has one translation per input line ("" for empty ones),
// sameLanguage is true when the engine found the lyrics mostly in the target
// language already.
// Lower case, without accents, spaces or punctuation: tells a line the
// engine gave back as it was, give or take a comma.
function bare(text) {
    return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
        .replace(/[\s.,;:!?'"\u2019\u00ab\u00bb()\[\]\-\u2013\u2014\u2026]+/g, "");
}

function translateLines(lines, target, options, callback) {
    var engine = ENGINES[options.engine];
    var indexes = [];
    var texts = [];
    lines.forEach(function (line, i) {
        if (line.trim() !== "") {
            indexes.push(i);
            texts.push(line);
        }
    });
    if (!engine || texts.length === 0) {
        callback(null);
        return;
    }
    engine.run(texts, target, options, function (result) {
        if (!result) {
            callback(null);
            return;
        }
        var translated = lines.map(function () { return ""; });
        // A line given back as it was is already in the target language: no
        // copy of it under itself. Ollama does not say which language it read,
        // so these lines also tell when the lyrics are mostly in it already.
        var unchanged = 0;
        indexes.forEach(function (lineIndex, n) {
            var text = result.texts[n] || "";
            if (text !== "" && bare(text) === bare(texts[n])) {
                unchanged++;
                text = "";
            }
            translated[lineIndex] = text;
        });
        var same = result.languages.filter(function (lang) { return lang === target; }).length;
        callback({ engine: engine.name, sameLanguage: Math.max(same, unchanged) > texts.length / 2, lines: translated });
    });
}
