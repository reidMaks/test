#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <LOCAL_FILE_PATH> <SERIES_SEARCH_REGEX> <SEASON_NUM> <EPISODE_NUM>"
  exit 1
fi

LOCAL_FILE="$1"
SERIES_REGEX="$2"
SEASON_NUM="$3"
EPISODE_NUM="$4"

if [ ! -f "$LOCAL_FILE" ]; then
  echo "Error: Local file not found: $LOCAL_FILE" >&2
  exit 1
fi

BASENAME="$(basename "$LOCAL_FILE")"
# Inject [x264] tag if not already present so Sonarr assigns Prefer x264 (+10 score)
if [[ ! "$BASENAME" =~ \[?[xXhH]\.?264\]? ]]; then
  STAGED_NAME="${BASENAME%.mkv} [x264].mkv"
else
  STAGED_NAME="$BASENAME"
fi

echo "==> [1/5] Looking up series '${SERIES_REGEX}' and S$(printf '%02d' "$SEASON_NUM")E$(printf '%02d' "$EPISODE_NUM") in Sonarr on QNAP..."
SONARR_KEY=$(ssh qnap 'grep -o "<ApiKey>[^<]*</ApiKey>" /share/CACHEDEV2_DATA/appdata/arr-stack/config/sonarr/config.xml | sed "s/<[^>]*>//g"')
API="http://127.0.0.1:8989/sonarr.home.arpa/api/v3"

SERIES_INFO=$(ssh qnap "curl -s '$API/series?apikey=$SONARR_KEY'" | jq -c "[.[] | select(.title | test(\"$SERIES_REGEX\"; \"i\"))][0]")
if [ "$SERIES_INFO" = "null" ] || [ -z "$SERIES_INFO" ]; then
  echo "Error: Series matching '$SERIES_REGEX' not found in Sonarr." >&2
  exit 1
fi

SERIES_ID=$(echo "$SERIES_INFO" | jq -r '.id')
SERIES_TITLE=$(echo "$SERIES_INFO" | jq -r '.title')
PROFILE_ID=$(echo "$SERIES_INFO" | jq -r '.qualityProfileId')

EPISODE_INFO=$(ssh qnap "curl -s '$API/episode?seriesId=$SERIES_ID&apikey=$SONARR_KEY'" | jq -c "[.[] | select(.seasonNumber == $SEASON_NUM and .episodeNumber == $EPISODE_NUM)][0]")
if [ "$EPISODE_INFO" = "null" ] || [ -z "$EPISODE_INFO" ]; then
  echo "Error: Season $SEASON_NUM Episode $EPISODE_NUM not found for '$SERIES_TITLE' (seriesId=$SERIES_ID)." >&2
  exit 1
fi

EPISODE_ID=$(echo "$EPISODE_INFO" | jq -r '.id')
EPISODE_TITLE=$(echo "$EPISODE_INFO" | jq -r '.title')
EXISTING_FILE_ID=$(echo "$EPISODE_INFO" | jq -r '.episodeFileId')

echo "    Found: $SERIES_TITLE (seriesId=$SERIES_ID, profileId=$PROFILE_ID) -> S$(printf '%02d' "$SEASON_NUM")E$(printf '%02d' "$EPISODE_NUM") '$EPISODE_TITLE' (episodeId=$EPISODE_ID, existingFileId=$EXISTING_FILE_ID)"

echo "==> [2/5] Uploading '$BASENAME' to QNAP staging '/share/CACHEDEV1_DATA/torrent/$STAGED_NAME'..."
scp "$LOCAL_FILE" "qnap:/share/CACHEDEV1_DATA/torrent/$STAGED_NAME"

if [ "$PROFILE_ID" != "6" ]; then
  echo "==> [3/5] Switching series '$SERIES_TITLE' from qualityProfileId=$PROFILE_ID to 6 (HD - 720p/1080p with Ukrainian Audio +1000 upgrade)..."
  ssh qnap "
    SERIES_JSON=\$(curl -s '$API/series/$SERIES_ID?apikey=$SONARR_KEY' | sed 's/\"qualityProfileId\": *[0-9]*/\"qualityProfileId\": 6/')
    curl -s -X PUT '$API/series/$SERIES_ID?apikey=$SONARR_KEY' -H 'Content-Type: application/json' -d \"\$SERIES_JSON\" >/dev/null
  "
else
  echo "==> [3/5] Series '$SERIES_TITLE' is already using qualityProfileId=6."
fi

if [ "$EXISTING_FILE_ID" != "0" ] && [ "$EXISTING_FILE_ID" != "null" ]; then
  echo "==> [4/5] Unlinking existing episodeFileId=$EXISTING_FILE_ID from Sonarr library (preserving /torrent/Downloads seed)..."
  ssh qnap "curl -s -X DELETE '$API/episodefile/$EXISTING_FILE_ID?apikey=$SONARR_KEY' >/dev/null"
else
  echo "==> [4/5] No existing episodeFile to unlink."
fi

echo "==> [5/5] Triggering Sonarr ManualImport (move) as WEBDL-1080p (+10 Prefer x264)..."
IMPORT_PAYLOAD=$(jq -n \
  --arg path "/torrent/$STAGED_NAME" \
  --argjson seriesId "$SERIES_ID" \
  --argjson episodeId "$EPISODE_ID" \
  '{
    name: "ManualImport",
    importMode: "move",
    files: [
      {
        path: $path,
        seriesId: $seriesId,
        episodeIds: [$episodeId],
        quality: {
          quality: {
            id: 3,
            name: "WEBDL-1080p",
            source: "web",
            resolution: 1080
          },
          revision: {
            version: 1,
            real: 0,
            isRepack: false
          }
        },
        languages: [
          {
            id: 30,
            name: "Ukrainian"
          }
        ]
      }
    ]
  }')

CMD_ID=$(echo "$IMPORT_PAYLOAD" | ssh qnap "curl -s -X POST '$API/command?apikey=$SONARR_KEY' -H 'Content-Type: application/json' -d @-" | jq -r '.id')
echo "    Sonarr ManualImport command queued (id=$CMD_ID). Waiting for completion..."
sleep 4

ssh qnap "curl -s '$API/episode?seriesId=$SERIES_ID&apikey=$SONARR_KEY'" \
  | jq "map(select(.id == $EPISODE_ID)) | map({episodeId: .id, seasonNumber, episodeNumber, title, hasFile, episodeFileId})"

NEW_FILE_ID=$(ssh qnap "curl -s '$API/episode?seriesId=$SERIES_ID&apikey=$SONARR_KEY'" | jq -r ".[] | select(.id == $EPISODE_ID) | .episodeFileId")
ssh qnap "curl -s '$API/episodefile/$NEW_FILE_ID?apikey=$SONARR_KEY'" \
  | jq '{id, relativePath, quality: .quality.quality.name, languages: (.languages | map(.name)), customFormats: (.customFormats | map(.name)), customFormatScore}'

echo "==> Done! Jellyfin LibraryMonitor will index the new file within ~30 seconds."
