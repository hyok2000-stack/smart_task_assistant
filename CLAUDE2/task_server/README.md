# Task Server - 智能任务中心后端服务

基于 Go 和 Gin 框架构建的智能任务中心后端服务，为 Flutter 智能任务助手应用提供 RESTful API 支持。

## 技术栈

- **语言**: Go 1.21+
- **框架**: Gin Web Framework
- **数据库**: PostgreSQL 15
- **缓存**: Redis 7
- **ORM**: GORM
- **认证**: JWT (golang-jwt/jwt)
- **日志**: Zap
- **容器**: Docker & Docker Compose

## 项目结构

```
task_server/
├── cmd/
│   └── server/          # 主程序入口
├── configs/             # 配置文件
├── internal/
│   ├── api/             # API 层
│   │   ├── handler/     # 请求处理器
│   │   ├── middleware/  # 中间件
│   │   └── router/      # 路由配置
│   ├── config/          # 配置管理
│   ├── model/           # 数据模型
│   ├── repository/      # 数据访问层
│   └── service/         # 业务逻辑层
├── pkg/
│   ├── cache/           # Redis 缓存
│   ├── database/        # 数据库连接
│   └── logger/          # 日志模块
├── Dockerfile           # Docker 构建文件
├── docker-compose.yml   # Docker Compose 配置
├── go.mod              # Go 模块文件
└── README.md           # 项目文档
```

## 功能特性

### 用户管理
- 用户注册
- 用户登录（JWT 认证）
- 用户信息查询
- 用户信息更新

### 任务管理
- 创建任务
- 查询任务列表（支持分页、过滤、搜索）
- 查询任务详情
- 更新任务
- 删除任务
- 切换任务完成状态
- 任务统计

### 核心特性
- JWT 认证授权
- RESTful API 设计
- 数据持久化
- Redis 缓存支持
- 日志记录
- 优雅关闭
- 健康检查
- CORS 跨域支持

## 快速开始

### 前置要求

- Go 1.21+
- Docker & Docker Compose（可选）
- PostgreSQL 15+（本地运行需要）
- Redis 7+（本地运行需要）

### 使用 Docker Compose（推荐）

1. 克隆项目：
```bash
git clone <repository-url>
cd task_server
```

2. 启动服务：
```bash
docker-compose up -d
```

3. 检查服务状态：
```bash
docker-compose ps
```

4. 查看日志：
```bash
docker-compose logs -f app
```

5. 停止服务：
```bash
docker-compose down
```

### 本地开发

1. 安装依赖：
```bash
go mod download
```

2. 复制配置文件：
```bash
cp configs/.env.example configs/.env
```

3. 修改配置文件 `configs/.env`：
```env
SERVER_HOST=0.0.0.0
SERVER_PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=taskuser
DB_PASSWORD=taskpass
DB_NAME=taskdb

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

JWT_SECRET=your-secret-key-here

LOG_LEVEL=info
```

4. 运行服务：
```bash
go run cmd/server/main.go
```

服务将在 `http://localhost:8080` 启动。

## API 文档

### 基础信息

- **Base URL**: `http://localhost:8080/api/v1`
- **认证方式**: Bearer Token (JWT)

### 认证接口

#### 用户注册
```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "username": "testuser",
  "email": "test@example.com",
  "password": "password123",
  "nickname": "测试用户"
}
```

#### 用户登录
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "testuser",
  "password": "password123"
}
```

响应：
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "username": "testuser",
    "email": "test@example.com",
    "nickname": "测试用户",
    "is_active": true
  }
}
```

### 用户接口

#### 获取用户信息
```http
GET /api/v1/user/profile
Authorization: Bearer {token}
```

#### 更新用户信息
```http
PUT /api/v1/user/profile
Authorization: Bearer {token}
Content-Type: application/json

{
  "nickname": "新昵称",
  "avatar": "avatar_url"
}
```

### 任务接口

#### 创建任务
```http
POST /api/v1/tasks
Authorization: Bearer {token}
Content-Type: application/json

{
  "title": "完成项目文档",
  "description": "编写项目的技术文档",
  "priority": 2,
  "due_date": "2024-03-31T18:00:00Z",
  "remind_at": "2024-03-31T09:00:00Z",
  "category": "工作",
  "tags": ["文档", "重要"]
}
```

#### 获取任务列表
```http
GET /api/v1/tasks?page=1&page_size=10&completed=false&priority=2
Authorization: Bearer {token}
```

查询参数：
- `page`: 页码（默认 1）
- `page_size`: 每页数量（默认 10）
- `completed`: 完成状态（true/false）
- `priority`: 优先级（0: 低, 1: 中, 2: 高）
- `category`: 分类
- `keyword`: 搜索关键词

#### 获取任务详情
```http
GET /api/v1/tasks/{id}
Authorization: Bearer {token}
```

#### 更新任务
```http
PUT /api/v1/tasks/{id}
Authorization: Bearer {token}
Content-Type: application/json

{
  "title": "更新后的任务标题",
  "completed": true
}
```

#### 删除任务
```http
DELETE /api/v1/tasks/{id}
Authorization: Bearer {token}
```

#### 切换任务完成状态
```http
PATCH /api/v1/tasks/{id}/toggle
Authorization: Bearer {token}
```

#### 获取任务统计
```http
GET /api/v1/tasks/stats
Authorization: Bearer {token}
```

响应：
```json
{
  "total": 100,
  "completed": 60,
  "pending": 40,
  "high_priority": 10,
  "overdue": 5,
  "this_week": 15,
  "this_month": 30
}
```

### 健康检查
```http
GET /health
```

响应：
```json
{
  "status": "ok",
  "message": "Task Server is running"
}
```

## 数据模型

### User（用户）
- `id`: 用户 ID
- `username`: 用户名（唯一）
- `email`: 邮箱（唯一）
- `password`: 密码（加密）
- `nickname`: 昵称
- `avatar`: 头像 URL
- `is_active`: 是否激活

### Task（任务）
- `id`: 任务 ID
- `user_id`: 用户 ID
- `title`: 任务标题
- `description`: 任务描述
- `completed`: 是否完成
- `priority`: 优先级（0: 低, 1: 中, 2: 高）
- `due_date`: 截止日期
- `remind_at`: 提醒时间
- `reminded`: 是否已提醒
- `category`: 分类
- `tags`: 标签
- `device_id`: 设备 ID（用于同步）
- `synced_at`: 同步时间
- `completed_at`: 完成时间

## 开发指南

### 添加新的 API 接口

1. 在 `internal/model/` 中定义数据模型
2. 在 `internal/repository/` 中实现数据访问逻辑
3. 在 `internal/service/` 中实现业务逻辑
4. 在 `internal/api/handler/` 中实现请求处理器
5. 在 `internal/api/router/` 中注册路由

### 运行测试

```bash
go test ./...
```

### 代码格式化

```bash
go fmt ./...
```

### 代码检查

```bash
go vet ./...
```

## 部署

### Docker 部署

1. 构建镜像：
```bash
docker build -t task-server:latest .
```

2. 运行容器：
```bash
docker run -p 8080:8080 task-server:latest
```

### 使用 Docker Compose

```bash
docker-compose up -d
```

## 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| SERVER_HOST | 服务监听地址 | 0.0.0.0 |
| SERVER_PORT | 服务端口 | 8080 |
| DB_HOST | 数据库地址 | localhost |
| DB_PORT | 数据库端口 | 5432 |
| DB_USER | 数据库用户名 | taskuser |
| DB_PASSWORD | 数据库密码 | taskpass |
| DB_NAME | 数据库名称 | taskdb |
| REDIS_HOST | Redis 地址 | localhost |
| REDIS_PORT | Redis 端口 | 6379 |
| REDIS_DB | Redis 数据库编号 | 0 |
| REDIS_PASSWORD | Redis 密码 | - |
| JWT_SECRET | JWT 密钥 | - |
| LOG_LEVEL | 日志级别 | info |

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 联系方式

如有问题，请联系：hyok2000-stack@users.noreply.github.com