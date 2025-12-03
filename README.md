# TRMNL Servarr Plugin

A TRMNL plugin for displaying data from Servarr applications (Sonarr, Radarr, Lidarr, Readarr) on your TRMNL e-ink device.

## Features

- Monitor download queues from your Servarr applications
- Support for multiple Servarr apps (Sonarr, Radarr, Lidarr, Readarr)
- Multiple display modes (Queue, Calendar, Activity, Stats)
- Responsive layouts for all TRMNL screen configurations

## Project Structure

```
trmnl-plugin-servarr/
├── .trmnlp.yml              # Local development configuration
├── README.md                # This file
├── bin/
│   └── dev                  # Development server startup script
└── src/
    ├── settings.yml         # Plugin metadata and custom fields
    ├── full.liquid          # Full screen layout (800x480)
    ├── half_horizontal.liquid  # Horizontal half layout (800x240)
    ├── half_vertical.liquid    # Vertical half layout (400x480)
    ├── quadrant.liquid      # Quadrant layout (400x240)
    └── shared.liquid        # Reusable template components
```

## Prerequisites

- [trmnlp](https://github.com/usetrmnl/trmnlp) - TRMNL Plugin Development Server
- Ruby 3.x (for trmnlp gem) OR Docker
- A running Servarr application (Sonarr, Radarr, etc.)

## Installation

### Using RubyGems

```bash
gem install trmnlp
```

### Using Docker

```bash
docker pull trmnl/trmnlp
```

## Development

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

### Configure Test Data

Edit `.trmnlp.yml` to customize test values:

```yaml
custom_fields:
  servarr_app: Sonarr
  servarr_url: http://localhost:8989
  api_key: your-test-api-key
  display_mode: Queue
  items_to_show: 5
```

### Mock Data for Testing

Uncomment and modify the `variables` section in `.trmnlp.yml` to test with mock data:

```yaml
variables:
  merge_variables:
    records:
      - title: "Breaking Bad S01E01"
        status: "downloading"
        size: 1000000000
        sizeleft: 500000000
      - title: "The Matrix"
        status: "queued"
        size: 2000000000
        sizeleft: 2000000000
```

## Deployment

### Login to TRMNL

```bash
trmnlp login
```

### Push to Device

```bash
trmnlp push
```

## Configuration Options

When adding this plugin to your TRMNL device, you can configure:

| Field | Description | Options |
|-------|-------------|---------|
| Servarr Application | Which app to monitor | Sonarr, Radarr, Lidarr, Readarr |
| Server URL | Base URL of your instance | e.g., `http://localhost:8989` |
| API Key | Your Servarr API key | Found in Settings > General |
| Display Mode | What to show | Queue, Calendar, Activity, Stats |
| Items to Show | Max items displayed | 1-10 |

## Layout Sizes

| Layout | Dimensions | Best For |
|--------|------------|----------|
| Full | 800x480 | Detailed queue view with table |
| Half Horizontal | 800x240 | Compact list view |
| Half Vertical | 400x480 | Narrow list with progress bars |
| Quadrant | 400x240 | Summary stats only |

## Resources

- [TRMNL Framework v2](https://usetrmnl.com/framework) - Component reference
- [TRMNL Liquid](https://github.com/usetrmnl/trmnl-liquid) - Templating guide
- [trmnlp Documentation](https://github.com/usetrmnl/trmnlp) - Development server docs
- [Plugin Import/Export](https://help.usetrmnl.com/en/articles/10542599-importing-and-exporting-private-plugins) - Sharing plugins

## License

MIT License
