package service

import (
	"errors"
	"task_server/internal/model"
	"task_server/internal/repository"
)

type TagService struct {
	tagRepo *repository.TagRepository
}

func NewTagService(tagRepo *repository.TagRepository) *TagService {
	return &TagService{tagRepo: tagRepo}
}

func (s *TagService) List(userID uint) ([]model.Tag, error) {
	return s.tagRepo.FindByUserID(userID)
}

// Create creates a tag (legacy, kept for compatibility)
func (s *TagService) Create(userID uint, name, color string) (*model.Tag, error) {
	return s.CreateWithFields(userID, "", name, color, "", 0, false)
}

// CreateWithFields creates a tag with all fields
func (s *TagService) CreateWithFields(userID uint, localID, name, color, icon string, sortOrder int, isDefault bool) (*model.Tag, error) {
	if name == "" {
		return nil, errors.New("标签名称不能为空")
	}
	// Check duplicate
	existing, _ := s.tagRepo.FindByName(userID, name)
	if existing != nil {
		return nil, errors.New("标签名称已存在")
	}
	tag := &model.Tag{
		UserID:    userID,
		LocalID:   localID,
		Name:      name,
		Color:     color,
		Icon:      icon,
		SortOrder: sortOrder,
		IsDefault: isDefault,
	}
	if err := s.tagRepo.Create(tag); err != nil {
		return nil, err
	}
	return tag, nil
}

// Update updates a tag (legacy, kept for compatibility)
func (s *TagService) Update(id, userID uint, name, color string) (*model.Tag, error) {
	return s.UpdateWithFields(id, userID, "", name, color, "", nil, nil)
}

// UpdateWithFields updates a tag with all fields
func (s *TagService) UpdateWithFields(id, userID uint, localID, name, color, icon string, sortOrder *int, isDefault *bool) (*model.Tag, error) {
	tag, err := s.tagRepo.FindByID(id, userID)
	if err != nil {
		return nil, errors.New("标签不存在")
	}
	if localID != "" {
		tag.LocalID = localID
	}
	if name != "" {
		tag.Name = name
	}
	tag.Color = color
	if icon != "" {
		tag.Icon = icon
	}
	if sortOrder != nil {
		tag.SortOrder = *sortOrder
	}
	if isDefault != nil {
		tag.IsDefault = *isDefault
	}
	if err := s.tagRepo.Update(tag); err != nil {
		return nil, err
	}
	return tag, nil
}

func (s *TagService) Delete(id, userID uint) error {
	_, err := s.tagRepo.FindByID(id, userID)
	if err != nil {
		return errors.New("标签不存在")
	}
	return s.tagRepo.Delete(id, userID)
}
