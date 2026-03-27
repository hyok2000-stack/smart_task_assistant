package config

import (
	"log"

	"github.com/spf13/viper"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	AI       AIConfig
	Weather  WeatherConfig
	Log      LogConfig
}

type ServerConfig struct {
	Port string
	Host string
	Mode string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

type RedisConfig struct {
	Host     string
	Port     string
	Password string
	DB       int
}

type JWTConfig struct {
	Secret          string
	ExpirationHours int
}

type AIConfig struct {
	APIKey  string
	BaseURL string
}

type WeatherConfig struct {
	APIKey string
}

type LogConfig struct {
	Level  string
	Output string
}

func LoadConfig() (*Config, error) {
	viper.SetConfigName(".env")
	viper.SetConfigType("env")
	viper.AddConfigPath("./configs")
	viper.AddConfigPath(".")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		log.Printf("Warning: Config file not found, using defaults: %v", err)
	}

	config := &Config{}

	// Server config
	config.Server.Host = viper.GetString("SERVER_HOST")
	if config.Server.Host == "" {
		config.Server.Host = "0.0.0.0"
	}
	config.Server.Port = viper.GetString("SERVER_PORT")
	if config.Server.Port == "" {
		config.Server.Port = "8080"
	}
	config.Server.Mode = viper.GetString("GIN_MODE")
	if config.Server.Mode == "" {
		config.Server.Mode = "debug"
	}

	// Database config
	config.Database.Host = viper.GetString("DB_HOST")
	config.Database.Port = viper.GetString("DB_PORT")
	config.Database.User = viper.GetString("DB_USER")
	config.Database.Password = viper.GetString("DB_PASSWORD")
	config.Database.DBName = viper.GetString("DB_NAME")
	config.Database.SSLMode = viper.GetString("DB_SSLMODE")

	// Redis config
	config.Redis.Host = viper.GetString("REDIS_HOST")
	config.Redis.Port = viper.GetString("REDIS_PORT")
	config.Redis.Password = viper.GetString("REDIS_PASSWORD")
	config.Redis.DB = viper.GetInt("REDIS_DB")

	// JWT config
	config.JWT.Secret = viper.GetString("JWT_SECRET")
	config.JWT.ExpirationHours = viper.GetInt("JWT_EXPIRATION_HOURS")
	if config.JWT.ExpirationHours == 0 {
		config.JWT.ExpirationHours = 24
	}

	// AI config
	config.AI.APIKey = viper.GetString("AI_API_KEY")
	config.AI.BaseURL = viper.GetString("AI_BASE_URL")
	if config.AI.BaseURL == "" {
		config.AI.BaseURL = "https://api.openai.com/v1"
	}

	// Weather config
	config.Weather.APIKey = viper.GetString("WEATHER_API_KEY")

	// Log config
	config.Log.Level = viper.GetString("LOG_LEVEL")
	if config.Log.Level == "" {
		config.Log.Level = "debug"
	}
	config.Log.Output = viper.GetString("LOG_OUTPUT")
	if config.Log.Output == "" {
		config.Log.Output = "stdout"
	}

	return config, nil
}
