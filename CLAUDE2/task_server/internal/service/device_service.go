package service

import (
	"errors"
	"task_server/internal/model"
	"task_server/internal/repository"
)

type DeviceService struct {
	deviceRepo *repository.DeviceRepository
}

func NewDeviceService(deviceRepo *repository.DeviceRepository) *DeviceService {
	return &DeviceService{deviceRepo: deviceRepo}
}

func (s *DeviceService) List(userID uint) ([]model.Device, error) {
	return s.deviceRepo.FindByUserID(userID)
}

type RegisterDeviceRequest struct {
	DeviceID  string `json:"device_id" binding:"required"`
	Name      string `json:"name"`
	Platform  string `json:"platform"`
	PushToken string `json:"push_token"`
}

func (s *DeviceService) Register(userID uint, req *RegisterDeviceRequest) (*model.Device, error) {
	device := &model.Device{
		UserID:   userID,
		DeviceID: req.DeviceID,
		Name:     req.Name,
		Platform: req.Platform,
	}
	if err := s.deviceRepo.Register(device); err != nil {
		return nil, err
	}
	return device, nil
}

func (s *DeviceService) Delete(id, userID uint) error {
	_, err := s.deviceRepo.FindByID(id, userID)
	if err != nil {
		return errors.New("设备不存在")
	}
	return s.deviceRepo.Delete(id, userID)
}

func (s *DeviceService) UpdatePushToken(id, userID uint, pushToken string) error {
	_, err := s.deviceRepo.FindByID(id, userID)
	if err != nil {
		return errors.New("设备不存在")
	}
	return s.deviceRepo.UpdatePushToken(id, pushToken)
}
