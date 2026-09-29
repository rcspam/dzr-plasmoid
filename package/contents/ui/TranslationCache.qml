import QtQuick
import QtQuick.LocalStorage

// Machine translations of lyrics kept on disk, as in Radioglobe's cache:
// QtQuick.LocalStorage (SQLite) in plasmashell's offline storage, shared by
// every plasmoid of the process, hence the specific database name. The most
// recently used entries are kept.
QtObject {
    id: cache

    property int maxEntries: 500
    property var db: null

    function open() {
        if (!db) {
            db = LocalStorage.openDatabaseSync("deezerplasmoid", "1.0", "Deezer plasmoid lyrics translations", 10 * 1024 * 1024);
            db.transaction(tx => {
                tx.executeSql("CREATE TABLE IF NOT EXISTS translations(key TEXT PRIMARY KEY, value TEXT NOT NULL, usedAt INTEGER NOT NULL)");
            });
        }
        return db;
    }

    // The stored value, or null.
    function get(key) {
        let value = null;
        try {
            open().transaction(tx => {
                const rows = tx.executeSql("SELECT value FROM translations WHERE key = ?", [key]).rows;
                if (rows.length > 0) {
                    value = JSON.parse(rows.item(0).value);
                    tx.executeSql("UPDATE translations SET usedAt = ? WHERE key = ?", [Date.now(), key]);
                }
            });
        } catch (e) {
            console.warn("[deezer] translation cache read failed for", key, e);
        }
        return value;
    }

    // Bytes of the kept translations (the file itself only shrinks on VACUUM,
    // which LocalStorage cannot run: it wraps everything in transactions).
    function size() {
        let bytes = 0;
        try {
            open().readTransaction(tx => {
                bytes = tx.executeSql("SELECT TOTAL(LENGTH(CAST(key AS BLOB)) + LENGTH(CAST(value AS BLOB))) AS n FROM translations").rows.item(0).n;
            });
        } catch (e) {
            console.warn("[deezer] translation cache size failed", e);
        }
        return bytes;
    }

    function clear() {
        try {
            open().transaction(tx => {
                tx.executeSql("DELETE FROM translations");
            });
        } catch (e) {
            console.warn("[deezer] translation cache clear failed", e);
        }
    }

    function set(key, value) {
        try {
            open().transaction(tx => {
                tx.executeSql("INSERT OR REPLACE INTO translations(key, value, usedAt) VALUES(?, ?, ?)",
                              [key, JSON.stringify(value), Date.now()]);
                tx.executeSql("DELETE FROM translations WHERE key NOT IN "
                              + "(SELECT key FROM translations ORDER BY usedAt DESC LIMIT ?)", [maxEntries]);
            });
        } catch (e) {
            console.warn("[deezer] translation cache write failed for", key, e);
        }
    }
}
