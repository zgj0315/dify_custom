# 本地开发与 Docker 启动简要说明

## 1. 本地源码开发

适合前后端联调、断点调试、快速改代码。

### 启动顺序

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

### 访问地址

- Web: `http://localhost:3000`
- API: `http://localhost:5001`

### 相关配置文件

- 后端模板：[api/.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/api/.env.localdev.example)
- 前端模板：[web/.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/web/.env.localdev.example)
- 中间件模板：[docker/middleware.env.localdev.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/middleware.env.localdev.example)

### 说明

- `./dev/start-api` 会自动执行数据库迁移
- 详细说明见：[本地开发环境设计方案.md](/Users/zhaoguangjian/github/zgj0315/dify_custom/本地开发环境设计方案.md)

## 2. Docker 启动全部服务

适合整体验证、模拟部署环境、统一启动整套服务。

### 一键启动

```bash
./dev/start-docker-stack
```

### 分步启动

1. 启动中间件

```bash
./dev/start-middleware
```

2. 启动应用层

```bash
./dev/start-docker-app
```

### 查看状态

```bash
./dev/docker-status
```

### 访问地址

- 统一入口：`http://localhost`
- API 直连：`http://localhost:5001`

### 相关文件

- 应用层编排：[docker/docker-compose.local-build.yaml](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/docker-compose.local-build.yaml)
- Docker 环境模板：[docker/app.env.localbuild.example](/Users/zhaoguangjian/github/zgj0315/dify_custom/docker/app.env.localbuild.example)
- 详细方案：[Docker封装与本地运行方案.md](/Users/zhaoguangjian/github/zgj0315/dify_custom/Docker封装与本地运行方案.md)

## 3. 如何选择

- 需要改代码、打断点、实时联调：使用“本地源码开发”
- 需要整体验证、接近部署环境：使用“Docker 启动全部服务”
