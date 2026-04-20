#!/usr/bin/env bash

set -euo pipefail

PACKAGE_ROOT=""
PROJECT_NAME="dify-offline"

usage() {
  cat <<'EOF'
Usage:
  verify-offline.sh --package-root <dir> [--project-name <name>]
EOF
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Required file does not exist: ${path}" >&2
    exit 1
  fi
}

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Required command is not available: ${name}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-root)
      PACKAGE_ROOT="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${PACKAGE_ROOT}" ]]; then
  usage >&2
  exit 1
fi

require_command docker

PACKAGE_ROOT=$(cd "${PACKAGE_ROOT}" && pwd)
DOCKER_DIR="${PACKAGE_ROOT}/docker"
ENV_FILE="${DOCKER_DIR}/.env"
IMAGE_ENV_FILE="${DOCKER_DIR}/.env.local-images"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yaml"
COMPOSE_OVERRIDE_FILE="${DOCKER_DIR}/docker-compose.local-images.yaml"

require_file "${ENV_FILE}"
require_file "${IMAGE_ENV_FILE}"
require_file "${COMPOSE_FILE}"
require_file "${COMPOSE_OVERRIDE_FILE}"

compose() {
  docker compose \
    -p "${PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --env-file "${IMAGE_ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    -f "${COMPOSE_OVERRIDE_FILE}" \
    "$@"
}

compose ps
compose images

COMMIT_SHA_LINE=$(compose exec api env | grep '^COMMIT_SHA=' || true)
if [[ -z "${COMMIT_SHA_LINE}" ]]; then
  echo "Unable to verify COMMIT_SHA inside api container" >&2
  exit 1
fi

echo "${COMMIT_SHA_LINE}"
