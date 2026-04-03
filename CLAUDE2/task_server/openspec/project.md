# Task Server Project

## Overview

Task Server is a Go/Gin backend REST API service for the Smart Task Assistant Flutter application. It provides task management, user authentication, and AI features with a robust 4-layer architecture.

## Technology Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| Go | 1.21+ | Programming language |
| Gin | v1.9.1 | HTTP web framework |
| GORM | v1.25.5 | ORM for database operations |
| PostgreSQL | v1.5.4 | Primary database driver |
| SQLite | v1.10.0 | Fallback database driver |
| JWT | v5.2.0 | Authentication tokens |
| Redis | v9.4.0 | Optional caching layer |
| Viper | v1.18.2 | Configuration management |
| Zap | v1.26.0 | Structured logging |

## Architecture

### 4-Layer Pattern

```
┌─────────────────────────────────────────────────────────┐
│                   Handler Layer (API)                   │
│           HTTP request/response handling                │
│              Input validation, JWT extraction           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Service Layer (Business Logic)         │
│           Business rules, ownership verification        │
│              Transaction management, errors             │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│               Repository Layer (Data Access)            │
│           GORM queries, database operations             │
│              SQL construction, result mapping           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                   Database Layer                        │
│         PostgreSQL (primary) / SQLite (fallback)        │
│              Connection pooling, migrations             │
└─────────────────────────────────────────────────────────┘
```

### Dependency Injection Pattern

All dependencies are injected in `cmd/server/main.go`:

```go
// Repository layer
userRepo := repository.NewUserRepository(database.GetDB())
taskRepo := repository.NewTaskRepository(database.GetDB())

// Service layer
userService := service.NewUserService(userRepo)
taskService := service.NewTaskService(taskRepo)

// Handler layer
userHandler := handler.NewUserHandler(userService)
taskHandler := handler.NewTaskHandler(taskService)
```

## Database Strategy

### Dual Database Support with Auto-Fallback

**Primary Database**: PostgreSQL (when `DB_HOST` and `DB_NAME` are configured)

**Fallback Database**: SQLite (file-based: `task_server.db`)

The fallback happens automatically in `pkg/database/database.go`:

1. Check if PostgreSQL config is valid (`DB_HOST` and `DB_NAME` not empty)
2. Attempt PostgreSQL connection
3. Verify connection with `Ping()`
4. On any failure, automatically fallback to SQLite
5. No manual intervention required

### Auto-Migration

On startup, GORM automatically migrates these models:

- `User` - User accounts with authentication
- `Task` - Task management with tags, reminders, priority
- `Tag` - Task categorization
- `Device` - Device management for sync
- `AISuggestion` - AI-generated task suggestions
- `AIChatMessage` - AI chat history

### Known Limitation: Date Functions

The statistics query in `task_repository.go` uses PostgreSQL-specific date functions:

```go
// PostgreSQL only
gorm.Expr("WEEKDAY(NOW())")
gorm.Expr("DATE_SUB(NOW(), INTERVAL ... DAY)")
gorm.Expr("DATE_ADD(NOW(), INTERVAL ... DAY)")
gorm.Expr("DATE_FORMAT(NOW(), '%Y-%m-01')")
gorm.Expr("LAST_DAY(NOW())")
```

**These will fail with SQLite**. This is a documented limitation that needs conditional queries.

## Authentication

### JWT Flow

1. User registers/logs in via `/api/v1/auth/*` endpoints
2. Server returns JWT token in response
3. Client includes token in `Authorization: Bearer {token}` header
4. `JWTAuth()` middleware extracts and validates token
5. User ID is stored in Gin context: `c.Set("user_id", claims.UserID)`
6. Handlers retrieve user ID: `userID := c.GetUint("user_id")`

### Protected Routes

All `/api/v1/tasks/*` and `/api/v1/user/*` routes require JWT authentication.

## Configuration

### Environment Variables

Configuration is loaded via `spf13/viper` from:

- **Development**: `configs/.env.local`
- **Production**: `configs/.env`

### Optional Services

PostgreSQL and Redis are **optional** for local development:

- PostgreSQL falls back to SQLite automatically
- Redis failures are logged but service continues without caching
- Default values ensure immediate startup after `go mod tidy`

### Key Config Sections

```go
type Config struct {
    Server   ServerConfig
    Database DatabaseConfig
    JWT      JWTConfig
    Redis    RedisConfig
    Log      LogConfig
}
```

## API Endpoints

### Public Routes (No Auth)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/` | Redirect to `/admin` |
| GET | `/welcome` | API information |
| POST | `/api/v1/auth/register` | User registration |
| POST | `/api/v1/auth/login` | User login |

### Protected Routes (JWT Required)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/user/profile` | Get user profile |
| PUT | `/api/v1/user/profile` | Update user profile |
| POST | `/api/v1/tasks` | Create task |
| GET | `/api/v1/tasks` | List tasks (paginated, filtered) |
| GET | `/api/v1/tasks/stats` | Task statistics |
| GET | `/api/v1/tasks/:id` | Get task details |
| PUT | `/api/v1/tasks/:id` | Update task |
| DELETE | `/api/v1/tasks/:id` | Delete task |
| PATCH | `/api/v1/tasks/:id/toggle` | Toggle completion |

### Task Filters

Task list supports filtering by:
- `completed` - Completion status
- `priority` - Priority level (0=low, 1=medium, 2=high)
- `category` - Category name
- `keyword` - Search in title/description
- `start_date` / `end_date` - Date range

## Project Structure

```
task_server/
├── cmd/
│   └── server/
│       └── main.go           # Application entry point, DI setup
├── internal/
│   ├── api/
│   │   ├── handler/          # HTTP request handlers
│   │   ├── middleware/       # JWT, CORS, logging, recovery
│   │   └── router/           # Route definitions
│   ├── config/               # Configuration loading
│   ├── model/                # GORM models, DTOs
│   ├── repository/           # Data access layer
│   └── service/              # Business logic layer
├── pkg/
│   ├── cache/                # Redis caching
│   ├── database/             # Database connection, migration
│   └── logger/               # Zap logging
├── configs/                  # Environment files
├── static/                   # Admin UI files
├── docs/                     # Documentation
├── scripts/                  # Utility scripts
└── data/                     # Data directory
```

## Common Operations

### Development

```bash
# Quick start
start_local.bat

# Manual run
go run cmd/server/main.go

# Build
go build -o bin/task_server.exe cmd/server/main.go

# Update deps
go mod tidy
```

### Testing

```bash
# Run all tests
go test ./...

# Run with coverage
go test ./... -cover
```

### Docker

```bash
# Start with compose
docker-compose up -d

# View logs
docker-compose logs -f app
```

## Key Patterns

### Ownership Verification

Service layer verifies task ownership before operations:

```go
func (s *TaskService) GetByID(id uint, userID uint) (*Task, error) {
    task, err := s.repo.FindByID(id)
    if err != nil {
        return nil, err
    }
    if task.UserID != userID {
        return nil, errors.New("unauthorized")
    }
    return task, nil
}
```

### Eager Loading

Use `Preload()` for relationships:

```go
err := r.db.Preload("Tags").First(&task, id).Error
```

### Error Handling

- Repository returns GORM errors directly
- Handler converts to HTTP responses
- Service adds business logic errors
- Logger used for consistent error logging

## Current Environment

- **Database**: SQLite (`task_server.db`)
- **Server**: http://localhost:8080
- **Admin UI**: http://localhost:8080/admin
- **API Base**: http://localhost:8080/api/v1