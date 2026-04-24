package service

import (
	"errors"
	"time"

	"task_server/internal/model"
	"task_server/internal/repository"
)

var (
	// ErrInvalidTriggerType 无效的触发类型
	ErrInvalidTriggerType = errors.New("invalid trigger type")
	// ErrMissingInterval 缺少间隔时间
	ErrMissingInterval = errors.New("interval_minutes required for interval trigger")
	// ErrMissingFixedTime 缺少固定时间
	ErrMissingFixedTime = errors.New("fixed_time required for fixed trigger")
	// ErrInvalidTarget 无效的目标数量
	ErrInvalidTarget = errors.New("target_count must be positive")
	// ErrInvalidVoiceSpeed 无效的语音速度
	ErrInvalidVoiceSpeed = errors.New("voice_speed must be slow, normal, or fast")
	// ErrInvalidScheduleType 无效的调度类型
	ErrInvalidScheduleType = errors.New("schedule_type must be weekdays or daily")
)

// HabitService 习惯服务
type HabitService struct {
	repo repository.HabitRepository
}

// NewHabitService 创建习惯服务
func NewHabitService(repo repository.HabitRepository) *HabitService {
	return &HabitService{repo: repo}
}

// Create 创建习惯
func (s *HabitService) Create(userID uint, req *model.CreateHabitRequest) (*model.Habit, error) {
	// 验证输入
	if err := s.validateHabitRequest(req); err != nil {
		return nil, err
	}

	// 检查是否已存在
	if _, err := s.repo.FindByHabitID(req.HabitID, userID); err == nil {
		return nil, repository.ErrHabitAlreadyExists
	}

	// 创建习惯
	now := time.Now().UTC()
	habit := &model.Habit{
		UserID:           userID,
		HabitID:          req.HabitID,
		Title:            req.Title,
		TargetCount:      req.TargetCount,
		Unit:             req.Unit,
		TriggerType:      req.TriggerType,
		IntervalMinutes:  req.IntervalMinutes,
		FixedTime:        req.FixedTime,
		ScheduleType:     req.ScheduleType,
		IconCode:         req.IconCode,
		SortOrder:        req.SortOrder,
		IsEnabled:        req.IsEnabled,
		SoundEnabled:     req.SoundEnabled,
		VibrationEnabled: req.VibrationEnabled,
		VoiceEnabled:     req.VoiceEnabled,
		VoiceText:        req.VoiceText,
		VoiceSpeed:       req.VoiceSpeed,
		ReferenceTime:    req.ReferenceTime,
		AdvanceMinutes:   req.AdvanceMinutes,
		DeviceID:         req.DeviceID,
		SyncedAt:         now,
	}

	// 设置默认值
	if habit.TargetCount == 0 {
		habit.TargetCount = 1
	}
	if habit.Unit == "" {
		habit.Unit = "次"
	}
	if habit.TriggerType == "" {
		habit.TriggerType = "interval"
	}
	if habit.ScheduleType == "" {
		habit.ScheduleType = "weekdays"
	}
	if habit.VoiceSpeed == "" {
		habit.VoiceSpeed = "normal"
	}

	if err := s.repo.Create(habit); err != nil {
		return nil, err
	}

	return habit, nil
}

// GetByID 根据数据库 ID 获取习惯
func (s *HabitService) GetByID(id uint, userID uint) (*model.Habit, error) {
	return s.repo.FindByID(id, userID)
}

// GetByHabitID 根据 HabitID 获取习惯
func (s *HabitService) GetByHabitID(habitID string, userID uint) (*model.Habit, error) {
	return s.repo.FindByHabitID(habitID, userID)
}

// List 列出用户的习惯
func (s *HabitService) List(userID uint, req *model.ListHabitsRequest) (*model.ListHabitsResponse, error) {
	habits, err := s.repo.FindByUserID(userID)
	if err != nil {
		return nil, err
	}

	// 过滤
	var filtered []*model.Habit
	for _, habit := range habits {
		if req.IsEnabled != nil && habit.IsEnabled != *req.IsEnabled {
			continue
		}
		filtered = append(filtered, habit)
	}

	// 分页
	total := int64(len(filtered))
	start := (req.Page - 1) * req.PageSize
	end := start + req.PageSize

	if start > len(filtered) {
		start = len(filtered)
	}
	if end > len(filtered) {
		end = len(filtered)
	}

	paged := filtered[start:end]
	totalPages := int(total) / req.PageSize
	if int(total)%req.PageSize != 0 {
		totalPages++
	}

	// 转换为响应格式
	responses := make([]model.HabitResponse, len(paged))
	for i, habit := range paged {
		responses[i] = model.HabitResponse{Habit: *habit}
	}

	return &model.ListHabitsResponse{
		Habits:     responses,
		Total:      total,
		Page:       req.Page,
		PageSize:   req.PageSize,
		TotalPages: totalPages,
	}, nil
}

// Update 更新习惯（根据数据库 ID）
func (s *HabitService) Update(id uint, userID uint, req *model.UpdateHabitRequest) (*model.Habit, error) {
	// 获取现有习惯
	habit, err := s.repo.FindByID(id, userID)
	if err != nil {
		return nil, err
	}

	return s.updateHabit(habit, req)
}

// Delete 删除习惯
func (s *HabitService) Delete(id uint, userID uint) error {
	return s.repo.Delete(id, userID)
}

// DeleteByHabitID 根据 HabitID 删除习惯
func (s *HabitService) DeleteByHabitID(habitID string, userID uint) error {
	return s.repo.DeleteByHabitID(habitID, userID)
}

// UpdateByHabitID 根据 HabitID 更新习惯
func (s *HabitService) UpdateByHabitID(habitID string, userID uint, req *model.UpdateHabitRequest) (*model.Habit, error) {
	// 获取现有习惯
	habit, err := s.repo.FindByHabitID(habitID, userID)
	if err != nil {
		return nil, err
	}

	// 应用更新（复用 Update 的逻辑）
	return s.updateHabit(habit, req)
}

// ToggleEnabled 切换启用状态
func (s *HabitService) ToggleEnabled(habitID string, userID uint) error {
	return s.repo.ToggleEnabled(habitID, userID)
}

// SyncFromDevice 从设备同步习惯
func (s *HabitService) SyncFromDevice(userID uint, deviceID string, habits []*model.Habit) error {
	if len(habits) == 0 {
		return nil
	}

	// 设置用户 ID 和同步时间
	now := time.Now().UTC()
	for _, habit := range habits {
		habit.UserID = userID
		habit.DeviceID = deviceID
		habit.SyncedAt = now
	}

	return s.repo.BulkUpsert(habits)
}

// updateHabit 应用更新请求到习惯对象
func (s *HabitService) updateHabit(habit *model.Habit, req *model.UpdateHabitRequest) (*model.Habit, error) {
	// 应用更新
	if req.Title != nil {
		habit.Title = *req.Title
	}
	if req.TargetCount != nil {
		if *req.TargetCount < 0 {
			return nil, ErrInvalidTarget
		}
		habit.TargetCount = *req.TargetCount
	}
	if req.Unit != nil {
		habit.Unit = *req.Unit
	}
	if req.TriggerType != nil {
		habit.TriggerType = *req.TriggerType
	}
	if req.IntervalMinutes != nil {
		habit.IntervalMinutes = req.IntervalMinutes
	}
	if req.FixedTime != nil {
		habit.FixedTime = *req.FixedTime
	}
	if req.ScheduleType != nil {
		if *req.ScheduleType != "weekdays" && *req.ScheduleType != "daily" {
			return nil, ErrInvalidScheduleType
		}
		habit.ScheduleType = *req.ScheduleType
	}
	if req.IconCode != nil {
		habit.IconCode = *req.IconCode
	}
	if req.SortOrder != nil {
		habit.SortOrder = *req.SortOrder
	}
	if req.IsEnabled != nil {
		habit.IsEnabled = *req.IsEnabled
	}
	if req.SoundEnabled != nil {
		habit.SoundEnabled = *req.SoundEnabled
	}
	if req.VibrationEnabled != nil {
		habit.VibrationEnabled = *req.VibrationEnabled
	}
	if req.VoiceEnabled != nil {
		habit.VoiceEnabled = *req.VoiceEnabled
	}
	if req.VoiceText != nil {
		habit.VoiceText = req.VoiceText
	}
	if req.VoiceSpeed != nil {
		if *req.VoiceSpeed != "slow" && *req.VoiceSpeed != "normal" && *req.VoiceSpeed != "fast" {
			return nil, ErrInvalidVoiceSpeed
		}
		habit.VoiceSpeed = *req.VoiceSpeed
	}
	if req.ReferenceTime != nil {
		habit.ReferenceTime = req.ReferenceTime
	}
	if req.AdvanceMinutes != nil {
		habit.AdvanceMinutes = req.AdvanceMinutes
	}

	// 验证触发类型配置
	if err := s.validateTriggerConfig(habit); err != nil {
		return nil, err
	}

	habit.UpdatedAt = time.Now().UTC()
	habit.SyncedAt = time.Now().UTC()

	if err := s.repo.Update(habit); err != nil {
		return nil, err
	}

	return habit, nil
}

// validateHabitRequest 验证习惯请求
func (s *HabitService) validateHabitRequest(req *model.CreateHabitRequest) error {
	if req.TargetCount < 0 {
		return ErrInvalidTarget
	}

	if req.TriggerType != "interval" && req.TriggerType != "fixed" {
		return ErrInvalidTriggerType
	}

	if req.TriggerType == "interval" && req.IntervalMinutes == nil {
		return ErrMissingInterval
	}

	if req.TriggerType == "fixed" && req.FixedTime == "" {
		return ErrMissingFixedTime
	}

	if req.ScheduleType != "weekdays" && req.ScheduleType != "daily" && req.ScheduleType != "" {
		return ErrInvalidScheduleType
	}

	if req.VoiceSpeed != "" && req.VoiceSpeed != "slow" && req.VoiceSpeed != "normal" && req.VoiceSpeed != "fast" {
		return ErrInvalidVoiceSpeed
	}

	return nil
}

// validateTriggerConfig 验证触发配置
func (s *HabitService) validateTriggerConfig(habit *model.Habit) error {
	if habit.TriggerType != "interval" && habit.TriggerType != "fixed" {
		return ErrInvalidTriggerType
	}

	if habit.TriggerType == "interval" && habit.IntervalMinutes == nil {
		return ErrMissingInterval
	}

	if habit.TriggerType == "fixed" && habit.FixedTime == "" {
		return ErrMissingFixedTime
	}

	if habit.VoiceSpeed != "slow" && habit.VoiceSpeed != "normal" && habit.VoiceSpeed != "fast" {
		return ErrInvalidVoiceSpeed
	}

	if habit.ScheduleType != "weekdays" && habit.ScheduleType != "daily" {
		return ErrInvalidScheduleType
	}

	return nil
}
