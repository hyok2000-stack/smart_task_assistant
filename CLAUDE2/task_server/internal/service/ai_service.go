package service

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"task_server/internal/config"
	"time"
)

type AIService struct {
	cfg *config.AIConfig
	client *http.Client
}

func NewAIService(cfg *config.AIConfig) *AIService {
	return &AIService{
		cfg: cfg,
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

type ChatRequest struct {
	Messages []ChatMessage `json:"messages"`
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatResponse struct {
	Reply   string `json:"reply"`
	Model   string `json:"model,omitempty"`
}

func (s *AIService) Chat(messages []ChatMessage) (*ChatResponse, error) {
	if s.cfg == nil || s.cfg.APIKey == "" || s.cfg.BaseURL == "" {
		return &ChatResponse{
			Reply: "AI 服务未配置，请在设置中配置 AI API 密钥和地址。",
		}, nil
	}

	// Build request to external AI provider
	reqBody := map[string]interface{}{
		"model":    "gpt-3.5-turbo",
		"messages": messages,
	}
	jsonBody, _ := json.Marshal(reqBody)

	req, err := http.NewRequest("POST", s.cfg.BaseURL+"/chat/completions", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.cfg.APIKey)

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return &ChatResponse{Reply: string(body)}, nil
	}

	// Extract reply from standard OpenAI format
	if choices, ok := result["choices"].([]interface{}); ok && len(choices) > 0 {
		if choice, ok := choices[0].(map[string]interface{}); ok {
			if msg, ok := choice["message"].(map[string]interface{}); ok {
				if content, ok := msg["content"].(string); ok {
					return &ChatResponse{Reply: content}, nil
				}
			}
		}
	}

	return &ChatResponse{Reply: "AI 服务返回格式异常"}, nil
}
