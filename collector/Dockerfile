# TRMNL Servarr Collector
# Collects data from Servarr apps and sends to TRMNL webhook
#
# Build:
#   docker build -t trmnl-servarr-collector ./collector
#
# Run with config file (recommended for multiple instances):
#   docker run -d \
#     -v ./config.yaml:/app/config.yaml:ro \
#     trmnl-servarr-collector
#
# Run with environment variables (single instance):
#   docker run -d \
#     -e SERVARR_URL=http://sonarr:8989 \
#     -e API_KEY=your-api-key \
#     -e WEBHOOK_URL=https://usetrmnl.com/api/custom_plugins/xxx \
#     -e INTERVAL=900 \
#     trmnl-servarr-collector

FROM python:3.12-slim

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy collector script
COPY trmnl_collector.py /app/

# Copy example config for reference
COPY config.example.yaml /app/

# Environment variables for single-instance mode (optional)
ENV SERVARR_URL=""
ENV API_KEY=""
ENV WEBHOOK_URL=""
ENV APP_NAME=""
ENV APP_TYPE=""
ENV CALENDAR_DAYS="7"
ENV CALENDAR_DAYS_BEFORE="0"
ENV CALENDAR_ONLY=""
ENV INTERVAL="0"
ENV TZ="UTC"

# Entry point script
COPY --chmod=755 <<'EOF' /app/entrypoint.sh
#!/bin/bash
set -e

# Check if config file exists
if [[ -f "/app/config.yaml" ]]; then
    echo "Starting with config file..."
    exec python /app/trmnl_collector.py --config /app/config.yaml
fi

# Fall back to environment variables (single instance mode)
if [[ -z "$SERVARR_URL" || -z "$API_KEY" ]]; then
    echo "ERROR: Either mount a config.yaml file or provide SERVARR_URL and API_KEY environment variables"
    exit 1
fi

# Build command arguments from environment variables
ARGS="-u $SERVARR_URL -k $API_KEY"

if [[ -n "$WEBHOOK_URL" ]]; then
    ARGS="$ARGS -w $WEBHOOK_URL"
fi

if [[ -n "$APP_NAME" ]]; then
    ARGS="$ARGS -n $APP_NAME"
fi

if [[ -n "$APP_TYPE" ]]; then
    ARGS="$ARGS -t $APP_TYPE"
fi

if [[ -n "$CALENDAR_DAYS" ]]; then
    ARGS="$ARGS -d $CALENDAR_DAYS"
fi

if [[ -n "$CALENDAR_DAYS_BEFORE" && "$CALENDAR_DAYS_BEFORE" != "0" ]]; then
    ARGS="$ARGS -b $CALENDAR_DAYS_BEFORE"
fi

if [[ -n "$CALENDAR_ONLY" && "$CALENDAR_ONLY" == "true" ]]; then
    ARGS="$ARGS -c"
fi

if [[ -n "$INTERVAL" && "$INTERVAL" != "0" ]]; then
    ARGS="$ARGS -i $INTERVAL"
fi

if [[ -n "$TZ" ]]; then
    ARGS="$ARGS -z $TZ"
fi

# Run the Python collector
exec python /app/trmnl_collector.py $ARGS
EOF

ENTRYPOINT ["/app/entrypoint.sh"]
