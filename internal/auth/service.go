package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

type contextKey string

const principalContextKey contextKey = "principal"

var ErrUnauthorized = errors.New("unauthorized")

type JWTConfig struct {
	Secret     string        `yaml:"secret"`
	TTL        time.Duration `yaml:"ttl"`
	CookieName string        `yaml:"cookie_name"`
}

type Config struct {
	JWT   JWTConfig `yaml:"jwt"`
	Users []User    `yaml:"users"`
}

type Service struct {
	jwtConfig JWTConfig
	store     *Store
	mu        sync.RWMutex
	usersByID map[string]*User
	roles     map[string]Role
}

type MeResponse struct {
	UserID             string      `json:"user_id"`
	TenantID           string      `json:"tenant_id"`
	Roles              []string    `json:"roles"`
	Permissions        Permissions `json:"permissions"`
	SuperAdmin         bool        `json:"super_admin"`
	MustChangePassword bool        `json:"must_change_password"`
}

type sessionClaims struct {
	UserID   string   `json:"user_id"`
	TenantID string   `json:"tenant_id"`
	Roles    []string `json:"roles"`
	jwt.RegisteredClaims
}

func NewService(cfg Config, roles map[string]Role, store *Store, logger *zap.Logger) (*Service, error) {
	if strings.TrimSpace(cfg.JWT.Secret) == "" {
		return nil, fmt.Errorf("auth.jwt.secret is required")
	}
	if cfg.JWT.TTL <= 0 {
		cfg.JWT.TTL = 24 * time.Hour
	}
	if strings.TrimSpace(cfg.JWT.CookieName) == "" {
		cfg.JWT.CookieName = "promptd_session"
	}
	data := StoreData{Users: cfg.Users, Roles: roles}
	if store != nil {
		if logger == nil {
			logger = zap.NewNop()
		}
		var err error
		data, err = store.LoadOrBootstrap(cfg.Users, roles, logger)
		if err != nil {
			return nil, err
		}
	}
	usersByID, err := validateUsers(data.Users, data.Roles)
	if err != nil {
		return nil, err
	}
	return &Service{jwtConfig: cfg.JWT, store: store, usersByID: usersByID, roles: data.Roles}, nil
}

func validateUsers(users []User, roles map[string]Role) (map[string]*User, error) {
	usersByID := make(map[string]*User, len(users))
	for i := range users {
		user := &users[i]
		if strings.TrimSpace(user.ID) == "" {
			return nil, fmt.Errorf("auth.users[].id is required")
		}
		if strings.TrimSpace(user.TenantID) == "" {
			user.TenantID = "default"
		}
		if len(user.Roles) == 0 {
			return nil, fmt.Errorf("auth.users[%q].roles is required", user.ID)
		}
		if _, exists := usersByID[user.ID]; exists {
			return nil, fmt.Errorf("duplicate auth.users id %q", user.ID)
		}
		if strings.TrimSpace(user.PasswordHash) == "" && len(user.ServiceTokens) == 0 {
			return nil, fmt.Errorf("auth.users[%q] must have password_hash or service_tokens", user.ID)
		}
		if _, err := CompileEffectivePolicy(user.Roles, roles); err != nil {
			return nil, fmt.Errorf("compile roles for user %q: %w", user.ID, err)
		}
		usersByID[user.ID] = user
	}
	return usersByID, nil
}

func (s *Service) AuthenticatePassword(userID, password string) (*Principal, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.usersByID[userID]
	if !ok || user.Disabled || strings.TrimSpace(user.PasswordHash) == "" {
		return nil, ErrUnauthorized
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, ErrUnauthorized
	}
	return s.buildPrincipal(user, "session")
}

func (s *Service) AuthenticateBearer(token string) (*Principal, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil, ErrUnauthorized
	}
	if principal, err := s.AuthenticateSessionToken(token); err == nil {
		return principal, nil
	}
	now := time.Now()
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, user := range s.usersByID {
		if user.Disabled {
			continue
		}
		for _, serviceToken := range user.ServiceTokens {
			if serviceToken.Disabled || strings.TrimSpace(serviceToken.TokenHash) == "" {
				continue
			}
			if serviceToken.NotBefore != "" {
				t, err := time.Parse(time.RFC3339, serviceToken.NotBefore)
				if err == nil && now.Before(t) {
					continue
				}
			}
			if serviceToken.ExpiresAt != "" {
				t, err := time.Parse(time.RFC3339, serviceToken.ExpiresAt)
				if err == nil && !now.Before(t) {
					continue
				}
			}
			if bcrypt.CompareHashAndPassword([]byte(serviceToken.TokenHash), []byte(token)) == nil {
				return s.buildPrincipal(user, "service_token")
			}
		}
	}
	return nil, ErrUnauthorized
}

func (s *Service) AuthenticateSessionToken(tokenValue string) (*Principal, error) {
	tokenValue = strings.TrimSpace(tokenValue)
	if tokenValue == "" {
		return nil, ErrUnauthorized
	}
	parsed, err := jwt.ParseWithClaims(tokenValue, &sessionClaims{}, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return []byte(s.jwtConfig.Secret), nil
	})
	if err != nil || !parsed.Valid {
		return nil, ErrUnauthorized
	}
	claims, ok := parsed.Claims.(*sessionClaims)
	if !ok {
		return nil, ErrUnauthorized
	}
	principal, err := s.BuildPrincipalByScope(ResourceScope{TenantID: claims.TenantID, UserID: claims.UserID})
	if err != nil {
		return nil, ErrUnauthorized
	}
	return principal, nil
}

func (s *Service) buildPrincipal(user *User, via string) (*Principal, error) {
	policy, err := CompileEffectivePolicy(user.Roles, s.roles)
	if err != nil {
		return nil, err
	}
	return &Principal{
		User:   user,
		Scope:  ResourceScope{TenantID: user.TenantID, UserID: user.ID},
		Roles:  append([]string(nil), user.Roles...),
		Policy: policy,
		Via:    via,
	}, nil
}

func (s *Service) BuildPrincipalByScope(scope ResourceScope) (*Principal, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.usersByID[scope.UserID]
	if !ok || user.Disabled || subtle.ConstantTimeCompare([]byte(user.TenantID), []byte(scope.TenantID)) != 1 {
		return nil, ErrUnauthorized
	}
	return s.buildPrincipal(user, "internal")
}

func (s *Service) IssueSessionToken(principal *Principal) (string, time.Time, error) {
	expiresAt := time.Now().Add(s.jwtConfig.TTL)
	claims := sessionClaims{
		UserID:   principal.Scope.UserID,
		TenantID: principal.Scope.TenantID,
		Roles:    append([]string(nil), principal.Roles...),
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   principal.Scope.UserID,
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(s.jwtConfig.Secret))
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, expiresAt, nil
}

func (s *Service) IssueSessionCookie(w http.ResponseWriter, principal *Principal) (string, time.Time, error) {
	signed, expiresAt, err := s.IssueSessionToken(principal)
	if err != nil {
		return "", time.Time{}, err
	}
	http.SetCookie(w, &http.Cookie{
		Name:     s.jwtConfig.CookieName,
		Value:    signed,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   false,
		MaxAge:   int(s.jwtConfig.TTL.Seconds()),
	})
	return signed, expiresAt, nil
}

func (s *Service) ClearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     s.jwtConfig.CookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   false,
		Expires:  time.Unix(0, 0),
		MaxAge:   -1,
	})
}

func (s *Service) AuthenticateRequest(r *http.Request) (*Principal, error) {
	authz := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(authz), "bearer ") {
		return s.AuthenticateBearer(strings.TrimSpace(authz[7:]))
	}
	cookie, err := r.Cookie(s.jwtConfig.CookieName)
	if err != nil || strings.TrimSpace(cookie.Value) == "" {
		return nil, ErrUnauthorized
	}
	return s.AuthenticateSessionToken(cookie.Value)
}

func (s *Service) Require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		principal, err := s.AuthenticateRequest(r)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), principalContextKey, principal)))
	})
}

func PrincipalFromContext(ctx context.Context) *Principal {
	principal, _ := ctx.Value(principalContextKey).(*Principal)
	return principal
}

func (s *Service) ToMeResponse(principal *Principal) MeResponse {
	return MeResponse{
		UserID:             principal.Scope.UserID,
		TenantID:           principal.Scope.TenantID,
		Roles:              append([]string(nil), principal.Roles...),
		Permissions:        principal.Policy.Permissions,
		SuperAdmin:         principal.Policy.SuperAdmin,
		MustChangePassword: principal.User.MustChangePassword,
	}
}

func (s *Service) ListUsers() []User {
	s.mu.RLock()
	defer s.mu.RUnlock()
	users := make([]User, 0, len(s.usersByID))
	for _, user := range s.usersByID {
		copy := *user
		copy.PasswordHash = ""
		users = append(users, copy)
	}
	sort.Slice(users, func(i, j int) bool { return users[i].ID < users[j].ID })
	return users
}

func (s *Service) ListRoles() map[string]Role {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return copyRoles(s.roles)
}

func (s *Service) SaveUser(user User, password string) error {
	user.ID = strings.TrimSpace(user.ID)
	if user.ID == "" {
		return fmt.Errorf("user id is required")
	}
	if user.TenantID == "" {
		user.TenantID = "default"
	}
	if password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		user.PasswordHash = string(hash)
		user.MustChangePassword = true
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing, ok := s.usersByID[user.ID]; ok && user.PasswordHash == "" {
		user.PasswordHash = existing.PasswordHash
		user.ServiceTokens = existing.ServiceTokens
		user.MustChangePassword = existing.MustChangePassword
	}
	users := s.usersLocked()
	found := false
	for i := range users {
		if users[i].ID == user.ID {
			users[i] = user
			found = true
			break
		}
	}
	if !found {
		users = append(users, user)
	}
	return s.replaceLocked(users, s.roles)
}

func (s *Service) DeleteUser(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.usersByID[id]; !ok {
		return fmt.Errorf("unknown user %q", id)
	}
	users := make([]User, 0, len(s.usersByID)-1)
	for _, user := range s.usersLocked() {
		if user.ID != id {
			users = append(users, user)
		}
	}
	return s.replaceLocked(users, s.roles)
}

func (s *Service) SaveRole(name string, role Role) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return fmt.Errorf("role name is required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	roles := copyRoles(s.roles)
	roles[name] = role
	return s.replaceLocked(s.usersLocked(), roles)
}

func (s *Service) DeleteRole(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, user := range s.usersByID {
		for _, role := range user.Roles {
			if role == name {
				return fmt.Errorf("role %q is assigned to user %q", name, user.ID)
			}
		}
	}
	roles := copyRoles(s.roles)
	delete(roles, name)
	return s.replaceLocked(s.usersLocked(), roles)
}

func (s *Service) ChangePassword(userID, currentPassword, newPassword string) error {
	if len(newPassword) < 8 {
		return fmt.Errorf("new password must be at least 8 characters")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	user, ok := s.usersByID[userID]
	if !ok || bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)) != nil {
		return ErrUnauthorized
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	users := s.usersLocked()
	for i := range users {
		if users[i].ID == userID {
			users[i].PasswordHash = string(hash)
			users[i].MustChangePassword = false
			break
		}
	}
	return s.replaceLocked(users, s.roles)
}

func (s *Service) usersLocked() []User {
	users := make([]User, 0, len(s.usersByID))
	for _, user := range s.usersByID {
		users = append(users, *user)
	}
	sort.Slice(users, func(i, j int) bool { return users[i].ID < users[j].ID })
	return users
}

func (s *Service) replaceLocked(users []User, roles map[string]Role) error {
	usersByID, err := validateUsers(users, roles)
	if err != nil {
		return err
	}
	if s.store != nil {
		if err := s.store.Save(StoreData{Users: users, Roles: roles}); err != nil {
			return err
		}
	}
	s.usersByID = usersByID
	s.roles = roles
	return nil
}
