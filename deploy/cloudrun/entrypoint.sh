#!/bin/sh
set -eu

# Cloud Run mounts configuration as read-only secret volumes. LibreChat reads
# /app/.env and /app/librechat.yaml, so copy the mounted files into place.
if [ -f /secrets/env/.env ]; then
  cp /secrets/env/.env /app/.env
fi

if [ -f /secrets/yaml/librechat.yaml ]; then
  cp /secrets/yaml/librechat.yaml /app/librechat.yaml
fi

# Meilisearch runs as a Cloud Run sidecar on localhost. Wait for it before
# starting the API so the startup index sync does not race the search engine.
# The Meilisearch sidecar uses ephemeral storage. Queue a full re-index on every
# container start so search still works after a cold start or revision rollout.
if [ "${FORCE_MEILI_RESYNC:-false}" = "true" ]; then
  echo "Queueing a full Meilisearch re-index..."
  node /app/reset-meili.js
fi

if [ "${WAIT_FOR_MEILI:-false}" = "true" ]; then
  echo "Waiting for Meilisearch on 127.0.0.1:7700..."
  attempts=0
  until curl -fsS "http://127.0.0.1:7700/health" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 90 ]; then
      echo "Meilisearch did not become healthy within 90 seconds" >&2
      exit 1
    fi
    sleep 1
  done
  echo "Meilisearch is healthy."
fi

cd /app
exec node api/server/index.js
