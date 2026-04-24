package repository

import (
	"task_server/internal/model"
	"time"
	"gorm.io/gorm"
)

type DeviceRepository struct {
	db *gorm.DB
}

func NewDeviceRepository(db *gorm.DB) *DeviceRepository {
	return &DeviceRepository{db: db}
}

func (r *DeviceRepository) FindByUserID(userID uint) ([]model.Device, error) {
	var devices []model.Device
	err := r.db.Where("user_id = ?", userID).Order("last_sync DESC").Find(&devices).Error
	return devices, err
}

func (r *DeviceRepository) FindByID(id uint, userID uint) (*model.Device, error) {
	var device model.Device
	err := r.db.Where("id = ? AND user_id = ?", id, userID).First(&device).Error
	return &device, err
}

func (r *DeviceRepository) FindByDeviceID(deviceID string, userID uint) (*model.Device, error) {
	var device model.Device
	err := r.db.Where("device_id = ? AND user_id = ?", deviceID, userID).First(&device).Error
	return &device, err
}

func (r *DeviceRepository) Register(device *model.Device) error {
	var existing model.Device
	result := r.db.Where("device_id = ? AND user_id = ?", device.DeviceID, device.UserID).First(&existing)
	if result.Error != nil && result.Error == gorm.ErrRecordNotFound {
		return r.db.Create(device).Error
	}
	return r.db.Model(&existing).Updates(map[string]interface{}{
		"name":      device.Name,
		"platform":  device.Platform,
		"last_sync": time.Now(),
	}).Error
}

func (r *DeviceRepository) Delete(id uint, userID uint) error {
	return r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Device{}).Error
}

func (r *DeviceRepository) UpdatePushToken(id uint, pushToken string) error {
	return r.db.Model(&model.Device{}).Where("id = ?", id).Update("push_token", pushToken).Error
}
