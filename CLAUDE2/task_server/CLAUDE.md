# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Task Server is a Go/Gin backend REST API service for the Smart Task Assistant Flutter application. It provides task management, user authentication, task forwarding with bidirectional sync, AI features, JWT authentication, and optional Redis caching.

## Common Commands

### Development
```bash
# Quick start (checks deps, builds, runs with SQLite)
start_local.bat

# Manual build
go build -o bin/task_server.exe cmd/server/main.go

# Run locally (uses SQLite by default, falls back from PostgreSQL)
go run cmd/server/main.go

# Update dependencies and rebuild
update_deps_and_build.bat

# Update dependencies only
go mod tidy
```

### Testing & Quality
```bash
# Run all tests
go test ./...

# Run tests with coverage
go test ./... -cover

# Format code
go fmt ./...

# Code analysis
go vet ./...
```

### Docker Deployment
```bash
# Build and start with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

## Architecture

### 4-Layer Architecture Pattern

```
Handler (API) → Service (Business Logic) → Repository (Data Access) → Database
```

**Flow Example**: Creating a task
1. `task_handler.go` receives HTTP request, validates input, extracts userID from JWT context
2. `task_service.go` applies business rules (ownership check, timestamp handling)
3. `task_repository.go` executes database queries via GORM
4. `database.go` manages connection (PostgreSQL primary, SQLite fallback)

### Dependency Injection

All dependencies are injected in `cmd/server/main.go`:
```go
userRepo := repository.NewUserRepository(database.GetDB())
taskRepo := repository.NewTaskRepository(database.GetDB())
forwardRepo := repository.NewForwardRepository(database.GetDB())

userService := service.NewUserService(userRepo)
taskService := service.NewTaskService(taskRepo)
forwardService := service.NewForwardService(forwardRepo)

userHandler := handler.NewUserHandler(userService)
taskHandler := handler.NewTaskHandler(taskService)
forwardHandler := handler.NewForwardHandler(forwardService)
```

### Database Strategy

**Dual database support with automatic fallback:**
- **Primary**: PostgreSQL (if configured with valid `DB_HOST` and `DB_NAME`)
- **Fallback**: SQLite (file-based: `task_server.db`)

The fallback happens automatically in `pkg/database/database.go`:
1. Check if PostgreSQL config is valid
2. Attempt connection and verify with `Ping()`
3. On any failure, automatically fallback to SQLite
4. No manual intervention required

**Auto-migration** runs on startup for: `User`, `Task`, `Tag`, `Device`, `AISuggestion`, `AIChatMessage`, `TaskForward`

### Known Limitation: Date Functions

The statistics query in `task_repository.go` uses PostgreSQL-specific date functions:
```go
gorm.Expr("WEEKDAY(NOW())")
gorm.Expr("DATE_SUB(NOW(), INTERVAL ... DAY)")
gorm.Expr("DATE_ADD(NOW(), INTERVAL ... DAY)")
gorm.Expr("DATE_FORMAT(NOW(), '%Y-%m-01')")
gorm.Expr("LAST_DAY(NOW())")
```

**These will fail with SQLite**. This is a documented limitation requiring conditional queries based on active database driver.

## Task Forwarding System

The forwarding feature uses a bidirectional sync model implemented in `internal/model/other.go`:

### TaskForward Model
- `TaskID` - Original task being forwarded
- `ForwardedTaskID` - The newly created copy for the recipient
- `ForwardedBy` - User who initiated the forward
- `ForwardedTo` - User receiving the forward
- `Deadline` - Optional deadline for the forwarded task
- `IsActive` - Whether the forward is still active
- `RevokedAt` - When the forward was revoked

### Service Layer Errors
The `forward_service.go` defines typed errors:
- `ErrTaskNotFound` - Task doesn't exist
- `ErrUserNotFound` - Target user doesn't exist
- `ErrNoPermission` - User doesn't own the task
- `ErrForwardToSelf` - Cannot forward to self
- `ErrAlreadyForwarded` - Task already forwarded to this user
- `ErrCircularForward` - Would create a forward cycle
- `ErrExceedLimit` - Forward count exceeds limit (max 10)
- `ErrInvalidDeadline` - Deadline is invalid
- `ErrForwardRevoked` - Forward already revoked

### Handler Pattern
`forward_handler.go` uses a helper function `getUserID()` to safely extract user ID from Gin context, handling uint, float64, and int types returned from JWT claims.

## Configuration

Configuration is loaded via `spf13/viper` from:
- **Development**: `configs/.env.local`
- **Production**: `configs/.env`

**No required services** for local dev: PostgreSQL and Redis are optional with sensible defaults.

Key config sections:
```go
type Config struct {
    Server   ServerConfig   // Host, Port, Mode
    Database DatabaseConfig // PostgreSQL connection details
    Redis    RedisConfig    // Optional caching
    JWT      JWTConfig      // Secret, ExpirationHours
    AI       AIConfig       // APIKey, BaseURL
    Weather  WeatherConfig  // APIKey
    Log      LogConfig      // Level, Output
}
```

## API Endpoints

### Public Routes (No Auth)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/` | Redirect to `/admin` (static UI) |
| GET | `/welcome` | API information |
| POST | `/api/v1/auth/register` | User registration |
| POST | `/api/v1/auth/login` | User login (returns JWT) |

### Protected Routes (JWT Required)

#### User Management
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/user/profile` | Get user profile |
| PUT | `/api/v1/user/profile` | Update user profile |
| GET | `/api/v1/users/search` | Search users by keyword |

#### Task Management
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/tasks` | Create task |
| GET | `/api/v1/tasks` | List tasks (paginated, filtered) |
| GET | `/api/v1/tasks/stats` | Task statistics |
| GET | `/api/v1/tasks/:id` | Get task details |
| PUT | `/api/v1/tasks/:id` | Update task |
| DELETE | `/api/v1/tasks/:id` | Delete task |
| PATCH | `/api/v1/tasks/:id/toggle` | Toggle completion |

#### Task Forwarding
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/tasks/:id/forward` | Forward task to users (creates copies) |
| GET | `/api/v1/tasks/:id/forwards` | Get forward records for a task |
| GET | `/api/v1/forwards/received` | Get tasks received by current user (paginated) |
| POST | `/api/v1/forwards/:id/revoke` | Revoke a task forward |

### Task Filters
Task list supports filtering by:
- `completed` - Completion status (true/false)
- `priority` - Priority level (0=low, 1=medium, 2=high)
- `category` - Category name
- `keyword` - Search in title/description
- `start_date` / `end_date` - Date range

## Important Implementation Notes

### Adding New Features
Follow the 4-layer pattern:
1. Add models/DTOs to `internal/model/`
2. Add repository methods to `internal/repository/`
3. Add service logic to `internal/service/`
4. Add handler to `internal/api/handler/`
5. Register route in `internal/api/router/router.go`

### Authentication Flow
1. User registers/logs in → receives JWT token
2. Client includes `Authorization: Bearer {token}` header
3. `JWTAuth()` middleware validates token
4. User ID stored in context: `c.Set("user_id", claims.UserID)`
5. Handlers retrieve: `userID := c.GetUint("user_id")`

### Ownership Verification
Service layer verifies task ownership before all operations:
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

### GORM Patterns
- Use `Preload()` for eager loading: `Preload("Tags")`
- Use `gorm.Expr()` for raw SQL: `gorm.Expr("NOW()")`
- Repository methods return GORM errors directly
- Handlers convert to HTTP responses

### Error Handling
- Use `pkg/logger` for consistent logging with Zap
- Service layer defines typed errors for business rules
- Handler layer maps errors to appropriate HTTP status codes
- Use `getuserID()` helper in handlers for safe JWT context extraction

### Cursor Rules (.clinerules)
The project uses Cursor-style coding rules:
- Plan first, implement second
- Write tests before/with implementation
- Follow DRY and SOLID principles
- Always read existing files before making changes
- Use markdown for all code blocks

## Current Environment
- **Database**: SQLite (`task_server.db`)
- **Server**: http://localhost:8080
- **Admin UI**: http://localhost:8080/admin
- **API Base**: http://localhost:8080/api/v1