#!/usr/bin/env python3
"""
TRMNL Servarr Collector

Collects data from Servarr applications (Sonarr, Radarr, Lidarr, Readarr, Prowlarr)
and sends to TRMNL webhook.

Usage:
    # With config file (multiple instances)
    python trmnl_collector.py --config config.yaml

    # CLI only (single instance)
    python trmnl_collector.py -u http://sonarr:8989 -k api_key -w https://webhook_url

    # Dry run (print JSON, don't send)
    python trmnl_collector.py --config config.yaml --dry-run
"""

import argparse
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

import requests
import yaml

VERSION = "2.0.0"


class ServarrConnectionError(Exception):
    """Raised when unable to connect to Servarr API."""
    pass


class ServarrAuthenticationError(Exception):
    """Raised when API key is invalid."""
    pass


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class ServarrCollector:
    """Collector for a single Servarr instance."""

    def __init__(
        self,
        name: str,
        url: str,
        api_key: str,
        webhook: Optional[str] = None,
        app_type: Optional[str] = None,
        calendar_days: int = 7,
        calendar_days_before: int = 0,
        calendar_only: bool = False,
        timezone: Optional[str] = None,
        verbose: bool = False,
        dry_run: bool = False,
    ):
        self.name = name
        self.url = url.rstrip('/')
        self.api_key = api_key
        self.webhook = webhook
        self.app_type = app_type
        self.calendar_days = calendar_days
        self.calendar_days_before = calendar_days_before
        self.calendar_only = calendar_only
        self.timezone = timezone or os.environ.get('TZ', '')
        self.verbose = verbose
        self.dry_run = dry_run
        self.api_version = None

    def _api_request(self, endpoint: str, raise_on_error: bool = False) -> Dict[str, Any]:
        """Make API request to Servarr.

        Args:
            endpoint: API endpoint to call
            raise_on_error: If True, raise exceptions instead of returning {}

        Raises:
            ServarrConnectionError: When unable to connect to the API
            ServarrAuthenticationError: When API key is invalid (401/403)
        """
        url = f"{self.url}{endpoint}"
        headers = {
            'X-Api-Key': self.api_key,
            'Content-Type': 'application/json'
        }
        try:
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.ConnectionError as e:
            error_msg = f"Cannot connect to {self.url}: "
            if "Name or service not known" in str(e) or "nodename nor servname provided" in str(e):
                error_msg += "Host not found (check URL)"
            elif "Connection refused" in str(e):
                error_msg += "Connection refused (is the service running?)"
            else:
                error_msg += str(e)
            if raise_on_error:
                raise ServarrConnectionError(error_msg) from e
            if self.verbose:
                logger.error(error_msg)
            return {}
        except requests.exceptions.Timeout as e:
            error_msg = f"Cannot connect to {self.url}: Request timed out"
            if raise_on_error:
                raise ServarrConnectionError(error_msg) from e
            if self.verbose:
                logger.error(error_msg)
            return {}
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code in (401, 403):
                error_msg = f"Authentication failed for {self.url}: Invalid API key (HTTP {e.response.status_code})"
                if raise_on_error:
                    raise ServarrAuthenticationError(error_msg) from e
                logger.error(error_msg)
                return {}
            if raise_on_error:
                raise
            if self.verbose:
                logger.error(f"API request failed: {e}")
            return {}
        except requests.exceptions.RequestException as e:
            if raise_on_error:
                raise ServarrConnectionError(f"Cannot connect to {self.url}: {e}") from e
            if self.verbose:
                logger.error(f"API request failed: {e}")
            return {}

    def detect_app_type(self) -> str:
        """Detect app type from system status.

        Raises:
            ServarrConnectionError: When unable to connect to the API
            ServarrAuthenticationError: When API key is invalid
            ValueError: When connected but app type cannot be determined
        """
        if self.app_type:
            return self.app_type.lower()

        # Try v3 API first (Sonarr, Radarr) - raise on connection/auth errors
        try:
            status = self._api_request('/api/v3/system/status', raise_on_error=True)
        except ServarrConnectionError:
            # Try v1 API before giving up (Lidarr, Readarr, Prowlarr use v1)
            try:
                status = self._api_request('/api/v1/system/status', raise_on_error=True)
            except ServarrConnectionError as e:
                # Both APIs failed - re-raise with clear message
                raise ServarrConnectionError(f"Cannot connect to {self.url}: Check URL and ensure service is running") from e
        except ServarrAuthenticationError:
            # Auth error on v3, try v1 in case it's a v1 app
            try:
                status = self._api_request('/api/v1/system/status', raise_on_error=True)
            except (ServarrConnectionError, ServarrAuthenticationError) as e:
                raise ServarrAuthenticationError(f"Authentication failed for {self.url}: Check API key") from e

        app_name = status.get('appName', '').lower()
        if not app_name:
            raise ValueError(
                f"Connected to {self.url} but could not detect app type. "
                f"Please specify with 'type' in config (sonarr, radarr, lidarr, readarr, or prowlarr)."
            )

        return app_name

    def _get_api_version(self, app_type: str) -> str:
        """Get API version based on app type."""
        if app_type in ('sonarr', 'radarr'):
            return 'v3'
        return 'v1'

    def fetch_queue(self, app_type: str) -> Dict[str, Any]:
        """Fetch and transform queue data."""
        include_params = {
            'sonarr': '&includeSeries=true&includeEpisode=true',
            'radarr': '&includeMovie=true',
            'lidarr': '&includeArtist=true&includeAlbum=true',
            'readarr': '&includeAuthor=true&includeBook=true',
        }.get(app_type, '')

        data = self._api_request(
            f'/api/{self.api_version}/queue?pageSize=20&includeUnknownSeriesItems=false{include_params}'
        )

        if not data:
            return {'count': 0, 'items': []}

        count = data.get('totalRecords', len(data.get('records', [])))
        items = []

        for record in data.get('records', [])[:10]:
            item = self._format_queue_item(record, app_type)
            if item:
                items.append(item)

        return {'count': count, 'items': items}

    def _format_queue_item(self, record: Dict, app_type: str) -> Dict[str, Any]:
        """Format a queue record based on app type."""
        title = 'Unknown'

        if app_type == 'sonarr' and record.get('series'):
            series = record['series']
            episode = record.get('episode', {})
            season = str(episode.get('seasonNumber', 0)).zfill(2)
            ep_num = str(episode.get('episodeNumber', 0)).zfill(2)
            title = f"{series.get('title', 'Unknown')} [S{season}E{ep_num}]"
        elif app_type == 'radarr' and record.get('movie'):
            movie = record['movie']
            title = f"{movie.get('title', 'Unknown')} ({movie.get('year', '')})"
        elif app_type == 'lidarr' and record.get('artist'):
            artist = record['artist']
            album = record.get('album', {})
            title = f"{artist.get('artistName', 'Unknown')} - {album.get('title', 'Unknown Album')}"
        elif app_type == 'readarr' and record.get('author'):
            author = record['author']
            book = record.get('book', {})
            title = f"{author.get('authorName', 'Unknown')} - {book.get('title', 'Unknown Book')}"
        else:
            title = record.get('title', 'Unknown')

        size = record.get('size', 0)
        sizeleft = record.get('sizeleft', 0)
        progress = int((size - sizeleft) / size * 100) if size > 0 else 0

        return {
            'title': title,
            'quality': record.get('quality', {}).get('quality', {}).get('name', 'Unknown'),
            'status': record.get('status', 'unknown'),
            'progress': progress,
            'eta': record.get('timeleft', 'pending'),
        }

    def fetch_calendar(self, app_type: str) -> Dict[str, Any]:
        """Fetch and transform calendar data."""
        today = datetime.now()
        start_date = (today - timedelta(days=self.calendar_days_before)).strftime('%Y-%m-%d')
        end_date = (today + timedelta(days=self.calendar_days)).strftime('%Y-%m-%d')

        data = self._api_request(
            f'/api/{self.api_version}/calendar?start={start_date}&end={end_date}&unmonitored=false&includeSeries=true'
        )

        if not data:
            return {'count': 0, 'items': []}

        count = len(data)
        items = []

        for record in data[:10]:
            item = self._format_calendar_item(record, app_type, today)
            if item:
                items.append(item)

        return {'count': count, 'items': items}

    def _format_calendar_item(self, record: Dict, app_type: str, today: datetime) -> Dict[str, Any]:
        """Format a calendar record based on app type."""
        title = 'Unknown'
        air_date = None
        air_date_time = None
        network = None

        if app_type == 'sonarr':
            series = record.get('series', {})
            season = str(record.get('seasonNumber', 0)).zfill(2)
            ep_num = str(record.get('episodeNumber', 0)).zfill(2)
            title = f"{series.get('title', 'Unknown')} [S{season}E{ep_num}]"
            air_date_time = record.get('airDateUtc') or record.get('airDate')
            network = series.get('network')
        elif app_type == 'radarr':
            title = f"{record.get('title', 'Unknown')} ({record.get('year', '')})"
            air_date_time = record.get('digitalRelease') or record.get('physicalRelease') or record.get('inCinemas')
        elif app_type == 'lidarr':
            artist = record.get('artist', {})
            title = f"{artist.get('artistName', 'Unknown')} - {record.get('title', 'Unknown')}"
            air_date_time = record.get('releaseDate')
        elif app_type == 'readarr':
            author = record.get('author', {})
            title = f"{author.get('authorName', 'Unknown')} - {record.get('title', 'Unknown')}"
            air_date_time = record.get('releaseDate')

        # Parse air date
        if air_date_time:
            air_date = air_date_time.split('T')[0]
            try:
                item_date = datetime.strptime(air_date, '%Y-%m-%d')
                days_until = (item_date.date() - today.date()).days
            except ValueError:
                days_until = 0
        else:
            days_until = 0

        return {
            'title': title,
            'air_date': air_date,
            'air_date_time': air_date_time,
            'network': network,
            'days_until': days_until,
        }

    def fetch_health(self) -> Dict[str, Any]:
        """Fetch health status."""
        data = self._api_request(f'/api/{self.api_version}/health')

        if not isinstance(data, list):
            return {'status': 'ok'}

        if not data:
            return {'status': 'ok'}

        has_error = any(item.get('type') == 'error' for item in data)
        if has_error:
            return {'status': 'error'}

        return {'status': 'warning'}

    def fetch_stats(self, app_type: str) -> Dict[str, Any]:
        """Fetch statistics based on app type."""
        if app_type == 'sonarr':
            return self._fetch_stats_sonarr()
        elif app_type == 'radarr':
            return self._fetch_stats_radarr()
        elif app_type == 'lidarr':
            return self._fetch_stats_lidarr()
        elif app_type == 'readarr':
            return self._fetch_stats_readarr()
        elif app_type == 'prowlarr':
            return self._fetch_stats_prowlarr()
        return {}

    def _fetch_stats_sonarr(self) -> Dict[str, Any]:
        """Fetch Sonarr statistics."""
        series_data = self._api_request('/api/v3/series')
        wanted_data = self._api_request('/api/v3/wanted/missing?pageSize=1')

        if not series_data:
            return {}

        total_series = len(series_data)
        total_episodes = sum(s.get('statistics', {}).get('totalEpisodeCount', 0) for s in series_data)
        episodes_on_disk = sum(s.get('statistics', {}).get('episodeFileCount', 0) for s in series_data)
        library_size = sum(s.get('statistics', {}).get('sizeOnDisk', 0) for s in series_data)
        monitored_missing = wanted_data.get('totalRecords', 0)

        return {
            'total_series': total_series,
            'total_episodes': total_episodes,
            'episodes_on_disk': episodes_on_disk,
            'episodes_missing': total_episodes - episodes_on_disk,
            'monitored_missing': monitored_missing,
            'library_size_bytes': library_size,
            'library_size_formatted': self._format_bytes(library_size),
        }

    def _fetch_stats_radarr(self) -> Dict[str, Any]:
        """Fetch Radarr statistics."""
        movie_data = self._api_request('/api/v3/movie')
        wanted_data = self._api_request('/api/v3/wanted/missing?pageSize=1')

        if not movie_data:
            return {}

        total_movies = len(movie_data)
        movies_on_disk = sum(1 for m in movie_data if m.get('hasFile'))
        library_size = sum(m.get('sizeOnDisk', 0) for m in movie_data)
        monitored_missing = wanted_data.get('totalRecords', 0)

        return {
            'total_movies': total_movies,
            'movies_on_disk': movies_on_disk,
            'movies_missing': total_movies - movies_on_disk,
            'monitored_missing': monitored_missing,
            'library_size_bytes': library_size,
            'library_size_formatted': self._format_bytes(library_size),
        }

    def _fetch_stats_lidarr(self) -> Dict[str, Any]:
        """Fetch Lidarr statistics."""
        artist_data = self._api_request('/api/v1/artist')
        wanted_data = self._api_request('/api/v1/wanted/missing?pageSize=1')

        if not artist_data:
            return {}

        total_artists = len(artist_data)
        total_albums = sum(a.get('statistics', {}).get('albumCount', 0) for a in artist_data)
        total_tracks = sum(a.get('statistics', {}).get('trackCount', 0) for a in artist_data)
        library_size = sum(a.get('statistics', {}).get('sizeOnDisk', 0) for a in artist_data)
        monitored_missing = wanted_data.get('totalRecords', 0)

        return {
            'total_artists': total_artists,
            'total_albums': total_albums,
            'total_tracks': total_tracks,
            'monitored_missing': monitored_missing,
            'library_size_bytes': library_size,
            'library_size_formatted': self._format_bytes(library_size),
        }

    def _fetch_stats_readarr(self) -> Dict[str, Any]:
        """Fetch Readarr statistics."""
        author_data = self._api_request('/api/v1/author')
        book_data = self._api_request('/api/v1/book')
        wanted_data = self._api_request('/api/v1/wanted/missing?pageSize=1')

        total_authors = len(author_data) if author_data else 0
        total_books = len(book_data) if book_data else 0
        books_on_disk = sum(1 for b in (book_data or []) if b.get('statistics', {}).get('bookFileCount', 0) > 0)
        library_size = sum(a.get('statistics', {}).get('sizeOnDisk', 0) for a in (author_data or []))
        monitored_missing = wanted_data.get('totalRecords', 0) if wanted_data else 0

        return {
            'total_authors': total_authors,
            'total_books': total_books,
            'books_on_disk': books_on_disk,
            'monitored_missing': monitored_missing,
            'library_size_bytes': library_size,
            'library_size_formatted': self._format_bytes(library_size),
        }

    def _fetch_stats_prowlarr(self) -> Dict[str, Any]:
        """Fetch Prowlarr statistics."""
        indexer_data = self._api_request('/api/v1/indexer')
        stats_data = self._api_request('/api/v1/indexerstats')

        total_indexers = len(indexer_data) if indexer_data else 0
        enabled_indexers = sum(1 for i in (indexer_data or []) if i.get('enable'))

        total_grabs = 0
        total_queries = 0
        failed_grabs = 0
        failed_queries = 0

        if stats_data and stats_data.get('indexers'):
            for idx in stats_data['indexers']:
                total_grabs += idx.get('numberOfGrabs', 0)
                total_queries += idx.get('numberOfQueries', 0)
                failed_grabs += idx.get('numberOfFailedGrabs', 0)
                failed_queries += idx.get('numberOfFailedQueries', 0)

        return {
            'total_indexers': total_indexers,
            'enabled_indexers': enabled_indexers,
            'total_grabs': total_grabs,
            'total_queries': total_queries,
            'failed_grabs': failed_grabs,
            'failed_queries': failed_queries,
        }

    def fetch_recently_added(self, app_type: str) -> Dict[str, Any]:
        """Fetch recently added items from history."""
        if app_type == 'prowlarr':
            return {'count': 0, 'items': []}

        include_params = {
            'sonarr': '&includeSeries=true&includeEpisode=true',
            'radarr': '&includeMovie=true',
            'lidarr': '&includeArtist=true&includeAlbum=true',
            'readarr': '&includeAuthor=true&includeBook=true',
        }.get(app_type, '')

        data = self._api_request(
            f'/api/{self.api_version}/history?pageSize=50&sortKey=date&sortDirection=descending{include_params}'
        )

        if not data or not data.get('records'):
            return {'count': 0, 'items': []}

        # Filter for downloadFolderImported events
        imported = [r for r in data['records'] if r.get('eventType') == 'downloadFolderImported'][:10]

        items = []
        now = datetime.now()

        for record in imported[:6]:
            item = self._format_recently_added_item(record, app_type, now)
            if item:
                items.append(item)

        return {'count': len(imported), 'items': items}

    def _format_recently_added_item(self, record: Dict, app_type: str, now: datetime) -> Dict[str, Any]:
        """Format a recently added record."""
        title = 'Unknown'

        if app_type == 'sonarr' and record.get('series'):
            series = record['series']
            episode = record.get('episode', {})
            season = str(episode.get('seasonNumber', 0)).zfill(2)
            ep_num = str(episode.get('episodeNumber', 0)).zfill(2)
            title = f"{series.get('title', 'Unknown')} [S{season}E{ep_num}]"
        elif app_type == 'radarr' and record.get('movie'):
            movie = record['movie']
            title = f"{movie.get('title', 'Unknown')} ({movie.get('year', '')})"
        elif app_type == 'lidarr' and record.get('artist'):
            artist = record['artist']
            album = record.get('album', {})
            title = f"{artist.get('artistName', 'Unknown')} - {album.get('title', 'Unknown Album')}"
        elif app_type == 'readarr' and record.get('author'):
            author = record['author']
            book = record.get('book', {})
            title = f"{author.get('authorName', 'Unknown')} - {book.get('title', 'Unknown Book')}"
        else:
            title = record.get('sourceTitle', 'Unknown')

        # Calculate relative time
        time_ago = self._calc_relative_time(record.get('date'), now)

        return {
            'title': title,
            'time_ago': time_ago,
        }

    def _calc_relative_time(self, date_str: Optional[str], now: datetime) -> str:
        """Calculate relative time string."""
        if not date_str:
            return ''

        try:
            # Parse ISO format
            event_time = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            event_time = event_time.replace(tzinfo=None)  # Remove timezone for comparison
            diff = now - event_time
            seconds = int(diff.total_seconds())

            if seconds < 60:
                return 'Just now'
            elif seconds < 3600:
                mins = seconds // 60
                return f'{mins} min ago'
            elif seconds < 86400:
                hours = seconds // 3600
                return f'{hours} hour{"s" if hours != 1 else ""} ago'
            else:
                days = seconds // 86400
                return f'{days} day{"s" if days != 1 else ""} ago'
        except (ValueError, TypeError):
            return ''

    @staticmethod
    def _format_bytes(size: int) -> str:
        """Format bytes to human readable string."""
        if not size:
            return '--'

        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if abs(size) < 1024:
                return f'{size:.1f} {unit}'
            size /= 1024
        return f'{size:.1f} PB'

    def _get_timezone_abbrev(self) -> str:
        """Get timezone abbreviation from configured timezone."""
        if not self.timezone:
            return 'UTC'

        try:
            tz = ZoneInfo(self.timezone)
            now = datetime.now(tz)
            # Get the abbreviation (e.g., EST, PST, UTC)
            abbrev = now.strftime('%Z')
            return abbrev if abbrev else self.timezone
        except Exception:
            # If timezone is invalid, return it as-is or UTC
            return self.timezone if self.timezone else 'UTC'

    def collect(self) -> Dict[str, Any]:
        """Collect all data from this instance."""
        logger.info(f"[{self.name}] Collecting data from {self.url}")

        # Detect app type
        app_type = self.detect_app_type()
        self.api_version = self._get_api_version(app_type)
        logger.info(f"[{self.name}] Detected app type: {app_type}, API version: {self.api_version}")

        # Get timezone abbreviation for display
        tz_abbrev = self._get_timezone_abbrev()

        # Build payload
        if self.calendar_only:
            # Calendar only mode - minimal payload
            calendar = self.fetch_calendar(app_type)
            payload = {
                'merge_variables': {
                    'app_name': app_type.capitalize(),
                    'app_type': app_type,
                    'last_updated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'timezone': tz_abbrev,
                    'calendar': calendar,
                }
            }
        else:
            # Full payload
            queue = self.fetch_queue(app_type)
            calendar = self.fetch_calendar(app_type)
            health = self.fetch_health()
            stats = self.fetch_stats(app_type)
            recently_added = self.fetch_recently_added(app_type)

            payload = {
                'merge_variables': {
                    'app_name': app_type.capitalize(),
                    'app_type': app_type,
                    'last_updated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'timezone': tz_abbrev,
                    'health': health,
                    'queue': queue,
                    'calendar': calendar,
                    'stats': stats,
                    'recently_added': recently_added,
                }
            }

        return payload

    def send(self, payload: Dict[str, Any]) -> bool:
        """Send payload to webhook."""
        payload_json = json.dumps(payload)
        payload_size = len(payload_json)

        if self.verbose:
            logger.info(f"[{self.name}] Payload size: {payload_size} bytes")

        # Dry run or no webhook - print to stdout
        if self.dry_run or not self.webhook:
            print(json.dumps(payload, indent=2))
            return True

        # Send to webhook
        logger.info(f"[{self.name}] Sending data to TRMNL webhook...")
        try:
            response = requests.post(
                self.webhook,
                headers={'Content-Type': 'application/json'},
                data=payload_json,
                timeout=30
            )
            response.raise_for_status()
            logger.info(f"[{self.name}] Successfully sent data (HTTP {response.status_code})")
            return True
        except requests.exceptions.RequestException as e:
            logger.error(f"[{self.name}] Failed to send data: {e}")
            if self.verbose and hasattr(e, 'response') and e.response is not None:
                logger.error(f"[{self.name}] Response: {e.response.text}")
            return False


def load_config(config_path: str) -> Dict[str, Any]:
    """Load configuration from YAML file."""
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def create_collectors_from_config(config: Dict[str, Any], args: argparse.Namespace) -> List[ServarrCollector]:
    """Create collector instances from config file."""
    collectors = []
    defaults = config.get('defaults', {})
    global_timezone = config.get('timezone', args.timezone)

    for instance in config.get('instances', []):
        collector = ServarrCollector(
            name=instance.get('name', instance.get('url', 'unknown')),
            url=instance['url'],
            api_key=instance['api_key'],
            webhook=instance.get('webhook'),
            app_type=instance.get('type'),
            calendar_days=instance.get('calendar_days', defaults.get('calendar_days', 7)),
            calendar_days_before=instance.get('calendar_days_before', defaults.get('calendar_days_before', 0)),
            calendar_only=instance.get('calendar_only', False),
            timezone=global_timezone,
            verbose=args.verbose,
            dry_run=args.dry_run,
        )
        collectors.append(collector)

    return collectors


def create_collector_from_args(args: argparse.Namespace) -> ServarrCollector:
    """Create a single collector from CLI arguments."""
    return ServarrCollector(
        name=args.type or 'servarr',
        url=args.url,
        api_key=args.api_key,
        webhook=args.webhook,
        app_type=args.type,
        calendar_days=args.days,
        calendar_days_before=args.days_before,
        calendar_only=args.calendar_only,
        timezone=args.timezone,
        verbose=args.verbose,
        dry_run=args.dry_run,
    )


def run_collection(collectors: List[ServarrCollector]) -> bool:
    """Run collection for all instances."""
    logger.info(f"Starting collection cycle at {datetime.now()}")
    succeeded = []
    failed = []

    for collector in collectors:
        try:
            payload = collector.collect()
            if collector.send(payload):
                succeeded.append(collector.name)
            else:
                failed.append((collector.name, "Failed to send webhook"))
        except ServarrConnectionError as e:
            logger.error(f"[{collector.name}] {e}")
            failed.append((collector.name, str(e)))
        except ServarrAuthenticationError as e:
            logger.error(f"[{collector.name}] {e}")
            failed.append((collector.name, str(e)))
        except Exception as e:
            logger.error(f"[{collector.name}] Collection failed: {e}")
            failed.append((collector.name, str(e)))

    # Log summary
    total = len(collectors)
    if failed:
        logger.warning(f"Collection complete: {len(succeeded)}/{total} succeeded, {len(failed)} failed")
        for name, reason in failed:
            logger.warning(f"  - {name}: {reason}")
    else:
        logger.info(f"Collection complete: {len(succeeded)}/{total} succeeded")

    return len(failed) == 0


def main():
    parser = argparse.ArgumentParser(
        description='TRMNL Servarr Collector - Collect data from Servarr apps and send to TRMNL webhook',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # With config file (multiple instances)
  %(prog)s --config config.yaml

  # CLI only (single instance)
  %(prog)s -u http://sonarr:8989 -k api_key -w https://webhook_url

  # Dry run (print JSON, don't send)
  %(prog)s --config config.yaml --dry-run
'''
    )

    # Config file
    parser.add_argument('--config', '-C', help='Path to YAML config file')

    # Single instance options
    parser.add_argument('-u', '--url', help='Servarr instance URL')
    parser.add_argument('-k', '--api-key', help='Servarr API key')
    parser.add_argument('-w', '--webhook', help='TRMNL webhook URL')
    parser.add_argument('-t', '--type', help='App type (sonarr, radarr, lidarr, readarr, prowlarr)')
    parser.add_argument('-d', '--days', type=int, default=7, help='Calendar days forward (default: 7)')
    parser.add_argument('-b', '--days-before', type=int, default=0, help='Calendar days back (default: 0)')
    parser.add_argument('-c', '--calendar-only', action='store_true', help='Only send calendar data')
    parser.add_argument('-z', '--timezone', default='', help='Timezone for date calculations')
    parser.add_argument('-i', '--interval', type=int, default=0, help='Collection interval in seconds (0 = run once)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    parser.add_argument('--dry-run', action='store_true', help='Print JSON, don\'t send to webhook')
    parser.add_argument('--version', action='version', version=f'%(prog)s {VERSION}')

    args = parser.parse_args()

    # Validate arguments
    if args.config:
        # Config file mode
        try:
            config = load_config(args.config)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            sys.exit(1)

        # Get interval from config or CLI
        interval = config.get('interval', args.interval)
        collectors = create_collectors_from_config(config, args)

        if not collectors:
            logger.error("No instances defined in config file")
            sys.exit(1)
    else:
        # CLI mode - require URL and API key
        if not args.url or not args.api_key:
            logger.error("Either --config or both --url and --api-key are required")
            parser.print_help()
            sys.exit(1)

        interval = args.interval
        collectors = [create_collector_from_args(args)]

    logger.info(f"TRMNL Servarr Collector v{VERSION}")
    logger.info(f"Loaded {len(collectors)} instance(s)")

    # Setup signal handlers
    def signal_handler(signum, frame):
        logger.info("Shutting down...")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run collection
    if interval > 0:
        logger.info(f"Running continuously with {interval}s interval (Ctrl+C to stop)")
        while True:
            run_collection(collectors)
            logger.info(f"Sleeping for {interval} seconds...")
            time.sleep(interval)
    else:
        # Single run
        success = run_collection(collectors)
        logger.info("Done!")
        sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
