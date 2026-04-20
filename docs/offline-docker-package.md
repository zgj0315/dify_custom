# Dify 离线 Docker 安装包

本文说明如何在联网构建机上生成 Dify 离线安装包，并在无互联网、但具备 Docker Compose 的服务器上完成部署。

## 适用范围

- 基于 [docs/local-docker-images.md](./local-docker-images.md) 的本地镜像构建方式。
- 覆盖默认全栈和默认 `weaviate` 向量库。
- 目标服务器需要已安装 Docker 和 Docker Compose。
- 本方案面向新部署或空数据卷部署，不包含历史数据迁移。

## 1. 在联网构建机生成离线包

先准备本地镜像环境变量文件：

```bash
cp docker/.env.local-images.example docker/.env.local-images
```

然后执行离线打包脚本：

```bash
bash docker/offline/build-offline-package.sh \
  --env-file docker/.env \
  --image-env-file docker/.env.local-images \
  --output dist/offline
```

脚本会完成以下动作：

- 按本地镜像流程构建 `api` 和 `web` 镜像。
- 解析默认部署所需的全部镜像清单。
- 导出单个镜像归档 `images.tar`。
- 组装部署所需的 `docker/` 运行时文件、安装脚本、校验脚本和 manifest。
- 输出离线安装包压缩文件。

## 2. 离线包内容

离线安装包包含以下主要内容：

- `images/images.tar`
- `docker/docker-compose.yaml`
- `docker/docker-compose.local-images.yaml`
- `docker/.env.example`
- `docker/.env.local-images.example`
- `docker/nginx/`
- `docker/ssrf_proxy/`
- `docker/certbot/`
- `scripts/install-offline.sh`
- `scripts/verify-offline.sh`
- `manifest/images.txt`
- `manifest/package-info.txt`

## 3. 在离线服务器部署

将压缩包上传到离线服务器并解压。

先在解压后的 `docker/` 目录中准备 `.env`：

```bash
cp docker/.env.example docker/.env
```

按实际部署环境修改 `docker/.env`，然后执行安装脚本：

```bash
bash scripts/install-offline.sh --package-root .
```

安装脚本会自动：

- 从 `images/images.tar` 导入镜像。
- 在缺少 `docker/.env.local-images` 时从示例文件生成。
- 使用 `docker-compose.yaml` 和 `docker-compose.local-images.yaml` 启动整套服务。

## 4. 部署后校验

执行校验脚本：

```bash
bash scripts/verify-offline.sh --package-root .
```

校验脚本会检查：

- `docker compose ps`
- `docker compose images`
- `api` 容器内的 `COMMIT_SHA`

之后还应实际执行一条依赖 `worker` 的 UI 流程，而不是只确认页面可访问。

## 5. 注意事项

- 当前版本只覆盖默认 `postgresql + weaviate` 组合，不包含所有可选 profiles。
- 离线包不主动关闭插件市场、更新检查等公网依赖；在无外网环境下，这些能力可能不可用。
- 构建机与目标服务器的 CPU 架构需要一致。
