# TRMNL Servarr Dashboard

A beautiful dashboard for your Servarr media stack on TRMNL e-ink displays. Monitor download queues, upcoming releases, recently added content, and library statistics from Sonarr, Radarr, Lidarr, Readarr, or Prowlarr.

![Servarr Dashboard](https://raw.githubusercontent.com/pythcon/trmnl-plugin-servarr/master/assets/trmnl-plugin-servarr2.png)

## Features

- Monitor download queues with progress bars
- View upcoming releases (calendar)
- See recently added media
- Library statistics with icons
- Health status monitoring
- Support for all Servarr apps (Sonarr, Radarr, Lidarr, Readarr, Prowlarr)
- Multiple display modes (Dashboard, Calendar Daily/Weekly/Monthly)
- Responsive layouts for all TRMNL screen configurations

## Quick Start

### 1. Install the Plugin from TRMNL

1. Go to your [TRMNL Dashboard](https://usetrmnl.com)
2. Navigate to **Plugin Directory**
3. Search for **"Servarr Dashboard"**
4. Click **Add to My Plugins**
5. Copy the **Webhook URL** from the plugin settings

### 2. Set Up the Collector

The collector fetches data from your Servarr apps and sends it to TRMNL. Run it with Docker:

```bash
# Create a directory for the collector
mkdir trmnl-servarr && cd trmnl-servarr

# Download the required files
curl -O https://raw.githubusercontent.com/pythcon/trmnl-plugin-servarr/master/collector/docker-compose.yml
curl -O https://raw.githubusercontent.com/pythcon/trmnl-plugin-servarr/master/collector/config.example.yaml

# Create your config from the example
cp config.example.yaml config.yaml
```

### 3. Configure Your Servarr Instances

Edit `config.yaml` with your Servarr details:

```yaml
# Global settings
interval: 900              # Collection interval in seconds (900 = 15 minutes)
timezone: America/New_York # Your timezone (for timestamp display)

# Instance definitions
instances:
  - name: sonarr
    url: http://localhost:8989          # Your Sonarr URL
    api_key: your-sonarr-api-key        # Settings > General > API Key
    webhook: https://usetrmnl.com/api/custom_plugins/your-webhook-id
```

**Finding your API Key:** In any Servarr app, go to **Settings > General > Security > API Key**

### 4. Start the Collector

```bash
docker compose up -d
```

That's it! The collector will now send data to your TRMNL device every 15 minutes.

## Multiple Servarr Instances

Add multiple instances to your `config.yaml`:

```yaml
interval: 900
timezone: America/New_York

instances:
  # Each instance needs its own webhook URL from a separate plugin install
  - name: sonarr
    url: http://localhost:8989
    api_key: your-sonarr-api-key
    webhook: https://usetrmnl.com/api/custom_plugins/sonarr-webhook-id

  - name: radarr
    url: http://localhost:7878
    api_key: your-radarr-api-key
    webhook: https://usetrmnl.com/api/custom_plugins/radarr-webhook-id

  - name: lidarr
    url: http://localhost:8686
    api_key: your-lidarr-api-key
    webhook: https://usetrmnl.com/api/custom_plugins/lidarr-webhook-id
```

## Configuration Reference

### Global Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `interval` | Collection interval in seconds (0 = run once) | `900` |
| `timezone` | Timezone for display (e.g., `America/New_York`, `Europe/London`) | `UTC` |

### Instance Settings

| Setting | Description | Required |
|---------|-------------|----------|
| `name` | Display name for logs | Yes |
| `url` | Servarr instance URL | Yes |
| `api_key` | Servarr API key | Yes |
| `webhook` | TRMNL webhook URL | Yes |
| `type` | App type (auto-detected if not set) | No |
| `calendar_days` | Days forward for calendar | No (default: 7) |
| `calendar_days_before` | Days back for calendar | No (default: 0) |
| `calendar_only` | Only send calendar data | No (default: false) |

### Plugin Display Settings

Configure these in your TRMNL plugin settings:

| Setting | Description | Options |
|---------|-------------|---------|
| Display Mode | Layout style | Dashboard, Calendar_Daily, Calendar_Weekly, Calendar_Monthly |
| Show Queue | Display download queue | Yes/No |
| Show Calendar | Display upcoming releases | Yes/No |
| Show Recently Added | Display recently imported media | Yes/No |
| Show Stats | Display library statistics | Yes/No |
| Max Queue Items | Maximum queue items shown | 1-10 |
| Show Network | Display TV network names | Yes/No |
| Show Quality | Display quality profiles | Yes/No |
| Show ETA | Display download time remaining | Yes/No |
| Date Format | How dates are displayed | Relative, Short, Full |

## Display Modes

### Dashboard (Default)
Three-column layout showing Queue, Recently Added/Upcoming, and Library Stats.

### Calendar - Daily
Shows all releases for the current day with times.

### Calendar - Weekly
7-day grid view (Sun-Sat) with releases on each day.

### Calendar - Monthly
Full month grid with releases marked on each day.

## Troubleshooting

### View Collector Logs

```bash
docker compose logs -f
```

### Test Without Sending to TRMNL

Run with `--dry-run` to see the JSON output:

```bash
docker compose run --rm trmnl-collector python /app/trmnl_collector.py --config /app/config.yaml --dry-run
```

### Common Issues

**"Cannot connect to..."**
- Verify your Servarr URL is accessible from the Docker container
- If using `localhost`, try using your machine's IP address or `host.docker.internal` (on Docker Desktop)

**"Authentication failed..."**
- Double-check your API key in Settings > General > API Key

**Times are wrong**
- Set the correct `timezone` in your config.yaml (e.g., `America/New_York`, `Europe/London`)

## Alternative Installation Methods

### Docker Run (Single Instance)

If you only have one Servarr instance, you can use `docker run` with environment variables instead of a config file:

```bash
docker run -d \
  --name trmnl-servarr \
  --restart unless-stopped \
  -e SERVARR_URL=http://localhost:8989 \
  -e API_KEY=your-api-key \
  -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
  -e INTERVAL=900 \
  -e TZ=America/New_York \
  ghcr.io/pythcon/trmnl-servarr-collector:latest
```

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `SERVARR_URL` | Servarr instance URL | Yes |
| `API_KEY` | Servarr API key | Yes |
| `WEBHOOK_URL` | TRMNL webhook URL | Yes |
| `APP_NAME` | Display name for title bar (e.g., "TV Shows") | No (auto from app type) |
| `INTERVAL` | Collection interval in seconds (0 = run once) | No (default: 0) |
| `TZ` | Timezone for display | No (default: UTC) |
| `APP_TYPE` | App type (sonarr/radarr/lidarr/readarr/prowlarr) | No (auto-detected) |
| `CALENDAR_DAYS` | Days forward for calendar | No (default: 7) |
| `CALENDAR_DAYS_BEFORE` | Days back for calendar | No (default: 0) |
| `CALENDAR_ONLY` | Only send calendar data (true/false) | No (default: false) |

### Python Script (No Docker)

Run the collector directly with Python if you prefer not to use Docker:

```bash
# Clone the repository
git clone https://github.com/pythcon/trmnl-plugin-servarr.git
cd trmnl-plugin-servarr/collector

# Install dependencies
pip install requests pyyaml

# Run with config file (recommended for multiple instances)
python trmnl_collector.py --config config.yaml

# Or run with CLI arguments (single instance)
python trmnl_collector.py \
  -u http://localhost:8989 \
  -k your-api-key \
  -w https://usetrmnl.com/api/custom_plugins/xxx \
  -z America/New_York \
  -i 900
```

#### CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `-C, --config` | Path to YAML config file | None |
| `-u, --url` | Servarr instance URL | Required (if no config) |
| `-k, --api-key` | Servarr API key | Required (if no config) |
| `-w, --webhook` | TRMNL webhook URL | None (prints to stdout) |
| `-n, --name` | Display name for title bar (e.g., "TV Shows") | Auto from app type |
| `-t, --type` | App type (sonarr/radarr/lidarr/readarr/prowlarr) | Auto-detected |
| `-d, --days` | Calendar days forward | 7 |
| `-b, --days-before` | Calendar days back | 0 |
| `-c, --calendar-only` | Only send calendar data | Off |
| `-z, --timezone` | Timezone for display | UTC |
| `-i, --interval` | Run interval in seconds (0 = run once) | 0 |
| `-v, --verbose` | Verbose output | Off |
| `--dry-run` | Print JSON, don't send to webhook | Off |

#### Running as a Systemd Service

To run the collector as a background service on Linux:

```bash
# Create service file
sudo tee /etc/systemd/system/trmnl-servarr.service << EOF
[Unit]
Description=TRMNL Servarr Collector
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/path/to/trmnl-plugin-servarr/collector
ExecStart=/usr/bin/python3 trmnl_collector.py --config config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable trmnl-servarr
sudo systemctl start trmnl-servarr

# Check status
sudo systemctl status trmnl-servarr
```

## Development

See the [Development Guide](docs/DEVELOPMENT.md) for information on local development and contributing.

## Resources

- [TRMNL](https://usetrmnl.com) - E-ink smart display
- [Servarr Wiki](https://wiki.servarr.com) - Sonarr, Radarr, Lidarr, Readarr, Prowlarr documentation

## License

MIT License
