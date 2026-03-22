package service

import (
	"errors"
	"task_server/internal/api/middleware"
	"task_server/internal/model"
	"task_server/internal/repository"

	"golang.org/x/crypto/bcrypt"
)

type UserService struct {
	userRepo *repository.UserRepository
}

func NewUserService(userRepo *repository.UserRepository) *UserService {
	return &UserService{userRepo: userRepo}
}

// Register 用户注册
func (s *UserService) Register(req *model.RegisterRequest) (*model.User, error) {
	// 检查用户名是否已存在
	_, err := s.userRepo.FindByUsername(req.Username)
	if err == nil {
		return nil, errors.New("username already exists")
	}

	// 检查邮箱是否已存在
	_, err = s.userRepo.FindByEmail(req.Email)
	if err == nil {
		return nil, errors.New("email already exists")
	}

	// 加密密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &model.User{
		Username: req.Username,
		Email:    req.Email,
		Password: string(hashedPassword),
		Nickname: req.Nickname,
		IsActive: true,
	}

	if req.Nickname == "" {
		user.Nickname = req.Username
	}

	err = s.userRepo.Create(user)
	if err != nil {
		return nil, err
	}

	// 清除密码字段
	user.Password = ""
	return user, nil
}

// Login 用户登录
func (s *UserService) Login(req *model.LoginRequest) (*model.LoginResponse, error) {
	// 查找用户
	user, err := s.userRepo.FindByUsername(req.Username)
	if err != nil {
		return nil, errors.New("invalid username or password")
	}

	// 验证密码
	err = bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password))
	if err != nil {
		return nil, errors.New("invalid username or password")
	}

	// 检查用户是否激活
	if !user.IsActive {
		return nil, errors.New("user account is inactive")
	}

	// 生成 token
	token, err := middleware.GenerateToken(user.ID)
	if err != nil {
		return nil, err
	}

	// 生成 refresh token (简化版，实际应该使用更安全的机制)
	refreshToken, err := middleware.GenerateToken(user.ID)
	if err != nil {
		return nil, err
	}

	// 清除密码字段
	user.Password = ""

	return &model.LoginResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         *user,
	}, nil
}

// GetByID 根据 ID 获取用户
func (s *UserService) GetByID(id uint) (*model.User, error) {
	user, err := s.userRepo.FindByID(id)
	if err != nil {
		return nil, err
	}
	user.Password = ""
	return user, nil
}

// Update 更新用户信息
func (s *UserService) Update(user *model.User) error {
	return s.userRepo.Update(user)
}