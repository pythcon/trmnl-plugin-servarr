# TRMNL Servarr Collector
# Lightweight container for collecting Servarr data and sending to TRMNL webhook
#
# Build:
#   docker build -t trmnl-servarr-collector ./collector
#
# Run (one-time):
#   docker run --rm \
#     -e SERVARR_URL=http://sonarr:8989 \
#     -e API_KEY=your-api-key \
#     -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
#     trmnl-servarr-collector
#
# Run (continuous with 15-minute interval):
#   docker run -d \
#     -e SERVARR_URL=http://sonarr:8989 \
#     -e API_KEY=your-api-key \
#     -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
#     -e INTERVAL=900 \
#     trmnl-servarr-collector

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    bc \
    tzdata

# Create app directory
WORKDIR /app

# Copy collector script
COPY trmnl-servarr-collector.sh /app/
RUN chmod +x /app/trmnl-servarr-collector.sh

# Environment variables (required)
ENV SERVARR_URL=""
ENV API_KEY=""
ENV WEBHOOK_URL=""

# Optional environment variables
ENV APP_TYPE=""
ENV CALENDAR_DAYS="7"
ENV INTERVAL="0"
ENV TZ="UTC"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f "${SERVARR_URL}/api/v3/system/status" -H "X-Api-Key: ${API_KEY}" || exit 1

# Entry point script
COPY --chmod=755 <<'EOF' /app/entrypoint.sh
#!/bin/bash
set -e

# Validate required environment variables
if [[ -z "$SERVARR_URL" ]]; then
    echo "ERROR: SERVARR_URL environment variable is required"
    exit 1
fi

if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API_KEY environment variable is required"
    exit 1
fi

if [[ -z "$WEBHOOK_URL" ]]; then
    echo "ERROR: WEBHOOK_URL environment variable is required"
    exit 1
fi

# Build command arguments
ARGS="-u $SERVARR_URL -k $API_KEY -w $WEBHOOK_URL"

if [[ -n "$APP_TYPE" ]]; then
    ARGS="$ARGS -t $APP_TYPE"
fi

if [[ -n "$CALENDAR_DAYS" ]]; then
    ARGS="$ARGS -d $CALENDAR_DAYS"
fi

if [[ -n "$INTERVAL" && "$INTERVAL" != "0" ]]; then
    ARGS="$ARGS -i $INTERVAL"
fi

# Run the collector
exec /app/trmnl-servarr-collector.sh $ARGS
EOF

ENTRYPOINT ["/app/entrypoint.sh"]
