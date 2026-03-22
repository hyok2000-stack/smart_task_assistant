package database

import (
	"fmt"
	"log"
	"task_server/internal/config"
	"task_server/internal/model"

	"github.com/glebarez/sqlite"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func InitDB(cfg *config.DatabaseConfig) error {
	var err error

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

	// 使用 SQLite 作为默认数据库
	log.Println("Using SQLite database (task_server.db)...")
	DB, err = gorm.Open(sqlite.Open("task_server.db"), &gorm.Config{})
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
	)
	if err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	log.Println("Database migration completed")

	return nil
}

func GetDB() *gorm.DB {
	return DB
}
