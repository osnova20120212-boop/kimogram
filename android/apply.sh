#!/usr/bin/env bash
# Turns a clean Telegram Android checkout (DrKLO/Telegram at UPSTREAM_COMMIT) into Kimogram.
#
#   android/apply.sh <telegram-android-dir>
#
# Environment: TELEGRAM_API_ID, TELEGRAM_API_HASH (required),
#              KIMOGRAM_PACKAGE (optional, default com.kimogram.app).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(cd "$1" && pwd)"
PACKAGE="${KIMOGRAM_PACKAGE:-com.kimogram.app}"
: "${TELEGRAM_API_ID:?set TELEGRAM_API_ID}"
: "${TELEGRAM_API_HASH:?set TELEGRAM_API_HASH}"

cd "$T"

# 1. Source changes to upstream files.
for p in "$HERE"/patches/*.patch; do
  echo "applying $(basename "$p")"
  git apply --whitespace=nowarn "$p"
done

# 2. New files and replaced images (icons).
cp -R "$HERE/overlay/." "$T/"
# Upstream ships these as .webp; ours are .png with the same resource name.
find TMessagesProj/src/main/res -path '*/drawable-*' -name 'ic_launcher_dr.webp' -delete

# 3. Package name and API keys.
sed -i "s/^APP_PACKAGE=.*/APP_PACKAGE=${PACKAGE}/" gradle.properties
BV=TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java
sed -i -E "s/public static int APP_ID = [0-9]+;.*/public static int APP_ID = ${TELEGRAM_API_ID};/" "$BV"
sed -i -E "s/public static String APP_HASH = \"[0-9a-f]*\";/public static String APP_HASH = \"${TELEGRAM_API_HASH}\";/" "$BV"
grep -q "APP_ID = ${TELEGRAM_API_ID};" "$BV" || { echo "APP_ID was not set"; exit 1; }

# 4. google-services.json must list our package or the Google Services plugin fails the build.
python3 - "$PACKAGE" <<'PY'
import json, sys, copy, glob
pkg = sys.argv[1]
for path in glob.glob('*/google-services.json'):
    data = json.load(open(path))
    clients = data['client']
    if any(c['client_info']['android_client_info']['package_name'] == pkg for c in clients):
        continue
    c = copy.deepcopy(clients[0])
    c['client_info']['android_client_info']['package_name'] = pkg
    clients.append(c)
    json.dump(data, open(path, 'w'), indent=2)
PY

echo "Kimogram applied to $T (package $PACKAGE)"
