#!/usr/bin/env bash
#
# TRMNL Servarr Collector
# Collects data from Servarr applications and sends to TRMNL webhook
#
# Usage:
#   ./trmnl-servarr-collector.sh -u <servarr_url> -k <api_key> -w <webhook_url> [-t <type>]
#
# Arguments:
#   -u, --url       Servarr instance URL (e.g., http://localhost:8989)
#   -k, --api-key   Servarr API key
#   -w, --webhook   TRMNL webhook URL
#   -t, --type      App type (sonarr|radarr|lidarr|readarr|prowlarr) - auto-detected if not provided
#   -d, --days      Calendar days to fetch (default: 7)
#   -z, --timezone  Timezone for date calculations (default: system timezone)
#   -i, --interval  Run continuously with this interval in seconds (e.g., 900 for 15 min)
#   -h, --help      Show this help message
#
# Supports: Sonarr, Radarr, Lidarr, Readarr, Prowlarr
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default values
CALENDAR_DAYS=7
APP_TYPE=""
SERVARR_URL=""
API_KEY=""
WEBHOOK_URL=""
TIMEZONE=""  # Empty = use system timezone
INTERVAL=0  # 0 means run once, >0 means loop with sleep
VERBOSE=false  # Show detailed error responses

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Get date in configured timezone (or system timezone if not set)
# Usage: get_date [date arguments]
# Example: get_date +%Y-%m-%d
get_date() {
    if [[ -n "$TIMEZONE" ]]; then
        TZ="$TIMEZONE" date "$@"
    else
        date "$@"
    fi
}

# Get timezone offset in seconds
get_timezone_offset() {
    local offset_str
    offset_str=$(get_date +%z)
    # Convert +0500 or -0800 to seconds
    local sign="${offset_str:0:1}"
    local hours="${offset_str:1:2}"
    local mins="${offset_str:3:2}"
    local total_seconds=$(( (10#$hours * 3600) + (10#$mins * 60) ))
    if [[ "$sign" == "-" ]]; then
        total_seconds=$(( -total_seconds ))
    fi
    echo "$total_seconds"
}

# Get timezone name
get_timezone_name() {
    if [[ -n "$TIMEZONE" ]]; then
        echo "$TIMEZONE"
    else
        # Try to get system timezone name
        if [[ -f /etc/timezone ]]; then
            cat /etc/timezone
        elif [[ -L /etc/localtime ]]; then
            readlink /etc/localtime | sed 's|.*/zoneinfo/||'
        else
            get_date +%Z
        fi
    fi
}

# Show help message
show_help() {
    cat << EOF
TRMNL Servarr Collector v${VERSION}

Collects data from Servarr applications and sends to TRMNL webhook.

Usage:
  $(basename "$0") -u <url> -k <api_key> [-w <webhook_url>] [-t <type>] [-d <days>]

Required Arguments:
  -u, --url       Servarr instance URL (e.g., http://localhost:8989)
  -k, --api-key   Servarr API key (found in Settings > General)

Optional Arguments:
  -w, --webhook   TRMNL webhook URL (from plugin settings)
                  If not provided, JSON is printed to terminal
  -t, --type      App type: sonarr, radarr, lidarr, readarr, prowlarr
                  (auto-detected if not provided)
  -d, --days      Number of days for calendar lookup (default: 7)
  -z, --timezone  Timezone for date calculations (e.g., America/New_York)
                  Defaults to system timezone if not specified
  -i, --interval  Run continuously with this sleep interval in seconds
                  (e.g., 900 for 15 minutes). If not set, runs once and exits.
  -v, --verbose   Enable verbose output (show response bodies on errors)
  -h, --help      Show this help message

Examples:
  # Output data to terminal for debugging (no webhook)
  $(basename "$0") -u http://localhost:8989 -k abc123

  # Sonarr with auto-detection (runs once)
  $(basename "$0") -u http://localhost:8989 -k abc123 -w https://usetrmnl.com/api/custom_plugins/xxx

  # Radarr with explicit type
  $(basename "$0") -u http://localhost:7878 -k xyz789 -w https://usetrmnl.com/api/custom_plugins/yyy -t radarr

  # Run continuously every 15 minutes (900 seconds)
  $(basename "$0") -u http://sonarr:8989 -k key123 -w https://... -i 900

  # With 14-day calendar, running every 30 minutes
  $(basename "$0") -u http://sonarr:8989 -k key123 -w https://... -d 14 -i 1800

  # With specific timezone (useful when server is in different TZ than user)
  $(basename "$0") -u http://sonarr:8989 -k key123 -w https://... -z America/New_York

Docker/Container Usage:
  Run the container with -i flag to keep it running continuously

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                SERVARR_URL="$2"
                shift 2
                ;;
            -k|--api-key)
                API_KEY="$2"
                shift 2
                ;;
            -w|--webhook)
                WEBHOOK_URL="$2"
                shift 2
                ;;
            -t|--type)
                APP_TYPE="$2"
                shift 2
                ;;
            -d|--days)
                CALENDAR_DAYS="$2"
                shift 2
                ;;
            -z|--timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$SERVARR_URL" ]]; then
        log_error "Missing required argument: --url"
        exit 1
    fi
    if [[ -z "$API_KEY" ]]; then
        log_error "Missing required argument: --api-key"
        exit 1
    fi
    # Remove trailing slash from URL
    SERVARR_URL="${SERVARR_URL%/}"
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install them and try again."
        exit 1
    fi
}

# Make API request to Servarr
api_request() {
    local endpoint="$1"
    local url="${SERVARR_URL}${endpoint}"

    curl -s -f -X GET "$url" \
        -H "X-Api-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        2>/dev/null || echo "{}"
}

# Detect app type from system status
detect_app_type() {
    if [[ -n "$APP_TYPE" ]]; then
        echo "$APP_TYPE"
        return
    fi

    local status
    status=$(api_request "/api/v3/system/status")

    if [[ -z "$status" || "$status" == "{}" ]]; then
        # Try v1 API (Lidarr, Readarr, Prowlarr)
        status=$(api_request "/api/v1/system/status")
    fi

    local app_name
    app_name=$(echo "$status" | jq -r '.appName // empty' | tr '[:upper:]' '[:lower:]')

    if [[ -z "$app_name" ]]; then
        log_error "Could not detect app type. Please specify with --type"
        exit 1
    fi

    echo "$app_name"
}

# Get API version based on app type
get_api_version() {
    local app_type="$1"
    case "$app_type" in
        sonarr|radarr)
            echo "v3"
            ;;
        lidarr|readarr|prowlarr)
            echo "v1"
            ;;
        *)
            echo "v3"
            ;;
    esac
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    if [[ -z "$bytes" || "$bytes" == "null" ]]; then
        echo "--"
        return
    fi

    if (( bytes >= 1099511627776 )); then
        echo "$(echo "scale=1; $bytes / 1099511627776" | bc) TB"
    elif (( bytes >= 1073741824 )); then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    else
        echo "$(echo "scale=1; $bytes / 1024" | bc) KB"
    fi
}

# Calculate days until a date (uses configured timezone)
days_until() {
    local target_date="$1"
    local today
    today=$(get_date +%Y-%m-%d)

    # Extract just the date part if it has time
    target_date="${target_date%%T*}"

    local today_epoch
    local target_epoch
    today_epoch=$(get_date -j -f "%Y-%m-%d" "$today" "+%s" 2>/dev/null || get_date -d "$today" "+%s" 2>/dev/null)
    target_epoch=$(get_date -j -f "%Y-%m-%d" "$target_date" "+%s" 2>/dev/null || get_date -d "$target_date" "+%s" 2>/dev/null)

    echo $(( (target_epoch - today_epoch) / 86400 ))
}

# Fetch and transform queue data
fetch_queue() {
    local api_version="$1"
    local app_type="$2"
    local queue_data

    # Build include params based on app type (like fetch_recently_added)
    local include_params=""
    case "$app_type" in
        sonarr)
            include_params="&includeSeries=true&includeEpisode=true"
            ;;
        radarr)
            include_params="&includeMovie=true"
            ;;
        lidarr)
            include_params="&includeArtist=true&includeAlbum=true"
            ;;
        readarr)
            include_params="&includeAuthor=true&includeBook=true"
            ;;
    esac

    queue_data=$(api_request "/api/${api_version}/queue?pageSize=20&includeUnknownSeriesItems=false${include_params}")

    if [[ -z "$queue_data" || "$queue_data" == "{}" ]]; then
        echo '{"count": 0, "items": []}'
        return
    fi

    local count
    count=$(echo "$queue_data" | jq '.totalRecords // .records | length // 0')

    # Format titles per app type using the included series/movie/artist/author data
    local items
    case "$app_type" in
        sonarr)
            items=$(echo "$queue_data" | jq '[.records[:10] | .[] | {
                title: (
                    if .series.title then
                        "\(.series.title) [S\(.episode.seasonNumber // 0 | tostring | if length == 1 then "0" + . else . end)E\(.episode.episodeNumber // 0 | tostring | if length == 1 then "0" + . else . end)]"
                    else
                        .title // "Unknown"
                    end
                ),
                quality: (.quality.quality.name // "Unknown"),
                status: (.status // "unknown"),
                progress: (if .size > 0 then (((.size - .sizeleft) / .size * 100) | floor) else 0 end),
                eta: (.timeleft // "pending")
            }]')
            ;;
        radarr)
            items=$(echo "$queue_data" | jq '[.records[:10] | .[] | {
                title: (
                    if .movie.title then
                        "\(.movie.title) (\(.movie.year // ""))"
                    else
                        .title // "Unknown"
                    end
                ),
                quality: (.quality.quality.name // "Unknown"),
                status: (.status // "unknown"),
                progress: (if .size > 0 then (((.size - .sizeleft) / .size * 100) | floor) else 0 end),
                eta: (.timeleft // "pending")
            }]')
            ;;
        lidarr)
            items=$(echo "$queue_data" | jq '[.records[:10] | .[] | {
                title: (
                    if .artist.artistName then
                        "\(.artist.artistName) - \(.album.title // "Unknown Album")"
                    else
                        .title // "Unknown"
                    end
                ),
                quality: (.quality.quality.name // "Unknown"),
                status: (.status // "unknown"),
                progress: (if .size > 0 then (((.size - .sizeleft) / .size * 100) | floor) else 0 end),
                eta: (.timeleft // "pending")
            }]')
            ;;
        readarr)
            items=$(echo "$queue_data" | jq '[.records[:10] | .[] | {
                title: (
                    if .author.authorName then
                        "\(.author.authorName) - \(.book.title // "Unknown Book")"
                    else
                        .title // "Unknown"
                    end
                ),
                quality: (.quality.quality.name // "Unknown"),
                status: (.status // "unknown"),
                progress: (if .size > 0 then (((.size - .sizeleft) / .size * 100) | floor) else 0 end),
                eta: (.timeleft // "pending")
            }]')
            ;;
        *)
            # Default fallback for prowlarr or unknown types
            items=$(echo "$queue_data" | jq '[.records[:10] | .[] | {
                title: (.title // "Unknown"),
                quality: (.quality.quality.name // "Unknown"),
                status: (.status // "unknown"),
                progress: (if .size > 0 then (((.size - .sizeleft) / .size * 100) | floor) else 0 end),
                eta: (.timeleft // "pending")
            }]')
            ;;
    esac

    jq -n --argjson count "$count" --argjson items "$items" \
        '{count: $count, items: $items}'
}

# Fetch and transform calendar data (uses configured timezone for date calculations)
fetch_calendar() {
    local api_version="$1"
    local app_type="$2"

    local start_date
    local end_date
    start_date=$(get_date +%Y-%m-%d)
    end_date=$(get_date -v+${CALENDAR_DAYS}d +%Y-%m-%d 2>/dev/null || get_date -d "+${CALENDAR_DAYS} days" +%Y-%m-%d 2>/dev/null)

    local calendar_data
    calendar_data=$(api_request "/api/${api_version}/calendar?start=${start_date}&end=${end_date}&unmonitored=false&includeSeries=true")

    if [[ -z "$calendar_data" || "$calendar_data" == "[]" ]]; then
        echo '{"count": 0, "items": []}'
        return
    fi

    local count
    count=$(echo "$calendar_data" | jq 'length')

    local items
    case "$app_type" in
        sonarr)
            items=$(echo "$calendar_data" | jq --arg today "$(get_date +%Y-%m-%d)" '[.[:10] | .[] | {
                title: "\(.series.title // "Unknown") [S\(.seasonNumber | tostring | if length == 1 then "0" + . else . end)E\(.episodeNumber | tostring | if length == 1 then "0" + . else . end)]",
                air_date: (.airDateUtc // .airDate | split("T")[0]),
                air_date_time: (.airDateUtc // .airDate // null),
                network: (.series.network // null),
                days_until: 0
            }]')
            ;;
        radarr)
            items=$(echo "$calendar_data" | jq '[.[:10] | .[] | {
                title: "\(.title) (\(.year))",
                air_date: ((.digitalRelease // .physicalRelease // .inCinemas) | split("T")[0]),
                air_date_time: (.digitalRelease // .physicalRelease // .inCinemas // null),
                days_until: 0
            }]')
            ;;
        lidarr)
            items=$(echo "$calendar_data" | jq '[.[:10] | .[] | {
                title: "\(.artist.artistName) - \(.title)",
                air_date: (.releaseDate | split("T")[0]),
                air_date_time: (.releaseDate // null),
                days_until: 0
            }]')
            ;;
        readarr)
            items=$(echo "$calendar_data" | jq '[.[:10] | .[] | {
                title: "\(.author.authorName) - \(.title)",
                air_date: (.releaseDate | split("T")[0]),
                air_date_time: (.releaseDate // null),
                days_until: 0
            }]')
            ;;
        *)
            items='[]'
            ;;
    esac

    # Calculate days_until for each item (using configured timezone for "today")
    items=$(echo "$items" | jq --arg today "$(get_date +%Y-%m-%d)" '[.[] | . + {
        days_until: (
            ((.air_date | strptime("%Y-%m-%d") | mktime) - ($today | strptime("%Y-%m-%d") | mktime)) / 86400 | floor
        )
    }]')

    jq -n --argjson count "$count" --argjson items "$items" \
        '{count: $count, items: $items}'
}

# Fetch health status
fetch_health() {
    local api_version="$1"
    local health_data

    health_data=$(api_request "/api/${api_version}/health")

    local issue_count
    issue_count=$(echo "$health_data" | jq 'if type == "array" then length else 0 end')

    local status="ok"
    if [[ "$issue_count" -gt 0 ]]; then
        local has_error
        has_error=$(echo "$health_data" | jq '[.[] | select(.type == "error")] | length')
        if [[ "$has_error" -gt 0 ]]; then
            status="error"
        else
            status="warning"
        fi
    fi

    jq -n --arg status "$status" \
        '{status: $status}'
}

# Fetch Sonarr statistics
fetch_stats_sonarr() {
    local series_data
    series_data=$(api_request "/api/v3/series")

    local total_series
    local total_episodes=0
    local episodes_on_disk=0
    local episodes_missing=0
    local monitored_missing=0
    local library_size=0

    total_series=$(echo "$series_data" | jq 'length')

    # Calculate totals from series data
    local stats
    stats=$(echo "$series_data" | jq '{
        total_episodes: [.[].statistics.totalEpisodeCount // 0] | add,
        episodes_on_disk: [.[].statistics.episodeFileCount // 0] | add,
        library_size: [.[].statistics.sizeOnDisk // 0] | add
    }')

    total_episodes=$(echo "$stats" | jq '.total_episodes')
    episodes_on_disk=$(echo "$stats" | jq '.episodes_on_disk')
    library_size=$(echo "$stats" | jq '.library_size')
    episodes_missing=$((total_episodes - episodes_on_disk))

    # Get monitored missing count
    local wanted_data
    wanted_data=$(api_request "/api/v3/wanted/missing?pageSize=1")
    monitored_missing=$(echo "$wanted_data" | jq '.totalRecords // 0')

    local size_formatted
    size_formatted=$(format_bytes "$library_size")

    jq -n \
        --argjson total_series "$total_series" \
        --argjson total_episodes "$total_episodes" \
        --argjson episodes_on_disk "$episodes_on_disk" \
        --argjson episodes_missing "$episodes_missing" \
        --argjson monitored_missing "$monitored_missing" \
        --argjson library_size "$library_size" \
        --arg library_size_formatted "$size_formatted" \
        '{
            total_series: $total_series,
            total_episodes: $total_episodes,
            episodes_on_disk: $episodes_on_disk,
            episodes_missing: $episodes_missing,
            monitored_missing: $monitored_missing,
            library_size_bytes: $library_size,
            library_size_formatted: $library_size_formatted
        }'
}

# Fetch Radarr statistics
fetch_stats_radarr() {
    local movie_data
    movie_data=$(api_request "/api/v3/movie")

    local total_movies
    local movies_on_disk=0
    local movies_missing=0
    local monitored_missing=0
    local library_size=0

    total_movies=$(echo "$movie_data" | jq 'length')
    movies_on_disk=$(echo "$movie_data" | jq '[.[] | select(.hasFile == true)] | length')
    movies_missing=$((total_movies - movies_on_disk))
    library_size=$(echo "$movie_data" | jq '[.[].sizeOnDisk // 0] | add')

    # Get monitored missing count
    local wanted_data
    wanted_data=$(api_request "/api/v3/wanted/missing?pageSize=1")
    monitored_missing=$(echo "$wanted_data" | jq '.totalRecords // 0')

    local size_formatted
    size_formatted=$(format_bytes "$library_size")

    jq -n \
        --argjson total_movies "$total_movies" \
        --argjson movies_on_disk "$movies_on_disk" \
        --argjson movies_missing "$movies_missing" \
        --argjson monitored_missing "$monitored_missing" \
        --argjson library_size "$library_size" \
        --arg library_size_formatted "$size_formatted" \
        '{
            total_movies: $total_movies,
            movies_on_disk: $movies_on_disk,
            movies_missing: $movies_missing,
            monitored_missing: $monitored_missing,
            library_size_bytes: $library_size,
            library_size_formatted: $library_size_formatted
        }'
}

# Fetch Lidarr statistics
fetch_stats_lidarr() {
    local artist_data
    artist_data=$(api_request "/api/v1/artist")

    local total_artists
    total_artists=$(echo "$artist_data" | jq 'length')

    local stats
    stats=$(echo "$artist_data" | jq '{
        total_albums: [.[].statistics.albumCount // 0] | add,
        total_tracks: [.[].statistics.trackCount // 0] | add,
        library_size: [.[].statistics.sizeOnDisk // 0] | add
    }')

    local total_albums
    local total_tracks
    local library_size
    total_albums=$(echo "$stats" | jq '.total_albums')
    total_tracks=$(echo "$stats" | jq '.total_tracks')
    library_size=$(echo "$stats" | jq '.library_size')

    # Get monitored missing count
    local wanted_data
    wanted_data=$(api_request "/api/v1/wanted/missing?pageSize=1")
    local monitored_missing
    monitored_missing=$(echo "$wanted_data" | jq '.totalRecords // 0')

    local size_formatted
    size_formatted=$(format_bytes "$library_size")

    jq -n \
        --argjson total_artists "$total_artists" \
        --argjson total_albums "$total_albums" \
        --argjson total_tracks "$total_tracks" \
        --argjson monitored_missing "$monitored_missing" \
        --argjson library_size "$library_size" \
        --arg library_size_formatted "$size_formatted" \
        '{
            total_artists: $total_artists,
            total_albums: $total_albums,
            total_tracks: $total_tracks,
            monitored_missing: $monitored_missing,
            library_size_bytes: $library_size,
            library_size_formatted: $library_size_formatted
        }'
}

# Fetch Readarr statistics
fetch_stats_readarr() {
    local author_data
    author_data=$(api_request "/api/v1/author")

    local book_data
    book_data=$(api_request "/api/v1/book")

    local total_authors
    total_authors=$(echo "$author_data" | jq 'length')

    local total_books
    local books_on_disk
    total_books=$(echo "$book_data" | jq 'length')
    books_on_disk=$(echo "$book_data" | jq '[.[] | select(.statistics.bookFileCount > 0)] | length')

    local library_size
    library_size=$(echo "$author_data" | jq '[.[].statistics.sizeOnDisk // 0] | add')

    # Get monitored missing count
    local wanted_data
    wanted_data=$(api_request "/api/v1/wanted/missing?pageSize=1")
    local monitored_missing
    monitored_missing=$(echo "$wanted_data" | jq '.totalRecords // 0')

    local size_formatted
    size_formatted=$(format_bytes "$library_size")

    jq -n \
        --argjson total_authors "$total_authors" \
        --argjson total_books "$total_books" \
        --argjson books_on_disk "$books_on_disk" \
        --argjson monitored_missing "$monitored_missing" \
        --argjson library_size "$library_size" \
        --arg library_size_formatted "$size_formatted" \
        '{
            total_authors: $total_authors,
            total_books: $total_books,
            books_on_disk: $books_on_disk,
            monitored_missing: $monitored_missing,
            library_size_bytes: $library_size,
            library_size_formatted: $library_size_formatted
        }'
}

# Fetch Prowlarr statistics
fetch_stats_prowlarr() {
    local indexer_data
    indexer_data=$(api_request "/api/v1/indexer")

    local stats_data
    stats_data=$(api_request "/api/v1/indexerstats")

    local total_indexers
    local enabled_indexers
    total_indexers=$(echo "$indexer_data" | jq 'length')
    enabled_indexers=$(echo "$indexer_data" | jq '[.[] | select(.enable == true)] | length')

    local total_grabs=0
    local total_queries=0
    local failed_grabs=0
    local failed_queries=0

    if [[ -n "$stats_data" && "$stats_data" != "{}" ]]; then
        total_grabs=$(echo "$stats_data" | jq '[.indexers[].numberOfGrabs // 0] | add // 0')
        total_queries=$(echo "$stats_data" | jq '[.indexers[].numberOfQueries // 0] | add // 0')
        failed_grabs=$(echo "$stats_data" | jq '[.indexers[].numberOfFailedGrabs // 0] | add // 0')
        failed_queries=$(echo "$stats_data" | jq '[.indexers[].numberOfFailedQueries // 0] | add // 0')
    fi

    jq -n \
        --argjson total_indexers "$total_indexers" \
        --argjson enabled_indexers "$enabled_indexers" \
        --argjson total_grabs "$total_grabs" \
        --argjson total_queries "$total_queries" \
        --argjson failed_grabs "$failed_grabs" \
        --argjson failed_queries "$failed_queries" \
        '{
            total_indexers: $total_indexers,
            enabled_indexers: $enabled_indexers,
            total_grabs: $total_grabs,
            total_queries: $total_queries,
            failed_grabs: $failed_grabs,
            failed_queries: $failed_queries
        }'
}

# Fetch statistics based on app type
fetch_stats() {
    local app_type="$1"

    case "$app_type" in
        sonarr)
            fetch_stats_sonarr
            ;;
        radarr)
            fetch_stats_radarr
            ;;
        lidarr)
            fetch_stats_lidarr
            ;;
        readarr)
            fetch_stats_readarr
            ;;
        prowlarr)
            fetch_stats_prowlarr
            ;;
        *)
            echo '{}'
            ;;
    esac
}

# Helper function to calculate relative time (uses configured timezone)
calc_relative_time() {
    local event_date="$1"
    local result=""

    if [[ -n "$event_date" ]]; then
        local event_epoch
        local now_epoch
        event_epoch=$(get_date -j -f "%Y-%m-%dT%H:%M:%S" "${event_date%%.*}" "+%s" 2>/dev/null || get_date -d "${event_date}" "+%s" 2>/dev/null || echo "0")
        now_epoch=$(get_date "+%s")

        if [[ "$event_epoch" -gt 0 ]]; then
            local diff=$((now_epoch - event_epoch))
            if [[ "$diff" -lt 60 ]]; then
                result="Just now"
            elif [[ "$diff" -lt 3600 ]]; then
                local mins=$((diff / 60))
                result="${mins} min ago"
            elif [[ "$diff" -lt 86400 ]]; then
                local hours=$((diff / 3600))
                if [[ "$hours" -eq 1 ]]; then
                    result="1 hour ago"
                else
                    result="${hours} hours ago"
                fi
            else
                local days=$((diff / 86400))
                if [[ "$days" -eq 1 ]]; then
                    result="1 day ago"
                else
                    result="${days} days ago"
                fi
            fi
        fi
    fi
    echo "$result"
}

# Fetch recently added items
fetch_recently_added() {
    local api_version="$1"
    local app_type="$2"
    local history_data

    # Build include params based on app type
    local include_params=""
    case "$app_type" in
        sonarr)
            include_params="&includeSeries=true&includeEpisode=true"
            ;;
        radarr)
            include_params="&includeMovie=true"
            ;;
        lidarr)
            include_params="&includeArtist=true&includeAlbum=true"
            ;;
        readarr)
            include_params="&includeAuthor=true&includeBook=true"
            ;;
    esac

    # Fetch recent history and filter client-side for downloadFolderImported events
    history_data=$(api_request "/api/${api_version}/history?pageSize=50&sortKey=date&sortDirection=descending${include_params}")

    if [[ -z "$history_data" || "$history_data" == "{}" ]]; then
        echo '{"count": 0, "items": []}'
        return
    fi

    # Filter for downloadFolderImported events client-side
    local records
    records=$(echo "$history_data" | jq '[.records // [] | .[] | select(.eventType == "downloadFolderImported")][:10]')

    if [[ "$records" == "[]" || "$records" == "null" ]]; then
        echo '{"count": 0, "items": []}'
        return
    fi

    local count
    count=$(echo "$records" | jq 'length')

    # Build items array with title and relative time
    local items
    case "$app_type" in
        sonarr)
            items=$(echo "$records" | jq '[.[:6] | .[] | {
                title: (
                    if .series.title then
                        "\(.series.title) [S\(.episode.seasonNumber | tostring | if length == 1 then "0" + . else . end)E\(.episode.episodeNumber | tostring | if length == 1 then "0" + . else . end)]"
                    else
                        .sourceTitle // "Unknown"
                    end
                ),
                date: .date
            }]')
            ;;
        radarr)
            items=$(echo "$records" | jq '[.[:6] | .[] | {
                title: (
                    if .movie.title then
                        "\(.movie.title) (\(.movie.year // ""))"
                    else
                        .sourceTitle // "Unknown"
                    end
                ),
                date: .date
            }]')
            ;;
        lidarr)
            items=$(echo "$records" | jq '[.[:6] | .[] | {
                title: (
                    if .artist.artistName then
                        "\(.artist.artistName) - \(.album.title // "Unknown Album")"
                    else
                        .sourceTitle // "Unknown"
                    end
                ),
                date: .date
            }]')
            ;;
        readarr)
            items=$(echo "$records" | jq '[.[:6] | .[] | {
                title: (
                    if .author.authorName then
                        "\(.author.authorName) - \(.book.title // "Unknown Book")"
                    else
                        .sourceTitle // "Unknown"
                    end
                ),
                date: .date
            }]')
            ;;
        *)
            items=$(echo "$records" | jq '[.[:6] | .[] | {
                title: (.sourceTitle // "Unknown"),
                date: .date
            }]')
            ;;
    esac

    # Add relative time to each item
    local final_items="[]"
    while IFS= read -r item; do
        local title date time_ago
        title=$(echo "$item" | jq -r '.title')
        date=$(echo "$item" | jq -r '.date')
        time_ago=$(calc_relative_time "$date")
        final_items=$(echo "$final_items" | jq --arg title "$title" --arg time_ago "$time_ago" '. + [{title: $title, time_ago: $time_ago}]')
    done < <(echo "$items" | jq -c '.[]')

    jq -n --argjson count "$count" --argjson items "$final_items" \
        '{count: $count, items: $items}'
}

# Build and send webhook payload
send_webhook() {
    local app_type="$1"
    local api_version="$2"

    log_info "Fetching data from ${app_type}..."

    # Fetch all data
    local queue
    local calendar
    local health
    local stats
    local recently_added

    queue=$(fetch_queue "$api_version" "$app_type")
    calendar=$(fetch_calendar "$api_version" "$app_type")
    health=$(fetch_health "$api_version")
    stats=$(fetch_stats "$app_type")

    # Prowlarr doesn't have history, so skip recently_added for it
    if [[ "$app_type" != "prowlarr" ]]; then
        recently_added=$(fetch_recently_added "$api_version" "$app_type")
    else
        recently_added='{"count": 0, "items": []}'
    fi

    # Get app name with proper capitalization
    local app_name
    app_name=$(echo "$app_type" | sed 's/./\U&/')

    # Get timezone info
    local tz_name
    local tz_offset
    tz_name=$(get_timezone_name)
    tz_offset=$(get_timezone_offset)

    # Build the payload
    local payload
    payload=$(jq -n \
        --arg app_name "$app_name" \
        --arg app_type "$app_type" \
        --arg last_updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg tz_name "$tz_name" \
        --argjson tz_offset "$tz_offset" \
        --argjson health "$health" \
        --argjson queue "$queue" \
        --argjson calendar "$calendar" \
        --argjson stats "$stats" \
        --argjson recently_added "$recently_added" \
        '{
            merge_variables: {
                app_name: $app_name,
                app_type: $app_type,
                last_updated: $last_updated,
                timezone: {
                    name: $tz_name,
                    offset_seconds: $tz_offset
                },
                health: $health,
                queue: $queue,
                calendar: $calendar,
                stats: $stats,
                recently_added: $recently_added
            }
        }')

    # Calculate payload size
    local payload_size
    payload_size=$(echo -n "$payload" | wc -c | tr -d ' ')

    if [[ "$VERBOSE" == true ]]; then
        log_info "Payload size: ${payload_size} bytes"
    fi

    # If no webhook URL, output to terminal
    if [[ -z "$WEBHOOK_URL" ]]; then
        echo "$payload" | jq .
        return 0
    fi

    log_info "Sending data to TRMNL webhook..."

    # Send to webhook
    local response_file
    local http_code

    response_file=$(mktemp)
    http_code=$(curl -s -o "$response_file" -w "%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        log_info "Successfully sent data to TRMNL (HTTP $http_code)"
    else
        log_error "Failed to send data to TRMNL (HTTP $http_code)"
        if [[ "$VERBOSE" == true ]]; then
            log_error "Response body:"
            cat "$response_file" >&2
            echo "" >&2
        fi
        rm -f "$response_file"
        exit 1
    fi
    rm -f "$response_file"
}

# Run a single collection cycle
run_collection() {
    local app_type="$1"
    local api_version="$2"

    log_info "Starting collection cycle at $(date)"

    # Fetch and send data
    if send_webhook "$app_type" "$api_version"; then
        log_info "Collection cycle completed successfully"
        return 0
    else
        log_error "Collection cycle failed"
        return 1
    fi
}

# Main function
main() {
    parse_args "$@"
    check_dependencies

    log_info "TRMNL Servarr Collector v${VERSION}"
    log_info "Connecting to: ${SERVARR_URL}"

    # Detect app type
    local app_type
    app_type=$(detect_app_type)
    log_info "Detected app type: ${app_type}"

    # Get API version
    local api_version
    api_version=$(get_api_version "$app_type")
    log_info "Using API version: ${api_version}"

    # Run once or continuously based on interval
    if [[ "$INTERVAL" -gt 0 ]]; then
        log_info "Running continuously with ${INTERVAL}s interval (Ctrl+C to stop)"

        # Handle graceful shutdown
        trap 'log_info "Shutting down..."; exit 0' SIGINT SIGTERM

        while true; do
            run_collection "$app_type" "$api_version" || true
            log_info "Sleeping for ${INTERVAL} seconds..."
            sleep "$INTERVAL"
        done
    else
        # Single run mode
        run_collection "$app_type" "$api_version"
        log_info "Done!"
    fi
}

# Run main function
main "$@"
