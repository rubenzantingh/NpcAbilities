#!/bin/sh

set -eu

RELEASE_NAME="$1"
RELEASE_MESSAGE="$2"
FILE_PATH="./NpcAbilitiesForever.zip"

: "${CF_API_TOKEN:?CF_API_TOKEN fehlt}"
: "${CF_PROJECT_ID:?CF_PROJECT_ID muss auf die eigene CurseForge-Projekt-ID gesetzt sein}"

case "$CF_PROJECT_ID" in
  *[!0-9]*|'')
    echo "CF_PROJECT_ID muss eine numerische CurseForge-Projekt-ID sein" >&2
    exit 2
    ;;
esac

CF_METADATA=$(python3 -c '
import json, os, sys
metadata = {
    "displayName": sys.argv[1],
    "releaseType": "release",
    "changelog": sys.argv[2],
    "changelogType": "markdown",
}
versions = os.environ.get("CF_GAME_VERSIONS", "").strip()
if versions:
    metadata["gameVersions"] = [int(value.strip()) for value in versions.split(",")]
print(json.dumps(metadata))
' "$RELEASE_NAME" "$RELEASE_MESSAGE")

response=$(curl -sS \
    -o response.txt \
    -w "%{http_code}" \
    -H "X-API-TOKEN: $CF_API_TOKEN" \
    --form-string "metadata=$CF_METADATA" \
    -F "file=@$FILE_PATH" \
    "https://wow.curseforge.com/api/projects/$CF_PROJECT_ID/upload-file")

http_status=$(echo "$response" | tail -n1)

if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
  echo "CurseForge upload successful"
else
  echo "CurseForge upload failed, HTTP-code: $http_status"
  cat response.txt
  exit 1
fi
