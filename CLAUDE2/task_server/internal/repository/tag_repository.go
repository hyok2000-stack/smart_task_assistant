package repository

import (
	"task_server/internal/model"
	"gorm.io/gorm"
)

type TagRepository struct {
	db *gorm.DB
}

func NewTagRepository(db *gorm.DB) *TagRepository {
	return &TagRepository{db: db}
}

func (r *TagRepository) FindByUserID(userID uint) ([]model.Tag, error) {
	var tags []model.Tag
	err := r.db.Where("user_id = ?", userID).Order("name ASC").Find(&tags).Error
	return tags, err
}

func (r *TagRepository) FindByID(id uint, userID uint) (*model.Tag, error) {
	var tag model.Tag
	err := r.db.Where("id = ? AND user_id = ?", id, userID).First(&tag).Error
	return &tag, err
}

func (r *TagRepository) Create(tag *model.Tag) error {
	return r.db.Create(tag).Error
}

func (r *TagRepository) Update(tag *model.Tag) error {
	return r.db.Save(tag).Error
}

func (r *TagRepository) Delete(id uint, userID uint) error {
	return r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Tag{}).Error
}

func (r *TagRepository) FindByName(userID uint, name string) (*model.Tag, error) {
	var tag model.Tag
	err := r.db.Where("user_id = ? AND name = ?", userID, name).First(&tag).Error
	return &tag, err
}
