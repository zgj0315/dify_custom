#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

ENV_FILE=""
IMAGE_ENV_FILE=""
OUTPUT_DIR=""
PROJECT_NAME="dify-offline"
PACKAGE_PREFIX="dify-offline"
IMAGE_TAG_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage:
  build-offline-package.sh --env-file <path> --image-env-file <path> --output <dir> [--tag <tag>] [--project-name <name>]
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
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --image-env-file)
      IMAGE_ENV_FILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --tag)
      IMAGE_TAG_OVERRIDE="$2"
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

if [[ -z "${ENV_FILE}" || -z "${IMAGE_ENV_FILE}" || -z "${OUTPUT_DIR}" ]]; then
  usage >&2
  exit 1
fi

require_command docker
require_command git
require_command tar

require_file "${ENV_FILE}"
require_file "${IMAGE_ENV_FILE}"
require_file "${REPO_ROOT}/docker/docker-compose.yaml"
require_file "${REPO_ROOT}/docker/docker-compose.local-images.yaml"
require_file "${REPO_ROOT}/docker/.env.example"
require_file "${REPO_ROOT}/docker/.env.local-images.example"
require_file "${REPO_ROOT}/docker/offline/install-offline.sh"
require_file "${REPO_ROOT}/docker/offline/verify-offline.sh"
require_file "${REPO_ROOT}/docs/offline-docker-package.md"
require_file "${REPO_ROOT}/docker/volumes/sandbox/conf/config.yaml"
require_file "${REPO_ROOT}/docker/volumes/sandbox/conf/config.yaml.example"

set -a
source "${IMAGE_ENV_FILE}"
set +a

DOCKER_REGISTRY_VALUE="${DOCKER_REGISTRY:-local}"
API_IMAGE_NAME_VALUE="${API_IMAGE_NAME:-dify-api}"
WEB_IMAGE_NAME_VALUE="${WEB_IMAGE_NAME:-dify-web}"
IMAGE_TAG_VALUE="${IMAGE_TAG_OVERRIDE:-${IMAGE_TAG:-dev}}"
COMMIT_SHA=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
ARCH=$(uname -m)
PACKAGE_NAME="${PACKAGE_PREFIX}-${COMMIT_SHA}-${IMAGE_TAG_VALUE}"
PACKAGE_ROOT="${OUTPUT_DIR}/${PACKAGE_NAME}"
ARCHIVE_PATH="${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz"
IMAGES_DIR="${PACKAGE_ROOT}/images"
MANIFEST_DIR="${PACKAGE_ROOT}/manifest"
PACKAGE_DOCKER_DIR="${PACKAGE_ROOT}/docker"
PACKAGE_SCRIPTS_DIR="${PACKAGE_ROOT}/scripts"
PACKAGE_SANDBOX_CONF_DIR="${PACKAGE_DOCKER_DIR}/volumes/sandbox/conf"
PACKAGE_SANDBOX_DEPENDENCIES_DIR="${PACKAGE_DOCKER_DIR}/volumes/sandbox/dependencies"

API_IMAGE="${DOCKER_REGISTRY_VALUE}/${API_IMAGE_NAME_VALUE}:${IMAGE_TAG_VALUE}"
WEB_IMAGE="${DOCKER_REGISTRY_VALUE}/${WEB_IMAGE_NAME_VALUE}:${IMAGE_TAG_VALUE}"

mkdir -p "${IMAGES_DIR}" "${MANIFEST_DIR}" "${PACKAGE_DOCKER_DIR}" "${PACKAGE_SCRIPTS_DIR}"
mkdir -p "${PACKAGE_SANDBOX_CONF_DIR}" "${PACKAGE_SANDBOX_DEPENDENCIES_DIR}"

docker build \
  --build-arg "COMMIT_SHA=${COMMIT_SHA}" \
  -t "${API_IMAGE}" \
  "${REPO_ROOT}/api"

docker build \
  --build-arg "COMMIT_SHA=${COMMIT_SHA}" \
  -t "${WEB_IMAGE}" \
  "${REPO_ROOT}/web"

IMAGE_LIST_RAW=$(docker compose \
  --env-file "${ENV_FILE}" \
  --env-file "${IMAGE_ENV_FILE}" \
  -f "${REPO_ROOT}/docker/docker-compose.yaml" \
  -f "${REPO_ROOT}/docker/docker-compose.local-images.yaml" \
  config --images)

IMAGE_LIST=$(printf '%s\n' "${IMAGE_LIST_RAW}" | awk 'NF && !seen[$0]++')

if [[ -z "${IMAGE_LIST}" ]]; then
  echo "Unable to resolve image list from docker compose config --images" >&2
  exit 1
fi

printf '%s\n' "${IMAGE_LIST}" > "${MANIFEST_DIR}/images.txt"

IMAGE_ARRAY=()
while IFS= read -r image; do
  IMAGE_ARRAY+=("${image}")
done < "${MANIFEST_DIR}/images.txt"

docker save -o "${IMAGES_DIR}/images.tar" "${IMAGE_ARRAY[@]}"

cp "${REPO_ROOT}/docker/docker-compose.yaml" "${PACKAGE_DOCKER_DIR}/docker-compose.yaml"
cp "${REPO_ROOT}/docker/docker-compose.local-images.yaml" "${PACKAGE_DOCKER_DIR}/docker-compose.local-images.yaml"
cp "${REPO_ROOT}/docker/.env.example" "${PACKAGE_DOCKER_DIR}/.env.example"
cp -R "${REPO_ROOT}/docker/nginx" "${PACKAGE_DOCKER_DIR}/nginx"
cp -R "${REPO_ROOT}/docker/ssrf_proxy" "${PACKAGE_DOCKER_DIR}/ssrf_proxy"
cp -R "${REPO_ROOT}/docker/certbot" "${PACKAGE_DOCKER_DIR}/certbot"
cp "${REPO_ROOT}/docker/volumes/sandbox/conf/config.yaml" "${PACKAGE_SANDBOX_CONF_DIR}/config.yaml"
cp "${REPO_ROOT}/docker/volumes/sandbox/conf/config.yaml.example" "${PACKAGE_SANDBOX_CONF_DIR}/config.yaml.example"

cat > "${PACKAGE_DOCKER_DIR}/.env.local-images.example" <<EOF
DOCKER_REGISTRY=${DOCKER_REGISTRY_VALUE}
IMAGE_TAG=${IMAGE_TAG_VALUE}
API_IMAGE_NAME=${API_IMAGE_NAME_VALUE}
WEB_IMAGE_NAME=${WEB_IMAGE_NAME_VALUE}
EOF

cp "${REPO_ROOT}/docker/offline/install-offline.sh" "${PACKAGE_SCRIPTS_DIR}/install-offline.sh"
cp "${REPO_ROOT}/docker/offline/verify-offline.sh" "${PACKAGE_SCRIPTS_DIR}/verify-offline.sh"
chmod +x "${PACKAGE_SCRIPTS_DIR}/install-offline.sh" "${PACKAGE_SCRIPTS_DIR}/verify-offline.sh"

cat > "${MANIFEST_DIR}/package-info.txt" <<EOF
commit_sha=${COMMIT_SHA}
image_tag=${IMAGE_TAG_VALUE}
architecture=${ARCH}
project_name=${PROJECT_NAME}
env_file=.env
image_env_file=.env.local-images
compose_profiles=weaviate,postgresql
package_name=${PACKAGE_NAME}
EOF

cp "${REPO_ROOT}/docs/offline-docker-package.md" "${PACKAGE_ROOT}/README.md"

rm -f "${ARCHIVE_PATH}"
tar -czf "${ARCHIVE_PATH}" -C "${OUTPUT_DIR}" "${PACKAGE_NAME}"

echo "Created offline package archive: ${ARCHIVE_PATH}"
