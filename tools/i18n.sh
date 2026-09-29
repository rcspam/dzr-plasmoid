#!/bin/sh
# Updates the translations: extracts the i18n() strings of the QML files into
# po/template.pot, merges them into every po/<lang>.po, then compiles each one
# into the package, where Plasma looks for them.
set -eu

cd "$(dirname "$0")/.."
ID=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Id"])')
DOMAIN="plasma_applet_$ID"

xgettext --from-code=UTF-8 --language=JavaScript --add-comments=i18n \
    -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
    --package-name="$ID" --msgid-bugs-address=https://github.com/rcspam \
    -o po/template.pot package/contents/ui/*.qml package/contents/ui/config/*.qml package/contents/config/*.qml

for po in po/*.po; do
    lang=$(basename "$po" .po)
    msgmerge --quiet --update --backup=none --no-fuzzy-matching "$po" po/template.pot
    mkdir -p "package/contents/locale/$lang/LC_MESSAGES"
    msgfmt --check -o "package/contents/locale/$lang/LC_MESSAGES/$DOMAIN.mo" "$po"
    echo "$lang: $(msgfmt --statistics -o /dev/null "$po" 2>&1)"
done
