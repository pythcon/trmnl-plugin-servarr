# TRMNL Servarr Plugin

A TRMNL plugin for displaying data from Servarr applications (Sonarr, Radarr, Lidarr, Readarr, Prowlarr) on your TRMNL e-ink device.

## Features

- Monitor download queues with progress bars
- View upcoming releases (calendar)
- See recently added media
- Library statistics with icons
- Health status monitoring
- Support for all Servarr apps (Sonarr, Radarr, Lidarr, Readarr, Prowlarr)
- Multiple display modes (Dashboard, Calendar Daily/Weekly/Monthly)
- Responsive layouts for all TRMNL screen configurations

## Project Structure

```
trmnl-plugin-servarr/
├── .trmnlp.yml              # Local development configuration
├── README.md                # This file
├── bin/
│   └── dev                  # Development server startup script
├── collector/
│   ├── trmnl-servarr-collector.sh  # Data collection script
│   ├── Dockerfile           # Docker build for collector
│   ├── entrypoint.sh        # Docker entrypoint
│   └── docker-compose.example.yml  # Example Docker setup
├── examples/
│   └── *.yml                # Test data examples for different modes
└── src/
    ├── settings.yml         # Plugin metadata and custom fields
    ├── full.liquid          # Full screen layout (800x480)
    ├── half_horizontal.liquid  # Horizontal half layout (800x240)
    ├── half_vertical.liquid    # Vertical half layout (400x480)
    └── quadrant.liquid      # Quadrant layout (400x240)
```

## Quick Start

### 1. Create a Private Plugin in TRMNL

1. Go to your TRMNL dashboard
2. Create a new Private Plugin
3. Copy the webhook URL

### 2. Run the Collector

The collector script fetches data from your Servarr apps and sends it to TRMNL.

#### Direct Execution

```bash
# Basic usage (outputs to terminal for debugging)
./collector/trmnl-servarr-collector.sh \
  -u http://localhost:8989 \
  -k your-api-key

# Send to TRMNL webhook
./collector/trmnl-servarr-collector.sh \
  -u http://localhost:8989 \
  -k your-api-key \
  -w https://usetrmnl.com/api/custom_plugins/your-webhook-id

# Run continuously every 15 minutes
./collector/trmnl-servarr-collector.sh \
  -u http://localhost:8989 \
  -k your-api-key \
  -w https://usetrmnl.com/api/custom_plugins/your-webhook-id \
  -i 900

# With verbose error logging
./collector/trmnl-servarr-collector.sh \
  -u http://localhost:8989 \
  -k your-api-key \
  -w https://usetrmnl.com/api/custom_plugins/your-webhook-id \
  -v
```

#### Docker

```bash
# Build the image
cd collector
docker build -t trmnl-servarr-collector .

# Run once
docker run --rm \
  -e SERVARR_URL=http://sonarr:8989 \
  -e API_KEY=your-api-key \
  -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
  trmnl-servarr-collector

# Run continuously (every 15 minutes)
docker run -d \
  -e SERVARR_URL=http://sonarr:8989 \
  -e API_KEY=your-api-key \
  -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
  -e INTERVAL=900 \
  trmnl-servarr-collector
```

See `collector/docker-compose.example.yml` for a complete Docker Compose setup.

## Collector Options

| Option | Env Variable | Description | Default |
|--------|--------------|-------------|---------|
| `-u, --url` | `SERVARR_URL` | Servarr instance URL | Required |
| `-k, --api-key` | `API_KEY` | Servarr API key | Required |
| `-w, --webhook` | `WEBHOOK_URL` | TRMNL webhook URL | None (prints to stdout) |
| `-t, --type` | `APP_TYPE` | App type (sonarr/radarr/lidarr/readarr/prowlarr) | Auto-detected |
| `-d, --days` | `CALENDAR_DAYS` | Calendar days to fetch | 7 |
| `-z, --timezone` | `TZ` | Timezone for date calculations | System timezone |
| `-i, --interval` | `INTERVAL` | Run interval in seconds (0 = run once) | 0 |
| `-v, --verbose` | - | Show response body on errors | Off |

## Plugin Configuration

When adding this plugin to your TRMNL device, you can configure:

| Field | Description | Options |
|-------|-------------|---------|
| Display Mode | Layout style | Dashboard, Calendar - Daily, Calendar - Weekly, Calendar - Monthly |
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

## Layout Sizes

| Layout | Dimensions | Best For |
|--------|------------|----------|
| Full | 800x480 | Dashboard with all sections, calendar views |
| Half Horizontal | 800x240 | Queue + stats side by side |
| Half Vertical | 400x480 | Stacked queue, calendar, stats |
| Quadrant | 400x240 | Queue count + next up + 2 stats |

## Development

### Prerequisites

- [trmnlp](https://github.com/usetrmnl/trmnlp) - TRMNL Plugin Development Server
- Ruby 3.x (for trmnlp gem) OR Docker

### Start the Development Server

```bash
# Using the dev script
./bin/dev

# Or directly with trmnlp
trmnlp serve

# Or with Docker
docker run -v $(pwd):/plugin -p 4567:4567 trmnl/trmnlp serve
```

The development server will:
- Watch for file changes in the `src/` directory
- Auto-reload templates when modified
- Render previews at `http://localhost:4567`

### Test with Example Data

Copy example data to test different display modes:

```bash
# Test Dashboard mode
cp examples/sonarr-dashboard.yml .trmnlp.yml

# Test Calendar Weekly
cp examples/sonarr-calendar-weekly.yml .trmnlp.yml

# Then run the dev server
./bin/dev
```

## Deployment

### Push Templates to TRMNL

```bash
trmnlp login
trmnlp push
```

### Set Up Continuous Collection

Use Docker Compose to run collectors for each Servarr app:

```yaml
services:
  trmnl-collector-sonarr:
    build: ./collector
    environment:
      - SERVARR_URL=http://sonarr:8989
      - API_KEY=your-api-key
      - WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx
      - INTERVAL=900
```

## Troubleshooting

### Webhook Returns Error

Use verbose mode to see the response:

```bash
./collector/trmnl-servarr-collector.sh -u ... -k ... -w ... -v
```

### Empty Data

- Check API key is correct (Settings > General in your Servarr app)
- Verify the URL is accessible from where the collector runs
- Run without `-w` to see the JSON output

### Times Are Wrong

Use the `-z` flag to set the correct timezone:

```bash
./collector/trmnl-servarr-collector.sh -u ... -k ... -w ... -z America/New_York
```

## Resources

- [TRMNL Framework v2](https://usetrmnl.com/framework) - Component reference
- [TRMNL Liquid](https://github.com/usetrmnl/trmnl-liquid) - Templating guide
- [trmnlp Documentation](https://github.com/usetrmnl/trmnlp) - Development server docs
- [Plugin Import/Export](https://help.usetrmnl.com/en/articles/10542599-importing-and-exporting-private-plugins) - Sharing plugins

## License

MIT License
