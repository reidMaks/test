---
name: manual-media-import
description: >-
  Import manually downloaded video files (episodes or movies from Telegram Desktop
  cache or local Downloads) into the QNAP NAS media library (Sonarr, Radarr, Jellyfin)
  over SSH while preserving active torrent seeding and ensuring automatic replacement
  when an official Ukrainian torrent release appears on trackers. Trigger when the user
  asks to manually add, upload, or import a video, episode, or movie into Jellyfin/Sonarr/Radarr.
---

# Manual Media Import to QNAP Media Stack (Sonarr / Radarr / Jellyfin)

Use this skill whenever the user wants to add a manually downloaded video file (for example, an early-release episode from a Telegram dubbing sponsor channel such as `[Amanogawa]` or a file from `~/Downloads`) into the QNAP media library so it can be watched immediately in Jellyfin without breaking `qBittorrent` seeding or future automatic torrent upgrades.

---

## 1. Environment & Paths Reference

- **Local Source Locations**:
  - Flatpak Telegram Desktop cache: `/home/max/.var/app/org.telegram.desktop/data/TelegramDesktop/tdata/temp_data/`
  - Local Downloads: `/home/max/Downloads/` (or `/home/max/Завантаження/`)
- **QNAP SSH Host**: `qnap` (logs in as non-root user `max`, `uid=1000(max) gid=100(everyone)`).
- **QNAP Media Share**:
  - Host path: `/share/CACHEDEV1_DATA/torrent`
  - Container mount path (`sonarr`, `radarr`, `qbittorrent`, `jellyfin`): `/torrent`
  - Sonarr root folder: `/share/CACHEDEV1_DATA/torrent/tv-sonarr` (`/torrent/tv-sonarr` inside container)
  - Radarr root folder: `/share/CACHEDEV1_DATA/torrent/radarr` (`/torrent/radarr` inside container)
- **Permissions & Staging Caveat (CRITICAL)**:
  - Series/movie subdirectories inside `/share/CACHEDEV1_DATA/torrent/tv-sonarr/<Series>` are created by the container (`UID=0`, `admin:administrators`) with mode `0755` (`drwxr-xr-x`).
  - Direct `scp` into a series subdirectory as user `max` will fail with `Permission denied`.
  - Furthermore, uploading directly into `/share/CACHEDEV1_DATA/torrent/tv-sonarr/` triggers Jellyfin's `inotify` `LibraryMonitor` while the file is still only partially uploaded.
  - **Always `scp` the file into the world-writable share root `/share/CACHEDEV1_DATA/torrent/` (`0777`)**, which is on the same filesystem (`CACHEDEV1_DATA`) as `/torrent/tv-sonarr` and `/torrent/radarr` but outside Jellyfin's watched library folders. Then invoke Sonarr's `ManualImport` API (`importMode: "move"`), which runs as `UID=0` inside the container and performs an instant atomic `rename()` into the target series folder.
- **Service APIs on QNAP (`127.0.0.1`)**:
  - **Sonarr**: `http://127.0.0.1:8989/sonarr.home.arpa/api/v3`
    - API Key location on QNAP: `/share/CACHEDEV2_DATA/appdata/arr-stack/config/sonarr/config.xml` (`<ApiKey>...</ApiKey>`).
  - **Radarr**: `http://127.0.0.1:7878/radarr.home.arpa/api/v3`
    - API Key location on QNAP: `/share/CACHEDEV2_DATA/appdata/arr-stack/config/radarr/config.xml` (`<ApiKey>...</ApiKey>`).
  - **Jellyfin Logs**: `/share/CACHEDEV2_DATA/appdata/arr-stack/config/jellyfin/log/log_YYYYMMDD.log` (`LibraryMonitor` watches `/torrent/tv-sonarr` via `inotify` and refreshes items automatically within ~30 seconds of file changes).

---

## 2. How Sonarr Upgrade Logic Works (Early-Release / Temporary File Case)

When importing an early-release Ukrainian dub file (e.g., `Cyberpunk Edgerunners S02E02 [2160p] [Amanogawa].mkv`) that must be **automatically deleted and replaced** once the official torrent appears on trackers (e.g., Toloka):

1. **Quality Profile Must Allow Upgrades to Ukrainian Audio (`qualityProfileId = 6`)**:
   - Profile `1` (`Any`) has `upgradeAllowed: false` and `Ukrainian Audio: 0`. If a series is on Profile `1` (often default when requested via Seerr), Sonarr will **never** upgrade it.
   - Profile `6` (`HD - 720p/1080p`) has:
     - `upgradeAllowed: true`
     - `cutoff: 7` (`Bluray-1080p`)
     - `cutoffFormatScore: 1000`, `minUpgradeFormatScore: 1`
     - Custom Format scores: `Ukrainian Audio` (`\b(ukr|ua|ukrainian)\b` in release title) = **`+1000`**, `Prefer x264` (`\b(x264|h264|avc)\b`) = **`+10`**, `Russian Audio` = **`-10000`**.
   - Always ensure the target series has `qualityProfileId: 6`.

2. **Quality Tier vs. Custom Format Score (Why `WEBDL-1080p` + `[x264]` is Required)**:
   - In Sonarr, **Quality Tier always ranks higher than Custom Format Score**.
   - If a manual `[2160p]` file is registered in Sonarr with quality `WEBDL-2160p` / `HDTV-2160p`, Sonarr considers it higher quality than `1080p`. When a `1080p` Ukrainian torrent later appears on Toloka (`WEBRip-1080p` or `WEBDL-1080p` with `UKR` -> score `+1000`), Sonarr will **refuse** to downgrade from `2160p` to `1080p`.
   - Conversely, if the manual file is registered as `WEBDL-1080p` with Custom Format score `0`, an English `1080p x264` torrent (score `+10`) could overwrite the Ukrainian manual file!
   - **Solution**:
     - Tag the staged filename with `[x264]` (e.g., `Cyberpunk Edgerunners S02E02 [2160p] [x264] [Amanogawa].mkv`) so Sonarr assigns it `Prefer x264` = **`+10`**.
     - In the `ManualImport` API call, explicitly set the quality object to **`WEBDL-1080p` (`id: 3`, `source: "web"`, `resolution: 1080`)** (which belongs to the `WEB 1080p` group alongside `WEBRip-1080p`).
     - **Result**:
       - **Jellyfin** reads the real video stream headers from the `.mkv` container and plays the video in native **4K (2160p)** with the Ukrainian audio track.
       - **English torrents** (`score <= 10`) cannot overwrite the manual file (`10` is not `> 10`).
       - **Ukrainian torrents** on Toloka (`UKR` in release title -> `score >= 1000`) are in the same `WEB 1080p` (or `Bluray-1080p`) tier with `1000 > 10`, so Sonarr **automatically grabs the torrent, deletes the temporary manual `.mkv` file, and replaces it with a hardlink from `/torrent/Downloads/`**.

3. **Safe Removal of Existing Non-Ukrainian Episode Hardlinks**:
   - If Sonarr already downloaded an English/original season pack (e.g., `VARYG`), the file in `/torrent/tv-sonarr/<Series>/` is a hardlink (`links = 2`) to `/torrent/Downloads/<TorrentFolder>/`.
   - Deleting the existing `episodeFileId` via `DELETE /api/v3/episodefile/{id}` only unlinks the copy in `/torrent/tv-sonarr/<Series>/` while leaving `/torrent/Downloads/` untouched so `qBittorrent` continues seeding 100% intact.

---

## 3. Step-by-Step Workflow

You can run the bundled helper script [import_episode.sh](./scripts/import_episode.sh) or execute the steps manually.

### Option A: Using the Helper Script (Recommended)

Run [import_episode.sh](./scripts/import_episode.sh) locally:

```bash
bash /home/max/pet/IaaC/.agents/skills/manual-media-import/scripts/import_episode.sh \
  "<LOCAL_FILE_PATH>" \
  "<SERIES_SEARCH_TERM>" \
  <SEASON_NUMBER> \
  <EPISODE_NUMBER>
```

Example (for *Cyberpunk: Edgerunners* Season 2 Episode 2):
```bash
bash /home/max/pet/IaaC/.agents/skills/manual-media-import/scripts/import_episode.sh \
  "/home/max/.var/app/org.telegram.desktop/data/TelegramDesktop/tdata/temp_data/Cyberpunk Edgerunners S02E02 [2160p] [Amanogawa].mkv" \
  "Cyberpunk" \
  2 \
  2
```

### Option B: Manual API Execution Steps

1. **Locate the local video file** in `/home/max/.var/app/org.telegram.desktop/data/TelegramDesktop/tdata/temp_data/` or `~/Downloads/`.
2. **Prepare the staged filename**:
   - Ensure `[x264]` is present in the filename (before the extension) so it receives `customFormatScore: 10` (`Prefer x264`), e.g.:
     `Cyberpunk Edgerunners S02E02 [2160p] [x264] [Amanogawa].mkv`.
3. **Upload via `scp` to `/share/CACHEDEV1_DATA/torrent/` on `qnap`**:
   ```bash
   scp "<LOCAL_FILE>" "qnap:/share/CACHEDEV1_DATA/torrent/<STAGED_FILENAME>"
   ```
4. **Query Sonarr on `qnap`** for `seriesId`, `qualityProfileId`, `episodeId`, and existing `episodeFileId`:
   ```bash
   ssh qnap '
     API="http://127.0.0.1:8989/sonarr.home.arpa/api/v3"
     KEY=$(grep -o "<ApiKey>[^<]*</ApiKey>" /share/CACHEDEV2_DATA/appdata/arr-stack/config/sonarr/config.xml | sed "s/<[^>]*>//g")
     curl -s "$API/series?apikey=$KEY"
   ' | jq '.[] | select(.title | test("<SERIES_SEARCH_TERM>"; "i")) | {id, title, qualityProfileId, path}'
   ```
5. **Ensure `qualityProfileId` is `6`** (`HD - 720p/1080p`) on the series (`PUT /api/v3/series/{seriesId}`).
6. **If `episodeFileId` > 0 exists** on the target episode, delete it via `DELETE /api/v3/episodefile/{episodeFileId}` so the new file replaces it cleanly without breaking torrent seeding in `/torrent/Downloads`.
7. **Import the staged file via `POST /api/v3/command` (`ManualImport`)**:
   ```json
   {
     "name": "ManualImport",
     "importMode": "move",
     "files": [
       {
         "path": "/torrent/<STAGED_FILENAME>",
         "seriesId": 83,
         "episodeIds": [7232],
         "quality": {
           "quality": {
             "id": 3,
             "name": "WEBDL-1080p",
             "source": "web",
             "resolution": 1080
           },
           "revision": { "version": 1, "real": 0, "isRepack": false }
         },
         "languages": [{ "id": 30, "name": "Ukrainian" }]
       }
     ]
   }
   ```
8. **Verify**:
   - Check `GET /api/v3/episodefile?seriesId={seriesId}` to confirm `quality == "WEBDL-1080p"` and `customFormatScore == 10`.
   - Check `/share/CACHEDEV2_DATA/appdata/arr-stack/config/jellyfin/log/log_*.log` to confirm `LibraryMonitor` detected and refreshed the episode in Jellyfin.
