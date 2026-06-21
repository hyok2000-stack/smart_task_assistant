package database

import (
	"fmt"
	"log"
	"os"
	"task_server/internal/config"
	"task_server/internal/model"

	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func InitDB(cfg *config.DatabaseConfig) error {
	var err error

	// SQLite 数据库路径：优先 DB_PATH 环境变量（便于放到非云同步目录，规避 OneDrive 等 IO 锁）
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "task_server.db"
	}

	// 检查是否配置了有效的 PostgreSQL 连接
	// 只有当 DB_HOST 和 DB_NAME 都不为空时才尝试 PostgreSQL
	hasValidPostgresConfig := false
	if cfg.Host != "" && cfg.DBName != "" {
		// 验证 host 是否有效（不是空字符串或仅包含空格）
		if len(cfg.Host) > 0 && cfg.Host != " " {
			hasValidPostgresConfig = true
		}
	}

	if hasValidPostgresConfig {
		dsn := fmt.Sprintf(
			"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
			cfg.Host,
			cfg.Port,
			cfg.User,
			cfg.Password,
			cfg.DBName,
			cfg.SSLMode,
		)

		log.Printf("Attempting to connect to PostgreSQL at %s:%s (database: %s)...",
			cfg.Host, cfg.Port, cfg.DBName)

		DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
		if err != nil {
			log.Printf("PostgreSQL connection failed: %v, falling back to SQLite", err)
			err = nil
			DB = nil
		} else {
			// 验证连接是否真的成功
			sqlDB, dbErr := DB.DB()
			if dbErr != nil {
				log.Printf("PostgreSQL connection verification failed: %v, falling back to SQLite", dbErr)
				err = nil
				DB = nil
			} else if sqlDB != nil {
				if pingErr := sqlDB.Ping(); pingErr != nil {
					log.Printf("PostgreSQL ping failed: %v, falling back to SQLite", pingErr)
					err = nil
					DB = nil
				} else {
					log.Println("PostgreSQL database connected successfully")
					// 连接成功，跳过 SQLite
					goto migrate
				}
			}
		}
	}

	// 使用 SQLite 作为默认数据库（路径在函数开头已按 DB_PATH 解析）
	log.Printf("Using SQLite database (%s)...", dbPath)
	DB, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		return fmt.Errorf("failed to connect to SQLite database: %w", err)
	}
	log.Println("SQLite database connected successfully")

migrate:
	// Auto migrate
	err = DB.AutoMigrate(
		&model.User{},
		&model.Task{},
		&model.Tag{},
		&model.Device{},
		&model.AISuggestion{},
		&model.AIChatMessage{},
		&model.TaskForward{},
		&model.Habit{},
		&model.HabitLog{},
		&model.SyncRecord{},
		&model.TaskProgress{},
	)
	if err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	log.Println("Database migration completed")

	// 初始化默认管理员账号
	if err := initAdminUser(); err != nil {
		log.Printf("Warning: Failed to initialize admin user: %v", err)
	}

	return nil
}

// initAdminUser 初始化默认管理员账号
func initAdminUser() error {
	var count int64
	DB.Model(&model.User{}).Where("role = ?", "admin").Count(&count)
	if count > 0 {
		return nil // 管理员已存在
	}

	// 加密密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	admin := &model.User{
		Username: "admin",
		Email:    "admin@taskserver.com",
		Password: string(hashedPassword),
		Nickname: "管理员",
		Role:     "admin",
		IsActive: true,
	}

	if err := DB.Create(admin).Error; err != nil {
		return fmt.Errorf("failed to create admin user: %w", err)
	}

	log.Println("Default admin user created (username: admin, password: admin123)")
	return nil
}

func GetDB() *gorm.DB {
	return DB
}
