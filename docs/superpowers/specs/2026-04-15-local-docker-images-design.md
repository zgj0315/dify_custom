# Local Docker Images Packaging Design

**Date:** 2026-04-15

**Status:** Proposed

## Goal

Provide a local packaging workflow that turns tested source changes in `api/` and `web/` into Docker images and runs them through Docker Compose without modifying the official `docker/docker-compose.yaml`.

## Context

The repository already supports two separate flows:

- Source-based local development from `api/README.md`, where API, web, worker, and middleware can run directly from the checked-out code.
- Compose-based container deployment from `docker/README.md`, where `docker/docker-compose.yaml` references published images such as `langgenius/dify-api:1.13.3` and `langgenius/dify-web:1.13.3`.

The gap is a repeatable way to package locally tested source changes into images and deploy them with the existing compose stack, while keeping the upstream compose file untouched for easier rebases and upgrades.

## Requirements

### Functional requirements

1. Package local `api/` code into a custom API image.
2. Reuse the same custom API image for `api`, `worker`, and `worker_beat`.
3. Package local `web/` code into a custom web image.
4. Start the stack with Docker Compose by layering an override file on top of `docker/docker-compose.yaml`.
5. Keep the official compose file unchanged.
6. Support explicit image tags so developers can verify which local build is running.

### Non-functional requirements

1. The workflow must be easy to run manually from a developer machine.
2. The solution must minimize divergence from upstream Dify deployment files.
3. The build and run phases must stay decoupled so failures are easier to debug.
4. The solution should be extensible to later CI-based image publishing, but CI is not required now.

## Options Considered

### Option A: Explicit `docker build` plus compose override

Build the images first, then run compose with an additional override file that swaps the image references for `api`, `worker`, `worker_beat`, and `web`.

Pros:

- Clean separation between build and runtime.
- Easy to inspect, retag, or reuse built images.
- Minimal change surface against upstream deployment files.
- Clear path to later registry publishing.

Cons:

- Requires one extra manual step before `docker compose up`.

### Option B: Compose override with `build:`

Put `build:` directives in the override file and rely on `docker compose up --build`.

Pros:

- Shorter command sequence.
- No separate build command needed.

Cons:

- Weak image lifecycle control.
- Harder to reason about which exact image tag is running.
- More awkward if later extended to push images or pin versions.

### Option C: Fork the official compose file

Copy `docker/docker-compose.yaml` and edit it directly for local custom images.

Pros:

- Straightforward to understand initially.

Cons:

- High upgrade cost.
- Easy to drift from upstream.
- Violates the explicit constraint to avoid changing the official compose file.

## Recommended Approach

Adopt **Option A: explicit local image builds plus a compose override**.

This matches the current repository layout:

- `api/Dockerfile` already produces the runtime image used by API-style services.
- `api/docker/entrypoint.sh` already switches behavior using `MODE`, so one image can serve `api`, `worker`, and `worker_beat`.
- `web/Dockerfile` already produces the production web image.
- `docker/docker-compose.yaml` can remain the immutable base deployment definition.

## Proposed File Changes

### New files

1. `docker/docker-compose.local-images.yaml`
   Purpose: override only the image references for local custom builds.

2. `docker/.env.local-images.example`
   Purpose: provide versioned defaults for local image naming without committing machine-specific values.

3. `docs/local-docker-images.md`
   Purpose: document the build, startup, verification, and cleanup workflow for developers.

### Optional convenience changes

4. `Makefile`
   Purpose: add optional convenience targets such as `build-local-images` and `up-local-images`.

The initial implementation should not add new `dev/` scripts. The manual workflow is the primary path, and `Makefile` wrappers are the only optional convenience layer if the team wants a shorter command surface later.

## Detailed Design

### 1. Image naming strategy

Use explicit local image names instead of reusing `langgenius/*` tags:

- `local/dify-api:${IMAGE_TAG}`
- `local/dify-web:${IMAGE_TAG}`

Recommended `IMAGE_TAG` values:

- `dev`
- current git short SHA
- `dev-YYYYMMDD-HHMM`

The default local workflow should use `dev`, with manual override allowed when a developer needs multiple concurrent tags.

The API image will be built once and referenced by:

- `api`
- `worker`
- `worker_beat`

This avoids redundant builds and preserves behavioral parity across those services.

### 2. Local image environment file

Add a checked-in example file:

```dotenv
DOCKER_REGISTRY=local
IMAGE_TAG=dev
API_IMAGE_NAME=dify-api
WEB_IMAGE_NAME=dify-web
```

Developers copy it to `docker/.env.local-images` when needed. The runtime command will load:

- `docker/.env` for deployment settings
- `docker/.env.local-images` for image naming settings

This keeps deployment configuration separate from image selection.

The initial implementation should only version `docker/.env.local-images.example`. It should not auto-generate `docker/.env.local-images`.

### 3. Compose override file

Add `docker/docker-compose.local-images.yaml` with only image overrides:

```yaml
services:
  api:
    image: ${DOCKER_REGISTRY:-local}/${API_IMAGE_NAME:-dify-api}:${IMAGE_TAG:-dev}

  worker:
    image: ${DOCKER_REGISTRY:-local}/${API_IMAGE_NAME:-dify-api}:${IMAGE_TAG:-dev}

  worker_beat:
    image: ${DOCKER_REGISTRY:-local}/${API_IMAGE_NAME:-dify-api}:${IMAGE_TAG:-dev}

  web:
    image: ${DOCKER_REGISTRY:-local}/${WEB_IMAGE_NAME:-dify-web}:${IMAGE_TAG:-dev}
```

No other service definitions should be copied into the override file. Network, volume, environment, dependency, and health-check logic must stay inherited from the upstream compose file.

### 4. Build workflow

Build API and web images explicitly from the repository root.

Recommended commands:

```bash
docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-api:dev \
  ./api

docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-web:dev \
  ./web
```

If convenience targets are added later, they should wrap these exact semantics instead of inventing a different build path.

### 5. Runtime workflow

Start the stack from the `docker/` directory or from the repository root with explicit file paths.

Recommended command shape:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  up -d
```

This command keeps the official compose file as the base and layers the local image selection on top.

### 6. Verification workflow

Verification should cover both container startup and actual image selection.

Required checks:

1. Confirm compose services are running:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  ps
```

2. Confirm the services use the expected local images:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  images
```

3. Confirm the built commit is present in runtime metadata when needed:

```bash
docker compose \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  exec api env | rg '^COMMIT_SHA='
```

4. Perform one UI flow that exercises asynchronous work, not just page rendering:
   - log in
   - trigger an API action that requires the worker
   - confirm the task completes successfully

### 7. Failure handling

Expected failure classes and responses:

1. Build failure in `api/` or `web/`
   - Stop before compose startup.
   - Fix code or Dockerfile issue first.

2. Compose still pulls official image
   - Check whether `docker-compose.local-images.yaml` was included.
   - Check whether `docker/.env.local-images` was loaded.
   - Check whether the target tag exists locally.

3. API starts but worker fails
   - Verify `worker` and `worker_beat` point to the same local API image tag.
   - Check whether runtime env in `docker/.env` is compatible with the new code.

4. Web starts but points to wrong backend
   - Verify the runtime variables from `docker/.env` still align with compose service names and exposed URLs.

### 8. Testing strategy

Before image build:

- Run the backend tests relevant to the modified API code.
- Run the frontend checks relevant to the modified web code.

After image build:

- Verify containers start successfully.
- Verify the custom images are actually selected.
- Verify one synchronous UI flow.
- Verify one asynchronous worker-backed flow.

### 9. Upgrade compatibility

To reduce future merge friction:

- never modify `docker/docker-compose.yaml`
- keep the override file minimal
- avoid copying large service blocks from upstream compose
- keep local image variables isolated in a separate env file

This allows upstream compose updates to be consumed with minimal rework.

## Implementation Scope

### In scope

- local custom image naming
- local API and web image builds
- compose override for `api`, `worker`, `worker_beat`, `web`
- developer-facing documentation
- optional `Makefile` wrappers

### Out of scope

- CI-based image publishing
- remote registry authentication
- Kubernetes manifests
- multi-architecture build automation
- replacing middleware-only local development flow from `api/README.md`

## Acceptance Criteria

The design is successful when all of the following are true:

1. A developer can modify code in `api/` and `web/`, test it locally, and build custom images.
2. The developer can start the compose stack without changing `docker/docker-compose.yaml`.
3. `api`, `worker`, and `worker_beat` run from the same local API image tag.
4. `web` runs from the expected local web image tag.
5. Compose output shows local image references rather than upstream `langgenius/*` images.
6. One end-to-end flow involving worker execution completes successfully.

## Rollout Plan

1. Add the minimal override file and image env example.
2. Document the manual build and run commands.
3. Validate the flow on one local machine.
4. Add optional `Makefile` wrappers only after the manual workflow is proven stable.
