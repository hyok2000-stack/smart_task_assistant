package cache

import (
	"context"
	"fmt"
	"log"
	"task_server/internal/config"
	"time"

	"github.com/redis/go-redis/v9"
)

var Client *redis.Client
var ctx = context.Background()

func InitRedis(cfg *config.RedisConfig) error {
	Client = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", cfg.Host, cfg.Port),
		Password: cfg.Password,
		DB:       cfg.DB,
	})

	// Test connection
	_, err := Client.Ping(ctx).Result()
	if err != nil {
		return fmt.Errorf("failed to connect to Redis: %w", err)
	}

	log.Println("Redis connected successfully")
	return nil
}

func GetClient() *redis.Client {
	return Client
}

// Set 设置缓存
func Set(key string, value interface{}, expiration time.Duration) error {
	return Client.Set(ctx, key, value, expiration).Err()
}

// Get 获取缓存
func Get(key string) (string, error) {
	return Client.Get(ctx, key).Result()
}

// Del 删除缓存
func Del(key string) error {
	return Client.Del(ctx, key).Err()
}

// Exists 检查 key 是否存在
func Exists(key string) (bool, error) {
	n, err := Client.Exists(ctx, key).Result()
	return n > 0, err
}

// SetJSON 设置 JSON 数据
func SetJSON(key string, value interface{}, expiration time.Duration) error {
	return Client.Set(ctx, key, value, expiration).Err()
}

// GetJSON 获取 JSON 数据
func GetJSON(key string, dest interface{}) error {
	return Client.Get(ctx, key).Scan(dest)
}
