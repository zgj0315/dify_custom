# 本地 Docker 镜像工作流

文件名：`local-docker-images.md`

本文说明如何将 `api/` 和 `web/` 中已经在本地验证过的改动打包为 Docker 镜像，并通过 Docker Compose 启动，而无需修改 `docker/docker-compose.yaml`。

## 前置条件

- 已安装 Docker 和 Docker Compose。
- `docker/.env` 已存在，并包含你希望使用的部署配置。
- 代码改动已经在本地完成验证。

## 1. 准备本地镜像环境变量文件

复制镜像变量示例文件：

```bash
cp docker/.env.local-images.example docker/.env.local-images
```

默认值如下：

- `DOCKER_REGISTRY=local`
- `IMAGE_TAG=dev`
- `API_IMAGE_NAME=dify-api`
- `WEB_IMAGE_NAME=dify-web`

如果你需要同时保留多组本地构建结果，请在构建前修改 `IMAGE_TAG`。

## 2. 构建 API 镜像

```bash
docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-api:dev \
  ./api
```

该镜像会被 `api`、`worker` 和 `worker_beat` 共用。

## 3. 构建 Web 镜像

```bash
docker build \
  --build-arg COMMIT_SHA="$(git rev-parse --short HEAD)" \
  -t local/dify-web:dev \
  ./web
```

## 4. 使用覆盖文件启动整套服务

为避免 Compose 默认将项目名解析为 `docker`，这里显式使用项目名 `dify-local-images`：

```bash
docker compose \
  -p dify-local-images \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  up -d
```

## 5. 验证当前运行的镜像

检查服务状态：

```bash
docker compose \
  -p dify-local-images \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  ps
```

检查实际使用的镜像：

```bash
docker compose \
  -p dify-local-images \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  images
```

检查 API 容器内的构建提交号：

```bash
docker compose \
  -p dify-local-images \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  exec api env | rg '^COMMIT_SHA='
```

之后请实际跑一条依赖 `worker` 的 UI 流程，而不只是打开页面确认能加载。

## 6. 停止整套服务

```bash
docker compose \
  -p dify-local-images \
  --env-file docker/.env \
  --env-file docker/.env.local-images \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local-images.yaml \
  down
```

## 故障排查

- 如果 Compose 仍然显示 `langgenius/dify-api` 或 `langgenius/dify-web`，请确认命令中已经包含 `docker/docker-compose.local-images.yaml`。
- 如果镜像标签不一致，请确认 `docker/.env.local-images` 中的标签与 `docker build` 时使用的标签一致。
- 如果 `api` 能启动但 `worker` 启动失败，请确认这三个 API 类服务使用的是同一个本地 API 标签。
