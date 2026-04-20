#!/usr/bin/env bash

set -euo pipefail

PACKAGE_ROOT=""
PROJECT_NAME="dify-offline"

usage() {
  cat <<'EOF'
Usage:
  install-offline.sh --package-root <dir> [--project-name <name>]
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
IMAGES_TAR="${PACKAGE_ROOT}/images/images.tar"
ENV_FILE="${DOCKER_DIR}/.env"
IMAGE_ENV_FILE="${DOCKER_DIR}/.env.local-images"
IMAGE_ENV_EXAMPLE="${DOCKER_DIR}/.env.local-images.example"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yaml"
COMPOSE_OVERRIDE_FILE="${DOCKER_DIR}/docker-compose.local-images.yaml"

require_file "${IMAGES_TAR}"
require_file "${ENV_FILE}"
require_file "${IMAGE_ENV_EXAMPLE}"
require_file "${COMPOSE_FILE}"
require_file "${COMPOSE_OVERRIDE_FILE}"

if [[ ! -f "${IMAGE_ENV_FILE}" ]]; then
  cp "${IMAGE_ENV_EXAMPLE}" "${IMAGE_ENV_FILE}"
fi

docker load -i "${IMAGES_TAR}"

docker compose \
  -p "${PROJECT_NAME}" \
  --env-file "${ENV_FILE}" \
  --env-file "${IMAGE_ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  -f "${COMPOSE_OVERRIDE_FILE}" \
  up -d

echo "Offline package installed with project: ${PROJECT_NAME}"
