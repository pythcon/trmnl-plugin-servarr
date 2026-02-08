# Terminus / BYOS Setup

Guide for using the Servarr collector with a self-hosted
[Terminus (BYOS)](https://github.com/usetrmnl/byos_hanami) instance.

## Architecture

Instead of pushing data to TRMNL cloud webhooks, the collector runs a
lightweight HTTP server. A Terminus Extension polls this endpoint for
JSON data and renders the same Liquid templates server-side.

```
Servarr APIs → Collector ←── GET JSON ── Terminus Extension → render → device
```

## 1. Configure the Collector

In your `config.yaml`, enable serve mode and remove or omit the `webhook` field:

```yaml
interval: 900
timezone: America/New_York

serve:
  enabled: true
  port: 8080

instances:
  - name: sonarr
    url: http://sonarr:8989
    api_key: your-api-key
    # webhook is not needed in serve mode
```

## 2. Run with Docker Compose

```yaml
services:
  trmnl-collector:
    image: ghcr.io/pythcon/trmnl-servarr-collector:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    environment:
      - TZ=America/New_York
      - SERVE_PORT=8080
```

Or set `SERVE_PORT=8080` to enable serve mode without a config file.

## 3. Verify the Endpoint

```bash
curl http://localhost:8080/
# Returns: {"instances": {"sonarr": "/data/sonarr"}}

curl http://localhost:8080/data/sonarr
# Returns: {"app_name": "Sonarr", "queue": {...}, ...}
```

> **Note:** The first request after startup may return 404 until the
> first collection cycle completes (up to `interval` seconds).

## 4. Create a Terminus Extension

1. Open your Terminus dashboard
2. Go to **Extensions → New Extension**
3. Configure:
   - **Name:** Servarr - Sonarr (or your app name)
   - **URI:** `http://trmnl-collector:8080/data/sonarr`
   - **Kind:** Poll
   - **Schedule:** 15 minutes (match your collector interval)
   - **Template:** paste the contents of `src/full.liquid`
   - **Model:** select your device model
4. Save and add the generated screen to your device playlist

Repeat for each Servarr instance (radarr, lidarr, etc.), using the
appropriate `/data/<name>` path.

## Template Notes

The existing Liquid templates work on Terminus with these caveats:

- **Settings:** All `trmnl.plugin_settings` values have `| default:` fallbacks,
  so defaults activate automatically (Dashboard mode, all sections shown, 3 items each).
- **Timestamps:** `trmnl.user.utc_offset` is not available on Terminus. The collector
  includes a `last_updated_local` field with a pre-formatted local timestamp as a
  workaround. To use it in the template title bar, replace:
  ```liquid
  {{ last_updated | date: "%s" | plus: trmnl.user.utc_offset | date: "%Y-%m-%d %H:%M" }}
  ```
  with:
  ```liquid
  {{ last_updated_local }}
  ```
