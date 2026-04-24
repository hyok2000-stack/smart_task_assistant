package service

import (
	"testing"

	"task_server/internal/api/middleware"
	"task_server/internal/config"
	"task_server/internal/model"
	"task_server/internal/repository"

	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

func setupUserTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dialector := sqlite.Open(":memory:")
	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(1)
	err = db.AutoMigrate(&model.User{})
	if err != nil {
		t.Fatalf("Failed to migrate test database: %v", err)
	}
	return db
}

func newUserService(t *testing.T) (*UserService, *gorm.DB) {
	t.Helper()
	db := setupUserTestDB(t)
	userRepo := repository.NewUserRepository(db)
	svc := NewUserService(userRepo)

	// Initialize JWT for token generation
	middleware.InitJWTAuth(&config.JWTConfig{Secret: "test-secret-key"})

	return svc, db
}

// ========== Register Tests ==========

func TestUserService_Register(t *testing.T) {
	svc, _ := newUserService(t)

	t.Run("success", func(t *testing.T) {
		req := &model.RegisterRequest{
			Username: "newuser",
			Email:    "new@test.com",
			Password: "password123",
			Nickname: "New User",
		}
		user, err := svc.Register(req)
		if err != nil {
			t.Fatalf("Register() error = %v", err)
		}
		if user.ID == 0 {
			t.Error("Register() user.ID should not be zero")
		}
		if user.Username != "newuser" {
			t.Errorf("Register() username = %v, want 'newuser'", user.Username)
		}
		if user.Password != "" {
			t.Error("Register() password should be cleared in response")
		}
		if user.IsActive != true {
			t.Error("Register() user should be active by default")
		}
	})

	t.Run("nickname defaults to username", func(t *testing.T) {
		req := &model.RegisterRequest{
			Username: "nonickname",
			Email:    "nonick@test.com",
			Password: "password123",
		}
		user, _ := svc.Register(req)
		if user.Nickname != "nonickname" {
			t.Errorf("Register() nickname = %v, want 'nonickname'", user.Nickname)
		}
	})

	t.Run("duplicate username", func(t *testing.T) {
		req := &model.RegisterRequest{
			Username: "newuser", // already created above
			Email:    "another@test.com",
			Password: "password123",
		}
		_, err := svc.Register(req)
		if err == nil {
			t.Fatal("Register() should fail with duplicate username")
		}
		if err.Error() != "username already exists" {
			t.Errorf("Register() error = %v, want 'username already exists'", err)
		}
	})

	t.Run("duplicate email", func(t *testing.T) {
		req := &model.RegisterRequest{
			Username: "uniqueuser",
			Email:    "new@test.com", // already used
			Password: "password123",
		}
		_, err := svc.Register(req)
		if err == nil {
			t.Fatal("Register() should fail with duplicate email")
		}
		if err.Error() != "email already exists" {
			t.Errorf("Register() error = %v, want 'email already exists'", err)
		}
	})
}

// ========== Login Tests ==========

func TestUserService_Login(t *testing.T) {
	svc, db := newUserService(t)

	// Create a user with known password
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)
	user := &model.User{
		Username: "loginuser",
		Email:    "login@test.com",
		Password: string(hashedPassword),
		Nickname: "Login User",
		IsActive: true,
		Role:     "user",
	}
	db.Create(user)

	t.Run("success", func(t *testing.T) {
		req := &model.LoginRequest{
			Username: "loginuser",
			Password: "password123",
		}
		resp, err := svc.Login(req)
		if err != nil {
			t.Fatalf("Login() error = %v", err)
		}
		if resp.Token == "" {
			t.Error("Login() token should not be empty")
		}
		if resp.RefreshToken == "" {
			t.Error("Login() refresh_token should not be empty")
		}
		if resp.User.Username != "loginuser" {
			t.Errorf("Login() username = %v, want 'loginuser'", resp.User.Username)
		}
		if resp.User.Password != "" {
			t.Error("Login() user password should be cleared")
		}
	})

	t.Run("wrong username", func(t *testing.T) {
		req := &model.LoginRequest{
			Username: "nonexistent",
			Password: "password123",
		}
		_, err := svc.Login(req)
		if err == nil {
			t.Fatal("Login() should fail with wrong username")
		}
		if err.Error() != "invalid username or password" {
			t.Errorf("Login() error = %v, want 'invalid username or password'", err)
		}
	})

	t.Run("wrong password", func(t *testing.T) {
		req := &model.LoginRequest{
			Username: "loginuser",
			Password: "wrongpassword",
		}
		_, err := svc.Login(req)
		if err == nil {
			t.Fatal("Login() should fail with wrong password")
		}
		if err.Error() != "invalid username or password" {
			t.Errorf("Login() error = %v, want 'invalid username or password'", err)
		}
	})

	t.Run("inactive user", func(t *testing.T) {
		// Create as active first, then update to inactive
		// (GORM skips bool zero-value with gorm:"default:true" tag on Create)
		hashed, _ := bcrypt.GenerateFromPassword([]byte("pass123"), bcrypt.DefaultCost)
		inactiveUser := &model.User{
			Username: "inactive",
			Email:    "inactive@test.com",
			Password: string(hashed),
			IsActive: true,
		}
		db.Create(inactiveUser)
		db.Model(&model.User{}).Where("id = ?", inactiveUser.ID).Update("is_active", false)

		req := &model.LoginRequest{
			Username: "inactive",
			Password: "pass123",
		}
		_, err := svc.Login(req)
		if err == nil {
			t.Fatal("Login() should fail for inactive user")
		}
		if err.Error() != "user account is inactive" {
			t.Errorf("Login() error = %v, want 'user account is inactive'", err)
		}
	})
}

// ========== GetByID Tests ==========

func TestUserService_GetByID(t *testing.T) {
	svc, db := newUserService(t)

	user := &model.User{
		Username: "getuser",
		Email:    "get@test.com",
		Password: "hash",
		IsActive: true,
	}
	db.Create(user)

	t.Run("success", func(t *testing.T) {
		found, err := svc.GetByID(user.ID)
		if err != nil {
			t.Fatalf("GetByID() error = %v", err)
		}
		if found.Username != "getuser" {
			t.Errorf("GetByID() username = %v, want 'getuser'", found.Username)
		}
		if found.Password != "" {
			t.Error("GetByID() password should be cleared")
		}
	})

	t.Run("not found", func(t *testing.T) {
		_, err := svc.GetByID(99999)
		if err == nil {
			t.Fatal("GetByID() should return error for non-existent user")
		}
	})
}

// ========== Update Tests ==========

func TestUserService_Update(t *testing.T) {
	svc, db := newUserService(t)

	user := &model.User{
		Username: "updateuser",
		Email:    "update@test.com",
		Password: "hash",
		Nickname: "Old Nick",
		IsActive: true,
	}
	db.Create(user)

	user.Nickname = "New Nick"
	err := svc.Update(user)
	if err != nil {
		t.Fatalf("Update() error = %v", err)
	}

	updated, _ := svc.GetByID(user.ID)
	if updated.Nickname != "New Nick" {
		t.Errorf("Update() nickname = %v, want 'New Nick'", updated.Nickname)
	}
}

// ========== SearchUsers Tests ==========

func TestUserService_SearchUsers(t *testing.T) {
	svc, db := newUserService(t)

	// Create test users
	users := []model.User{
		{Username: "alice", Email: "alice@test.com", Nickname: "Alice Smith", Password: "hash", IsActive: true},
		{Username: "bob", Email: "bob@test.com", Nickname: "Bob Jones", Password: "hash", IsActive: true},
		{Username: "charlie", Email: "charlie@test.com", Nickname: "Charlie Brown", Password: "hash", IsActive: true},
	}
	for i := range users {
		db.Create(&users[i])
	}

	t.Run("search by username", func(t *testing.T) {
		resp, err := svc.SearchUsers("alice", 10)
		if err != nil {
			t.Fatalf("SearchUsers() error = %v", err)
		}
		if resp.Total != 1 {
			t.Errorf("SearchUsers() total = %v, want 1", resp.Total)
		}
	})

	t.Run("search by email", func(t *testing.T) {
		resp, _ := svc.SearchUsers("bob@test.com", 10)
		if resp.Total != 1 {
			t.Errorf("SearchUsers() total = %v, want 1", resp.Total)
		}
	})

	t.Run("search with limit", func(t *testing.T) {
		resp, _ := svc.SearchUsers("test.com", 2)
		if len(resp.Users) > 2 {
			t.Errorf("SearchUsers() should respect limit, got %v users", len(resp.Users))
		}
	})

	t.Run("no results", func(t *testing.T) {
		resp, _ := svc.SearchUsers("nonexistent", 10)
		if resp.Total != 0 {
			t.Errorf("SearchUsers() total = %v, want 0", resp.Total)
		}
	})
}

// ========== ListUsers Tests ==========

func TestUserService_ListUsers(t *testing.T) {
	svc, db := newUserService(t)

	for i := 0; i < 5; i++ {
		user := &model.User{
			Username: "listuser" + string(rune('0'+i)),
			Email:    "list" + string(rune('0'+i)) + "@test.com",
			Password: "hash",
			IsActive: true,
		}
		db.Create(user)
	}

	t.Run("first page", func(t *testing.T) {
		resp, err := svc.ListUsers(1, 3)
		if err != nil {
			t.Fatalf("ListUsers() error = %v", err)
		}
		if resp.Total != 5 {
			t.Errorf("ListUsers() total = %v, want 5", resp.Total)
		}
		if len(resp.Users) != 3 {
			t.Errorf("ListUsers() count = %v, want 3", len(resp.Users))
		}
	})

	t.Run("second page", func(t *testing.T) {
		resp, _ := svc.ListUsers(2, 3)
		if len(resp.Users) != 2 {
			t.Errorf("ListUsers() second page count = %v, want 2", len(resp.Users))
		}
	})
}
