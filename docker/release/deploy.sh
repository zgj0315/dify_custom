#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RELEASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$RELEASE_DIR/compose"
ENV_FILE="${ENV_FILE:-$COMPOSE_DIR/.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dify}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy $COMPOSE_DIR/.env.production.example to $COMPOSE_DIR/.env and fill in production values first."
  exit 1
fi

if [ "${SKIP_IMAGE_LOAD:-false}" != "true" ] && [ -f "$RELEASE_DIR/images.tar.gz" ]; then
  "$SCRIPT_DIR/load-images.sh" "$RELEASE_DIR/images.tar.gz"
fi

(
  cd "$COMPOSE_DIR"
  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    -f docker-compose.yaml \
    -f docker-compose.production.override.yaml \
    config -q

  docker compose \
    -p "$PROJECT_NAME" \
    --env-file "$ENV_FILE" \
    -f docker-compose.yaml \
    -f docker-compose.production.override.yaml \
    up -d "$@"
)
