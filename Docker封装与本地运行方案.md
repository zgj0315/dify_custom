# Docker 封装与本地运行方案

## 1. 目标

将当前已在本地开发环境中跑通的程序，封装为一组可构建、可启动、可验证的 Docker 镜像与容器，满足以下目标：

- 前端、后端、Worker、Beat 均运行在容器内
- 中间件继续使用现有 Docker 方案
- 本地可一键构建和启动
- 镜像来源于当前仓库代码，而不是官方预构建镜像
- 保留后续发布到测试环境或生产环境的延展性

## 2. 当前工程基础

仓库中已经具备容器化基础能力：

- 后端镜像构建文件：[api/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/Dockerfile)
- 前端镜像构建文件：[web/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/Dockerfile)
- 官方整站编排文件：[docker/docker-compose.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.yaml)
- 本地中间件编排文件：[docker/docker-compose.middleware.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.middleware.yaml)

因此不需要重新设计运行时，只需要把官方 compose 中使用的远程镜像：

- `langgenius/dify-api`
- `langgenius/dify-web`

替换为基于当前源码 `build` 出来的自定义镜像。

## 3. 推荐方案

推荐采用“两层编排”：

### 3.1 中间件层

继续复用现有中间件编排：

- Postgres
- Redis
- Sandbox
- Plugin Daemon
- SSRF Proxy
- Weaviate

对应文件：

- [docker/docker-compose.middleware.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.middleware.yaml)

这一层已经在本地验证过，稳定性最高，不建议重做。

### 3.2 应用层

新增一份“源码构建版”的 compose，例如：

- `docker/docker-compose.local-build.yaml`

该文件只负责应用相关容器：

- `api`
- `worker`
- `worker_beat`
- `web`
- `nginx`

中间件则直接依赖已存在的 `middleware` 容器和网络。

## 4. 目标容器设计

### 4.1 api

职责：

- Flask API
- 自动执行数据库迁移
- 提供 `5001` 服务

镜像来源：

- 基于 [api/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/Dockerfile) 构建

建议镜像名：

- `dify-custom-api:local`

关键点：

- `MODE=api`
- 保持 `MIGRATION_ENABLED=true`
- 复用挂载目录 `/app/api/storage`

### 4.2 worker

职责：

- Celery 异步任务消费

镜像来源：

- 与 `api` 共用同一后端镜像

建议配置：

- `MODE=worker`

### 4.3 worker_beat

职责：

- 定时任务调度

镜像来源：

- 与 `api` 共用同一后端镜像

建议配置：

- `MODE=beat`

### 4.4 web

职责：

- Next.js 前端服务

镜像来源：

- 基于 [web/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/Dockerfile) 构建

建议镜像名：

- `dify-custom-web:local`

关键点：

- 容器内访问 API 应该走 `http://api:5001`
- 对外暴露前端可通过 `nginx` 或直接映射 `3000`

### 4.5 nginx

职责：

- 对外统一暴露访问入口
- 转发 `/console/api`、`/api`、`/v1` 到 `api`
- 转发页面请求到 `web`

镜像来源：

- 直接复用 nginx 官方镜像
- 复用仓库现有模板：
  - [docker/nginx/nginx.conf.template](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/nginx/nginx.conf.template)
  - [docker/nginx/proxy.conf.template](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/nginx/proxy.conf.template)
  - [docker/nginx/conf.d/default.conf.template](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/nginx/conf.d/default.conf.template)

## 5. 编排方式

推荐拆成两步：

### 5.1 启动中间件

使用已有文件：

- `docker compose -f docker/docker-compose.middleware.yaml --profile weaviate -p dify up -d`

### 5.2 构建并启动应用层

新增应用层 compose，例如：

- `docker compose -f docker/docker-compose.local-build.yaml -p dify-app up -d --build`

这样分层的好处：

- 中间件和业务镜像解耦
- 改前后端代码时只需要重建应用层
- 数据卷与数据库不会因为重建应用层被影响

## 6. 环境变量设计

建议新增一份专用于“本地源码构建容器运行”的环境模板，例如：

- `docker/app.env.localbuild.example`

配置原则如下。

### 6.1 API / Worker / Beat

数据库与中间件地址全部改为容器网络内地址：

- `DB_HOST=db`
- `REDIS_HOST=redis`
- `WEAVIATE_ENDPOINT=http://weaviate:8080`
- `CODE_EXECUTION_ENDPOINT=http://sandbox:8194`
- `PLUGIN_DAEMON_URL=http://plugin_daemon:5002`
- `PLUGIN_DIFY_INNER_API_URL=http://api:5001`

关键要求：

- `PLUGIN_DAEMON_KEY` 必须与中间件层一致
- `PLUGIN_DIFY_INNER_API_KEY` 必须与 plugin daemon 配置一致

### 6.2 Web

前端容器内访问 API 时建议使用：

- `CONSOLE_API_URL=http://api:5001`
- `APP_API_URL=http://api:5001`

若通过 nginx 对外暴露，则浏览器访问入口仍是：

- `http://localhost`

### 6.3 Nginx

对外映射：

- `80 -> nginx`
- 可选 `443 -> nginx`

## 7. 镜像构建策略

### 7.1 后端镜像

直接复用现有 [api/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/Dockerfile)。

建议补充的约束：

- 构建上下文设为 `./api`
- 增加 `COMMIT_SHA` build arg
- 使用固定 tag，例如 `dify-custom-api:local`

### 7.2 前端镜像

直接复用现有 [web/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/Dockerfile)。

建议补充的约束：

- 构建上下文设为 `./web`
- 使用固定 tag，例如 `dify-custom-web:local`

## 8. 本地运行拓扑

推荐的本地运行拓扑如下：

1. `db`
2. `redis`
3. `sandbox`
4. `plugin_daemon`
5. `ssrf_proxy`
6. `weaviate`
7. `api`
8. `worker`
9. `worker_beat`
10. `web`
11. `nginx`

对外访问入口：

- `http://localhost`

容器内部访问关系：

- `web -> api:5001`
- `api -> db:5432`
- `api -> redis:6379`
- `api -> plugin_daemon:5002`
- `api -> sandbox:8194`
- `api -> weaviate:8080`
- `plugin_daemon -> api:5001`

## 9. 推荐实施步骤

### 第一阶段：补齐编排文件

新增：

- `docker/docker-compose.local-build.yaml`
- `docker/app.env.localbuild.example`

其中：

- `api/worker/beat` 使用 `build`
- `web` 使用 `build`
- `nginx` 使用官方镜像
- 中间件通过外部网络或直接复用 `docker-compose.middleware.yaml` 启动结果

### 第二阶段：补齐启动脚本

新增脚本：

- `dev/build-images`
- `dev/start-docker-app`
- `dev/start-docker-stack`
- `dev/docker-status`

建议职责：

- `build-images`：构建 `api` 与 `web` 镜像
- `start-docker-app`：启动应用层容器
- `start-docker-stack`：先起中间件，再起应用层
- `docker-status`：输出 compose ps 与关键 URL

### 第三阶段：验证运行

验证顺序：

1. `docker compose ps`
2. `api` 日志中无 migration 异常
3. `web` 日志中无启动异常
4. 打开 `http://localhost/install`
5. 完成初始化后打开 `http://localhost/apps`
6. 检查是否仍出现 `Internal Server Error`

## 10. 风险点与处理建议

### 10.1 插件相关配置不一致

这是当前项目里最容易出问题的部分。

必须保证以下值在 `api` 与 `plugin_daemon` 间一致：

- `PLUGIN_DAEMON_KEY`
- `PLUGIN_DIFY_INNER_API_KEY`
- `PLUGIN_DAEMON_URL`
- `PLUGIN_DIFY_INNER_API_URL`

否则会再次出现模型提供商接口 401/500。

### 10.2 migration 时机

建议只让 `api` 容器负责 migration，`worker` 和 `beat` 不负责。

原因：

- 避免多个容器同时迁移数据库
- 避免启动竞争

### 10.3 Web 运行地址

如果浏览器直接访问 `web:3000`，则前端 API 地址配置容易混乱。

建议统一通过 `nginx` 对外暴露，避免：

- 页面地址和 API 地址不一致
- `localhost:3000`、`localhost:5001`、`localhost` 三套入口混用

### 10.4 存储目录

建议为后端保留独立 volume：

- `./docker/volumes/app/storage:/app/api/storage`

否则上传文件、缓存、插件工作目录容易丢失。

## 11. 推荐最终形态

本地源码封装 Docker 的推荐最终形态如下：

- 中间件层：继续使用 [docker/docker-compose.middleware.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.middleware.yaml)
- 应用层：新增 `docker-compose.local-build.yaml`
- 后端镜像：基于 [api/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/Dockerfile) 构建
- 前端镜像：基于 [web/Dockerfile](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/Dockerfile) 构建
- 对外入口：统一由 `nginx` 暴露 `http://localhost`

## 12. 结论

最合适的实现方式不是重写整套 Docker 方案，而是：

- 保留已经验证过的中间件容器
- 把官方 `api/web` 镜像替换成当前仓库源码构建镜像
- 用独立 compose 管理应用层
- 用统一 env 模板解决容器间地址与密钥一致性问题

这样改动最小，落地最快，也最接近后续部署形态。

如果继续推进实施，下一步应直接落地：

1. `docker/docker-compose.local-build.yaml`
2. `docker/app.env.localbuild.example`
3. `dev/start-docker-stack`
4. 本地构建与启动验证
