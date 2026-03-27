# 本地开发与 Docker 说明

## 1. 结构概览

当前仓库运行时主要分为两类代码模块：

| 模块 | 作用 | 相关容器 |
| --- | --- | --- |
| `api/` | Flask API、Celery Worker、Beat | `api`、`worker`、`worker_beat` |
| `web/` | Next.js 前端 | `web` |

外围服务包括：

- `nginx`
- `db`
- `redis`
- `sandbox`
- `plugin_daemon`
- `ssrf_proxy`
- `weaviate`

镜像来源：

| 服务 | 镜像来源 |
| --- | --- |
| `api`、`worker`、`worker_beat` | [api/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/Dockerfile) |
| `web` | [web/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/Dockerfile) |
| `nginx` | 官方 `nginx` 镜像 |
| 中间件服务 | 外部镜像或官方镜像 |

## 2. 本地源码开发

适合改代码、联调、断点调试。

运行方式：

- 宿主机运行：`api`、`worker`、`worker_beat`、`web`
- Docker 运行：`db`、`redis`、`sandbox`、`plugin_daemon`、`ssrf_proxy`、`weaviate`

启动顺序：

1. 启动中间件

```bash
./dev/start-middleware
```

2. 启动后端

```bash
./dev/start-api
```

3. 启动 Worker

```bash
./dev/start-worker
```

4. 启动前端

```bash
./dev/start-web
```

5. 可选启动 Beat

```bash
./dev/start-beat
```

也可以先执行：

```bash
./dev/start-dev-stack
```

访问地址：

- Web：`http://localhost:3000`
- API：`http://localhost:5001`

说明：

- `./dev/start-api` 会自动执行数据库迁移
- `./dev/start-api`、`./dev/start-web`、`./dev/start-middleware` 在缺少配置文件时会自动从模板复制

本地开发配置模板：

- [api/.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/.env.localdev.example)
- [web/.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/.env.localdev.example)
- [docker/middleware.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/middleware.env.localdev.example)

## 3. Docker 启动全部服务

适合整体验证和接近部署方式的运行。

容器分层：

- 中间件层：`dify-middleware`
- 应用层：`dify-app`

### 3.1 中间件层

包含：

- `db`
- `redis`
- `sandbox`
- `plugin_daemon`
- `ssrf_proxy`
- `weaviate`

编排文件：

- [docker/docker-compose.middleware.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.middleware.yaml)

### 3.2 应用层

包含：

- `api`
- `worker`
- `worker_beat`
- `web`
- `nginx`

编排文件：

- [docker/docker-compose.local-build.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.local-build.yaml)

启动方式：

一键启动：

```bash
./dev/start-docker-stack
```

分步启动：

```bash
./dev/start-middleware
./dev/start-docker-app
```

仅构建镜像：

```bash
./dev/build-images
```

查看状态：

```bash
./dev/docker-status
```

访问地址：

- 统一入口：`http://localhost`
- API 直连：`http://localhost:5001`

说明：

- Docker 模式下前端不再直接对外暴露 `3000`
- 页面统一通过 `nginx` 提供
- 应用层依赖中间件层外部网络，必须先启动中间件层

Docker 配置模板：

- [docker/app.env.localbuild.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/app.env.localbuild.example)

## 4. 关键配置

浏览器公开地址：

- `CONSOLE_API_URL=http://localhost`
- `APP_API_URL=http://localhost`
- `FILES_URL=http://localhost`

容器内部依赖地址：

- `DB_HOST=db`
- `REDIS_HOST=redis`
- `WEAVIATE_ENDPOINT=http://weaviate:8080`
- `CODE_EXECUTION_ENDPOINT=http://sandbox:8194`
- `PLUGIN_DAEMON_URL=http://plugin_daemon:5002`
- `PLUGIN_DIFY_INNER_API_URL=http://api:5001`

外部网络：

- `dify-middleware_default`
- `dify-middleware_ssrf_proxy_network`

## 5. 常用文件

- [dev/start-middleware](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-middleware)
- [dev/start-api](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-api)
- [dev/start-worker](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-worker)
- [dev/start-web](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-web)
- [dev/start-beat](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-beat)
- [dev/start-dev-stack](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-dev-stack)
- [dev/build-images](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/build-images)
- [dev/start-docker-app](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-docker-app)
- [dev/start-docker-stack](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/start-docker-stack)
- [dev/docker-status](/Users/zhaoguangjian/github/zgj0315/dify_custom/dev/docker-status)
