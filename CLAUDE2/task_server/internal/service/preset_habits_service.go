package service

import (
	"time"

	"task_server/internal/model"
	"task_server/internal/repository"
)

// PresetHabitsService 预设习惯服务
type PresetHabitsService struct {
	habitRepo repository.HabitRepository
}

// NewPresetHabitsService 创建预设习惯服务
func NewPresetHabitsService(habitRepo repository.HabitRepository) *PresetHabitsService {
	return &PresetHabitsService{
		habitRepo: habitRepo,
	}
}

// GetDefaultHabits 获取默认习惯列表
func (s *PresetHabitsService) GetDefaultHabits() []*model.Habit {
	now := time.Now().UTC()

	return []*model.Habit{
		// 喝水 - 需要记录
		{
			HabitID:          "habit_water",
			Title:            "喝水",
			TargetCount:      8,
			Unit:             "杯",
			TriggerType:      "interval",
			IntervalMinutes:  intPtr(60),
			ScheduleType:     "weekdays",
			IconCode:         0x1F4A7, // 💧
			SoundEnabled:     true,
			VibrationEnabled: true,
			VoiceEnabled:     true,
			VoiceText:        strPtr("该休息一下了，喝水"),
			VoiceSpeed:       "normal",
			IsEnabled:        true,
			SortOrder:        0,
			SyncedAt:         now,
		},
		// 起身活动 - 需要记录
		{
			HabitID:          "habit_stretch",
			Title:            "起身活动",
			TargetCount:      5,
			Unit:             "次",
			TriggerType:      "interval",
			IntervalMinutes:  intPtr(90),
			ScheduleType:     "weekdays",
			IconCode:         0x1F6B6, // 🚶
			SoundEnabled:     true,
			VibrationEnabled: true,
			VoiceEnabled:     true,
			VoiceText:        strPtr("时间到了，起身活动一下"),
			VoiceSpeed:       "normal",
			IsEnabled:        true,
			SortOrder:        1,
			SyncedAt:         now,
		},
		// 上班打卡 - 不需要记录
		{
			HabitID:          "habit_clock_in",
			Title:            "上班打卡",
			TargetCount:      0,
			Unit:             "次",
			TriggerType:      "fixed",
			FixedTime:        "08:50",
			ReferenceTime:    strPtr("09:00"),
			AdvanceMinutes:   intPtr(10),
			ScheduleType:     "weekdays",
			IconCode:         0x1F4E5, // 📥
			SoundEnabled:     true,
			VibrationEnabled: true,
			VoiceEnabled:     true,
			VoiceText:        strPtr("该打卡了"),
			VoiceSpeed:       "normal",
			IsEnabled:        true,
			SortOrder:        2,
			SyncedAt:         now,
		},
		// 下班打卡 - 不需要记录
		{
			HabitID:          "habit_clock_out",
			Title:            "下班打卡",
			TargetCount:      0,
			Unit:             "次",
			TriggerType:      "fixed",
			FixedTime:        "18:00",
			ReferenceTime:    strPtr("18:00"),
			AdvanceMinutes:   intPtr(0),
			ScheduleType:     "weekdays",
			IconCode:         0x1F4E4, // 📤
			SoundEnabled:     true,
			VibrationEnabled: true,
			VoiceEnabled:     true,
			VoiceText:        strPtr("下班时间到了"),
			VoiceSpeed:       "normal",
			IsEnabled:        true,
			SortOrder:        3,
			SyncedAt:         now,
		},
	}
}

// InitializeDefaults 为用户初始化默认习惯
func (s *PresetHabitsService) InitializeDefaults(userID uint, deviceID string) error {
	// 检查用户是否已有习惯
	count, err := s.habitRepo.CountByUserID(userID)
	if err != nil {
		return err
	}
	if count > 0 {
		return nil // 用户已有习惯，不重复初始化
	}

	// 获取默认习惯
	defaultHabits := s.GetDefaultHabits()

	// 设置用户 ID 和设备 ID
	for _, habit := range defaultHabits {
		habit.UserID = userID
		habit.DeviceID = deviceID
	}

	// 批量插入
	return s.habitRepo.BulkUpsert(defaultHabits)
}

// HasDefaultsInitialized 检查用户是否已初始化默认习惯
func (s *PresetHabitsService) HasDefaultsInitialized(userID uint) (bool, error) {
	count, err := s.habitRepo.CountByUserID(userID)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// ResetToDefaults 重置为默认习惯
func (s *PresetHabitsService) ResetToDefaults(userID uint, deviceID string) error {
	// 删除用户所有习惯
	habits, err := s.habitRepo.FindByUserID(userID)
	if err != nil {
		return err
	}

	for _, habit := range habits {
		if err := s.habitRepo.Delete(habit.ID, userID); err != nil {
			return err
		}
	}

	// 初始化默认习惯
	return s.InitializeDefaults(userID, deviceID)
}

// GetDefaultHabitVoiceTexts 获取默认习惯的语音内容
func (s *PresetHabitsService) GetDefaultHabitVoiceTexts(isZh bool) map[string]string {
	if isZh {
		return map[string]string{
			"habit_water":     "该休息一下了，喝水",
			"habit_stretch":   "时间到了，起身活动一下",
			"habit_clock_in":  "该打卡了",
			"habit_clock_out": "下班时间到了",
		}
	}
	return map[string]string{
		"habit_water":     "Time for a break, drink water",
		"habit_stretch":   "Time to stretch",
		"habit_clock_in":  "Time to clock in",
		"habit_clock_out": "Time to clock out",
	}
}

// Helper functions
func intPtr(i int) *int {
	return &i
}

func strPtr(s string) *string {
	return &s
}
