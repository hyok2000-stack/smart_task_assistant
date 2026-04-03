package service

import (
	"time"

	"task_server/internal/model"
	"task_server/internal/repository"
)

// HabitLogService 习惯日志服务
type HabitLogService struct {
	repo      repository.HabitLogRepository
	habitRepo repository.HabitRepository
}

// NewHabitLogService 创建习惯日志服务
func NewHabitLogService(repo repository.HabitLogRepository, habitRepo repository.HabitRepository) *HabitLogService {
	return &HabitLogService{
		repo:      repo,
		habitRepo: habitRepo,
	}
}

// LogCompletion 记录完成
func (s *HabitLogService) LogCompletion(userID uint, habitID string, count int, status int) (*model.HabitLog, error) {
	// 验证习惯存在且属于用户
	if _, err := s.habitRepo.FindByHabitID(habitID, userID); err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	log := &model.HabitLog{
		UserID:      userID,
		HabitID:     habitID,
		Count:       count,
		Status:      status,
		CompletedAt: now,
	}

	if err := s.repo.Create(log); err != nil {
		return nil, err
	}

	return log, nil
}

// LogCompletionWithDeviceID 记录完成（带设备 ID）
func (s *HabitLogService) LogCompletionWithDeviceID(userID uint, habitID string, count int, status int, deviceID string) (*model.HabitLog, error) {
	// 验证习惯存在且属于用户
	if _, err := s.habitRepo.FindByHabitID(habitID, userID); err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	log := &model.HabitLog{
		UserID:      userID,
		HabitID:     habitID,
		Count:       count,
		Status:      status,
		CompletedAt: now,
		DeviceID:    deviceID,
	}

	if err := s.repo.Create(log); err != nil {
		return nil, err
	}

	return log, nil
}

// List 列出日志
func (s *HabitLogService) List(habitID string, userID uint, req *model.ListHabitLogsRequest) (*model.ListHabitLogsResponse, error) {
	// 验证习惯存在且属于用户
	if _, err := s.habitRepo.FindByHabitID(habitID, userID); err != nil {
		return nil, err
	}

	logs, total, err := s.repo.FindByHabitID(habitID, userID, req.Page, req.PageSize)
	if err != nil {
		return nil, err
	}

	// 转换为响应格式
	responses := make([]model.HabitLogResponse, len(logs))
	for i, log := range logs {
		responses[i] = model.HabitLogResponse{HabitLog: *log}
	}

	totalPages := int(total) / req.PageSize
	if int(total)%req.PageSize != 0 {
		totalPages++
	}

	return &model.ListHabitLogsResponse{
		Logs:       responses,
		Total:      total,
		Page:       req.Page,
		PageSize:   req.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetStats 获取统计信息
func (s *HabitLogService) GetStats(habitID string, userID uint) (*model.HabitStats, error) {
	// 获取习惯以获取目标数量
	habit, err := s.habitRepo.FindByHabitID(habitID, userID)
	if err != nil {
		return nil, err
	}

	// 获取今日完成数量
	todayProgress, err := s.repo.GetTodayCount(habitID, userID)
	if err != nil {
		return nil, err
	}

	// 计算进度百分比
	percentage := 0
	if habit.TargetCount > 0 {
		percentage = (todayProgress * 100) / habit.TargetCount
		if percentage > 100 {
			percentage = 100
		}
	}

	// 获取连续天数
	streakDays, err := s.CalculateStreak(habitID, userID)
	if err != nil {
		streakDays = 0
	}

	// 获取最后完成时间
	lastCompleted, _ := s.repo.GetLastCompletedTime(habitID, userID)

	return &model.HabitStats{
		TodayProgress: todayProgress,
		TargetCount:   habit.TargetCount,
		Percentage:    percentage,
		StreakDays:    streakDays,
		LastCompleted: lastCompleted,
	}, nil
}

// CalculateStreak 计算连续天数
func (s *HabitLogService) CalculateStreak(habitID string, userID uint) (int, error) {
	// 获取最近 365 天的完成日期
	dates, err := s.repo.GetUniqueCompletionDates(habitID, userID, 365)
	if err != nil {
		return 0, err
	}

	if len(dates) == 0 {
		return 0, nil
	}

	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

	streak := 0
	checkDate := today

	// 检查今天是否有完成记录
	hasToday := false
	for _, date := range dates {
		if date.Equal(today) {
			hasToday = true
			break
		}
	}

	if !hasToday {
		// 如果今天没有完成记录，检查昨天是否有
		yesterday := today.Add(-24 * time.Hour)
		hasYesterday := false
		for _, date := range dates {
			if date.Equal(yesterday) {
				hasYesterday = true
				checkDate = yesterday
				break
			}
		}
		if !hasYesterday {
			// 今天和昨天都没有，连续天数中断
			return 0, nil
		}
	}

	// 向前遍历，计算连续天数
	for {
		found := false
		for _, date := range dates {
			if date.Equal(checkDate) {
				streak++
				checkDate = checkDate.Add(-24 * time.Hour)
				found = true
				break
			}
		}
		if !found {
			break
		}
	}

	return streak, nil
}

// GetHistory 获取历史记录
func (s *HabitLogService) GetHistory(habitID string, userID uint, days int) (*model.HabitHistoryResponse, error) {
	// 验证习惯存在且属于用户
	habit, err := s.habitRepo.FindByHabitID(habitID, userID)
	if err != nil {
		return nil, err
	}

	// 获取目标数量
	targetCount := habit.TargetCount
	if targetCount <= 0 {
		targetCount = 1
	}

	now := time.Now().UTC()
	startDate := now.AddDate(0, 0, -days)
	startOfDay := time.Date(startDate.Year(), startDate.Month(), startDate.Day(), 0, 0, 0, 0, time.UTC)
	endDate := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, time.UTC)

	// 获取日期范围内的统计数据
	stats, err := s.repo.GetDailyStatsForDateRange(habitID, userID, startOfDay, endDate)
	if err != nil {
		return nil, err
	}

	// 转换为历史记录格式
	history := make([]model.HabitHistoryItem, len(stats))
	for i, stat := range stats {
		dateStr := stat["date"].(time.Time).Format("2006-01-02")
		count := int(stat["count"].(int64))
		status := stat["status"].(int64)

		// 确定状态
		var statusStr string
		if count >= targetCount {
			statusStr = "completed"
		} else if count > 0 {
			statusStr = "partial"
		} else if status == 1 {
			statusStr = "skipped"
		} else {
			statusStr = "none"
		}

		history[i] = model.HabitHistoryItem{
			Date:   dateStr,
			Count:  count,
			Status: statusStr,
		}
	}

	return &model.HabitHistoryResponse{
		History: history,
	}, nil
}

// GetTodayProgress 获取今日进度
func (s *HabitLogService) GetTodayProgress(habitID string, userID uint) (int, error) {
	return s.repo.GetTodayCount(habitID, userID)
}

// GetProgressPercentage 获取进度百分比
func (s *HabitLogService) GetProgressPercentage(habitID string, userID uint, targetCount int) (int, error) {
	if targetCount <= 0 {
		return 0, nil
	}

	todayCount, err := s.repo.GetTodayCount(habitID, userID)
	if err != nil {
		return 0, err
	}

	percentage := (todayCount * 100) / targetCount
	if percentage > 100 {
		return 100, nil
	}
	return percentage, nil
}

// GetTodayStatsForAll 获取用户所有习惯的今日统计
func (s *HabitLogService) GetTodayStatsForAll(userID uint) (map[string]*model.HabitStats, error) {
	// 获取用户的所有习惯
	habits, err := s.habitRepo.FindByUserID(userID)
	if err != nil {
		return nil, err
	}

	stats := make(map[string]*model.HabitStats)

	for _, habit := range habits {
		todayProgress, _ := s.repo.GetTodayCount(habit.HabitID, userID)

		percentage := 0
		if habit.TargetCount > 0 {
			percentage = (todayProgress * 100) / habit.TargetCount
			if percentage > 100 {
				percentage = 100
			}
		}

		streakDays, _ := s.CalculateStreak(habit.HabitID, userID)
		lastCompleted, _ := s.repo.GetLastCompletedTime(habit.HabitID, userID)

		stats[habit.HabitID] = &model.HabitStats{
			TodayProgress: todayProgress,
			TargetCount:   habit.TargetCount,
			Percentage:    percentage,
			StreakDays:    streakDays,
			LastCompleted: lastCompleted,
		}
	}

	return stats, nil
}
