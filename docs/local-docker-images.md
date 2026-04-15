# Local Docker Images Workflow

This document explains how to package tested local changes from `api/` and `web/` into Docker images and run them with Docker Compose without modifying `docker/docker-compose.yaml`.

## Prerequisites

- Docker and Docker Compose are installed.
- `docker/.env` exists and contains the deployment settings you want to use.
- Your code changes have already been validated locally.

## 1. Prepare the local image env file

Copy the example image variables file:

```bash
cp docker/.env.local-images.example docker/.env.local-images
```

Default values:

- `DOCKER_REGISTRY=local`
- `IMAGE_TAG=dev`
- `API_IMAGE_NAME=dify-api`
- `WEB_IMAGE_NAME=dify-web`

If you need multiple local builds at the same time, edit `IMAGE_TAG` before building.

## 2. Build the API image

```bash
docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-api:dev \
  ./api
```

This image is reused by `api`, `worker`, and `worker_beat`.

## 3. Build the web image

```bash
docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-web:dev \
  ./web
```

## 4. Start the stack with the override file

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  up -d
```

## 5. Verify the running images

Check service status:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  ps
```

Check selected images:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  images
```

Check the build commit inside the API container:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  exec api env | rg '^COMMIT_SHA='
```

Then run one UI flow that requires the worker, not just a page load.

## 6. Stop the stack

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  down
```

## Troubleshooting

- If Compose still shows `langgenius/dify-api` or `langgenius/dify-web`, confirm that `docker/docker-compose.local-images.yaml` is included in the command.
- If the tag does not match, confirm that `docker/.env.local-images` matches the tag used during `docker build`.
- If `worker` fails while `api` starts, verify that all three API-style services use the same local API tag.
