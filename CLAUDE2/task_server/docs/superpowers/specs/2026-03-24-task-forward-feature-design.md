# 任务转发功能设计文档

**日期**: 2026-03-24
**项目**: Task Server - 任务转发对象管理功能
**状态**: 设计中

---

## 1. 概述

### 1.1 目标

为 C 端用户提供任务转发功能，允许用户将任务转发给其他用户，并实现状态同步和过期管理。

### 1.2 核心需求

- 支持用户通过搜索查找其他用户并转发任务
- 支持一对多转发（最多10人）
- 转发时可以附带留言和截止时间
- 转发任务自动复制给接收方
- 原任务和转发任务状态同步（所有字段）
- 超过截止时间自动标记为过期
- 支持转发者随时撤回转发
- 显示转发者和原始任务信息

---

## 2. 数据模型设计

### 2.1 TaskForward 模型（新增）

```go
type TaskForward struct {
    ID              uint           `gorm:"primarykey"`
    CreatedAt       time.Time
    UpdatedAt       time.Time
    DeletedAt       gorm.DeletedAt

    TaskID          uint           `gorm:"not null;index"`         // 原任务ID（转发方的任务）
    ForwardedTaskID uint           `gorm:"not null;index"`         // 转发后的任务ID（接收方的任务）
    ForwardedBy     uint           `gorm:"not null;index"`         // 转发者ID
    ForwardedTo     uint           `gorm:"not null;index"`         // 接收者ID
    Message         string         `gorm:"type:text"`              // 转发留言
    Deadline        *time.Time                                     // 截止时间（过期自动标记）
    IsExpired       bool           `gorm:"default:false"`          // 是否已过期
    IsActive        bool           `gorm:"default:true"`           // 关系是否有效（撤回后为false）
    RevokedAt       *time.Time                                     // 撤回时间

    // 关联关系
    Task            Task           `gorm:"foreignKey:TaskID"`
    ForwardedTask   Task           `gorm:"foreignKey:ForwardedTaskID"`
    Forwarder       User           `gorm:"foreignKey:ForwardedBy"`
    Receiver        User           `gorm:"foreignKey:ForwardedTo"`
}
```

### 2.2 Task 模型（修改）

```go
type Task struct {
    // ... 现有字段 ...
    IsForwarded  bool           `gorm:"default:false"`  // 是否为转发的任务
    ForwardedBy  *uint          // 转发者ID
    ParentTaskID *uint          `gorm:"index"`          // 原任务ID（如果是转发的任务）
    IsExpired    bool           `gorm:"default:false"`  // 是否过期（转发的任务）
}
```

### 2.3 请求/响应模型

```go
// 搜索用户请求
type SearchUsersRequest struct {
    Keyword string `form:"keyword" binding:"required,min=1"`
    Limit   int    `form:"limit,default=10"`
}

// 搜索用户响应
type SearchUsersResponse struct {
    Users []User `json:"users"`
    Total int    `json:"total"`
}

// 转发任务请求
type TaskForwardRequest struct {
    TargetUserIDs []uint  `json:"target_user_ids" binding:"required,min=1,max=10"`
    Message       string  `json:"message" binding:"max=500"`
    Deadline      string  `json:"deadline"` // ISO 8601 格式
}

// 转发任务响应（一对多转发）
type TaskForwardListResponse struct {
    Forwards []TaskForwardResponse `json:"forwards"`
    Total    int                   `json:"total"`
}

// 转发任务响应
type TaskForwardResponse struct {
    ForwardID      uint      `json:"forward_id"`
    ForwardedTaskID uint     `json:"forwarded_task_id"`
    TaskID         uint      `json:"task_id"`
    ForwardedBy    User      `json:"forwarded_by"`
    ForwardedTo    User      `json:"forwarded_to"`
    Message        string    `json:"message"`
    Deadline       *time.Time `json:"deadline"`
    CreatedAt      time.Time `json:"created_at"`
}

// 撤回转发请求
type RevokeForwardRequest struct {
    Reason string `json:"reason" binding:"max=200"`
}

// 转发记录响应
type ForwardRecordResponse struct {
    ID              uint      `json:"id"`
    TaskID          uint      `json:"task_id"`
    ForwardedTaskID uint      `json:"forwarded_task_id"`
    ForwardedBy     uint      `json:"forwarded_by"`
    ForwardedTo     uint      `json:"forwarded_to"`
    Message         string    `json:"message"`
    Deadline        *time.Time `json:"deadline"`
    IsExpired       bool      `json:"is_expired"`
    IsActive        bool      `json:"is_active"`
    RevokedAt       *time.Time `json:"revoked_at"`
    CreatedAt       time.Time `json:"created_at"`
}
```

---

## 3. 架构设计

### 3.1 目录结构

```
internal/
├── api/handler/
│   └── forward_handler.go      # 转发相关API处理器
├── repository/
│   └── forward_repository.go   # 转发数据访问层
├── service/
│   └── forward_service.go      # 转发业务逻辑层
└── model/
    ├── task.go                  # 修改：添加转发字段
    └── other.go                 # 修改：添加 TaskForward 模型
```

### 3.2 层级职责

| 层级 | 职责 |
|-----|------|
| Handler | 处理HTTP请求，参数验证，调用Service层，格式化响应 |
| Service | 核心业务逻辑，状态同步，权限验证，事务管理 |
| Repository | 数据库CRUD操作，查询构建 |

### 3.3 状态同步机制

使用 Service 层的显式同步方法，避免 GORM 钩子的无限循环问题：

```go
// Service 层显式同步方法
func (s *ForwardService) SyncTaskStatus(ctx context.Context, taskID uint, sourceUserID uint) error {
    // 使用事务保证一致性
    return s.db.Transaction(func(tx *gorm.DB) error {
        // 查找关联的转发关系
        var forwards []TaskForward
        tx.Where("task_id = ? AND is_active = true", taskID).Find(&forwards)

        // 获取源任务
        var sourceTask Task
        tx.First(&sourceTask, taskID)

        // 同步到所有转发任务
        for _, forward := range forwards {
            // 跳过源用户自己的转发
            if forward.ForwardedTo == sourceUserID {
                continue
            }

            // 使用 updatedAt 时间戳防止覆盖更新
            var targetTask Task
            tx.First(&targetTask, forward.ForwardedTaskID)

            // 只有当源任务更新时间更新时才同步
            if sourceTask.UpdatedAt.After(targetTask.UpdatedAt) {
                // 同步字段（排除 ID、ParentTaskID、ForwardedBy 等元数据）
                updates := map[string]interface{}{
                    "title":       sourceTask.Title,
                    "description": sourceTask.Description,
                    "completed":   sourceTask.Completed,
                    "priority":    sourceTask.Priority,
                    "due_date":    sourceTask.DueDate,
                    "remind_at":   sourceTask.RemindAt,
                    "category":    sourceTask.Category,
                    "is_expired":  sourceTask.IsExpired,
                }

                tx.Model(&Task{}).Where("id = ?", forward.ForwardedTaskID).Updates(updates)
            }
        }

        return nil
    })
}

// 反向同步：转发任务更新到原任务
func (s *ForwardService) SyncToParentTask(ctx context.Context, forwardedTaskID uint) error {
    return s.db.Transaction(func(tx *gorm.DB) error {
        var forward TaskForward
        tx.First(&forward, "forwarded_task_id = ? AND is_active = true", forwardedTaskID)

        if forward.ID == 0 {
            return nil // 没有关联的转发
        }

        var sourceTask Task
        tx.First(&sourceTask, forwardedTaskID)

        var parentTask Task
        tx.First(&parentTask, forward.TaskID)

        // 只有当转发任务更新时间更新时才同步
        if sourceTask.UpdatedAt.After(parentTask.UpdatedAt) {
            updates := map[string]interface{}{
                "title":       sourceTask.Title,
                "description": sourceTask.Description,
                "completed":   sourceTask.Completed,
                "priority":    sourceTask.Priority,
                "due_date":    sourceTask.DueDate,
                "remind_at":   sourceTask.RemindAt,
                "category":    sourceTask.Category,
            }

            tx.Model(&Task{}).Where("id = ?", forward.TaskID).Updates(updates)
        }

        return nil
    })
}
```

采用"最后写入优先"策略，基于 `updated_at` 时间戳判断。

**重要：** 不使用 GORM 钩子，而是在更新任务时显式调用同步方法，这样可以：
- 避免无限循环
- 更容易控制同步逻辑
- 便于测试和调试
- 支持选择性同步（某些字段可能不需要同步）

---

## 4. API 接口设计

### 4.1 搜索可转发用户

```
GET /api/v1/users/search?keyword=xxx&limit=10
Authorization: Bearer {token}
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "users": [
      {
        "id": 2,
        "username": "user2",
        "email": "user2@example.com",
        "nickname": "用户2",
        "avatar": ""
      }
    ],
    "total": 1
  }
}
```

### 4.2 转发任务

```
POST /api/v1/tasks/{id}/forward
Authorization: Bearer {token}
Content-Type: application/json

{
  "target_user_ids": [2, 3, 4],
  "message": "请帮忙处理这个任务",
  "deadline": "2024-04-01T18:00:00Z"
}
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "forwards": [
      {
        "forward_id": 1,
        "forwarded_task_id": 10,
        "task_id": 1,
        "forwarded_by": {
          "id": 1,
          "username": "user1"
        },
        "forwarded_to": {
          "id": 2,
          "username": "user2"
        },
        "message": "请帮忙处理这个任务",
        "deadline": "2024-04-01T18:00:00Z",
        "created_at": "2024-03-24T10:00:00Z"
      },
      {
        "forward_id": 2,
        "forwarded_task_id": 11,
        "task_id": 1,
        "forwarded_by": {
          "id": 1,
          "username": "user1"
        },
        "forwarded_to": {
          "id": 3,
          "username": "user3"
        },
        "message": "请帮忙处理这个任务",
        "deadline": "2024-04-01T18:00:00Z",
        "created_at": "2024-03-24T10:00:00Z"
      }
    ],
    "total": 2
  }
}
```

### 4.3 撤回转发

```
DELETE /api/v1/forwards/{id}
Authorization: Bearer {token}
Content-Type: application/json

{
  "reason": "任务已取消"
}
```

### 4.4 获取转发记录

```
GET /api/v1/tasks/{id}/forwards?page=1&page_size=10
Authorization: Bearer {token}
```

### 4.5 获取收到的转发

```
GET /api/v1/forwards/received?page=1&page_size=10
Authorization: Bearer {token}
```

---

## 5. 数据流程

### 5.1 转发任务流程

```
1. 用户A搜索用户B → 调用搜索API → 返回用户列表
2. 用户A转发任务给B → 调用转发API
3. Service层处理：
   - 验证任务所有权
   - 验证目标用户存在且不是自己
   - 检查是否已转发给该用户
   - 复制任务给B（标记为转发任务）
   - 创建TaskForward关系记录
   - 返回转发信息
4. 接收方B任务列表显示转发任务
```

### 5.2 撤回转发流程

```
1. 用户A调用撤回API
2. Service层处理：
   - 验证转发者身份（只有转发者可以撤回）
   - 标记TaskForward为inactive
   - 记录撤回时间和原因
   - 删除或标记接收方的转发任务
3. 返回撤回成功
```

### 5.3 状态同步流程

```
1. 用户A更新原任务（任意字段）
2. Handler 调用 TaskService.UpdateTask
3. Service 层显式调用 ForwardService.SyncTaskStatus 同步到转发任务
4. 查找所有关联的活跃转发任务
5. 基于 updated_at 时间戳判断，同步更新到转发任务（除ID、ParentTaskID等元数据）
6. 转发任务更新时，同样显式调用同步方法更新原任务
```

**重要：** 同步在 Service 层显式调用，不使用 GORM 钩子。采用"最后写入优先"策略，基于 `updated_at` 时间戳判断哪个更新应该被应用。

### 5.4 撤回转发策略

撤回时采用软删除策略：

```
1. 用户A调用撤回API
2. Service层处理：
   - 验证转发者身份（只有转发者可以撤回）
   - 标记TaskForward为inactive
   - 记录撤回时间和原因
   - 软删除接收方的转发任务（Task模型已支持软删除，通过DeletedAt字段）
3. 返回撤回成功
```

选择软删除的原因：
- 保留转发历史记录
- 便于审计和统计
- 如果需要可以恢复

### 5.5 循环转发防护

在转发前检测是否会产生循环转发：

```
1. 检查目标用户是否在当前任务的转发链路中
2. 如果 A→B，B 试图转发回 A，则拒绝
3. 最大转发深度限制为 3 层（A→B→C→D，D 不能再转发）
```

### 5.6 过期检查流程

```
定时任务（每小时运行）：
1. 查询所有未过期且已过Deadline的转发
2. 标记TaskForward为过期
3. 标记关联的转发任务为过期状态
4. 注意：如果任务已经完成，则不标记为过期
```

**时区处理：**
- Deadline 使用 UTC 时间存储
- 前端提交时需要转换为 UTC
- 显示时根据用户时区转换

**定时任务实现：**
- 可使用 Go 的 cron 库（如 robfig/cron）
- 在 `cmd/server/main.go` 中启动
- 或部署到云环境时使用外部 cron（如 Kubernetes CronJob）

---

## 6. 权限模型

### 6.1 转发记录可见性

| 用户 | 可查看的内容 |
|-----|-------------|
| 转发者 | 所有自己发起的转发记录（包括撤回的） |
| 接收者 | 所有收到的转发记录（包括被撤回的，标记已撤回） |
| 其他用户 | 不可见 |

### 6.2 操作权限

| 操作 | 允许的用户 |
|-----|----------|
| 转发任务 | 任务所有者 |
| 撤回转发 | 转发者 |
| 更新转发任务 | 任务所有者（原任务或转发任务所有者） |
| 查看转发记录 | 转发者和接收者 |

### 6.3 权限强制执行

权限检查在 Service 层进行，示例代码：

```go
func (s *ForwardService) ForwardTask(ctx context.Context, taskID uint, req *TaskForwardRequest, userID uint) error {
    // 检查任务所有权
    task, err := s.taskRepo.GetByID(ctx, taskID)
    if err != nil {
        return err
    }
    if task.UserID != userID {
        return ErrNoPermission
    }

    // ... 其他验证和处理
}
```

## 7. 错误处理

### 7.1 常见错误场景

| 错误场景 | HTTP状态码 | 错误码 | 提示信息 |
|---------|-----------|-------|---------|
| 任务不存在 | 404 | TASK_NOT_FOUND | 任务不存在 |
| 无操作权限 | 403 | FORBIDDEN | 无操作权限 |
| 转发给自己 | 400 | CANNOT_FORWARD_SELF | 不能转发给自己 |
| 重复转发 | 400 | ALREADY_FORWARDED | 该任务已转发给此用户 |
| 用户不存在 | 404 | USER_NOT_FOUND | 用户不存在 |
| 转发已撤回 | 400 | FORWARD_REVOKED | 转发已撤回 |
| 撤回权限不足 | 403 | CANNOT_REVOKE | 只有转发者可以撤回 |
| 超过转发人数限制 | 400 | EXCEED_FORWARD_LIMIT | 最多转发给10个用户 |
| 截止时间无效 | 400 | INVALID_DEADLINE | 截止时间格式无效或已过期 |

### 7.2 错误响应格式

```json
{
  "code": 400,
  "message": "不能转发给自己"
}
```

---

## 8. 路由配置

在 `internal/api/router/router.go` 中添加：

```go
forwardHandler := handler.NewForwardHandler(forwardService)

// 用户搜索
userGroup.GET("/search", forwardHandler.SearchUsers)

// 转发相关
taskGroup.POST("/:id/forward", forwardHandler.ForwardTask)
taskGroup.GET("/:id/forwards", forwardHandler.GetTaskForwards)

// 转发管理
forwardGroup := r.Group("/api/v1/forwards")
forwardGroup.Use(middleware.Auth())
{
    forwardGroup.GET("/received", forwardHandler.GetReceivedForwards)
    forwardGroup.DELETE("/:id", forwardHandler.RevokeForward)
}
```

---

## 9. 数据库迁移

在 `pkg/database/database.go` 初始化时添加：

```go
// 自动迁移新模型
db.AutoMigrate(&model.TaskForward{})

// Task 模型的修改通过 GORM 自动处理
db.AutoMigrate(&model.Task{})
```

GORM 的 `AutoMigrate` 会自动添加新字段，无需手动执行 SQL。

### 新增索引

为了优化查询性能，在迁移后添加以下索引：

```go
// 转发关系索引
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_task_id ON task_forwards(task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_task_id ON task_forwards(forwarded_task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_by ON task_forwards(forwarded_by)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_to ON task_forwards(forwarded_to)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_is_active ON task_forwards(is_active)")

// 任务表的转发相关索引
db.Exec("CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_tasks_forwarded_by ON tasks(forwarded_by)")
```

---

## 10. 测试策略

### 10.1 单元测试

**Repository 层：**
- `TestCreateTaskForward` - 创建转发关系
- `TestGetTaskForwards` - 查询转发记录
- `TestGetReceivedForwards` - 查询收到的转发
- `TestRevokeForward` - 撤回转发
- `TestCheckExpiredForwards` - 过期检查

**Service 层：**
- `TestForwardTask_Success` - 转发成功
- `TestForwardTask_NoPermission` - 无权限转发
- `TestForwardTask_ToSelf` - 转发给自己
- `TestForwardTask_AlreadyForwarded` - 重复转发
- `TestForwardTask_ExceedLimit` - 超过人数限制
- `TestRevokeForward_Success` - 撤回成功
- `TestRevokeForward_NoPermission` - 撤回权限不足
- `TestSearchUsers` - 搜索用户
- `TestForwardTask_PreventCircularForward` - 防止循环转发（A→B→A）
- `TestSyncTaskStatus_ConcurrentUpdates` - 并发更新测试
- `TestRevokeForward_SoftDeleteTask` - 撤回时软删除任务
- `TestCheckExpiredForwards_AlreadyCompleted` - 已完成任务不标记过期

**Repository 层：**
- `TestCheckCircularForward` - 检测转发链路
- `TestGetForwardChain` - 获取转发链路

### 10.2 集成测试

- 端到端转发流程测试
- 多用户并发转发测试
- 状态同步一致性测试
- 过期自动标记测试
- 循环转发防护测试

---

## 11. 实施计划概要

1. **数据模型创建** - 添加 TaskForward 模型，修改 Task 模型
2. **Repository 层实现** - 转发数据的 CRUD 操作
3. **Service 层实现** - 转发、撤回、搜索、状态同步业务逻辑
4. **Handler 层实现** - API 接口处理器
5. **路由配置** - 注册新路由
6. **状态同步方法** - 实现显式同步方法（不使用 GORM 钩子）
7. **定时任务** - 过期检查（使用 robfig/cron 或外部 cron）
8. **单元测试** - Repository 和 Service 层测试
9. **集成测试** - 端到端测试

---

## 12. 后续扩展

- 转发历史记录查询
- 转发统计（转发次数、成功率等）
- 转发提醒（即将过期提醒）
- 批量转发操作
- 转发权限组（用户组转发）