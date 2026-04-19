package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
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
	usersByID map[string]*User
	roles     map[string]Role
}

type MeResponse struct {
	UserID      string      `json:"user_id"`
	TenantID    string      `json:"tenant_id"`
	Roles       []string    `json:"roles"`
	Permissions Permissions `json:"permissions"`
	SuperAdmin  bool        `json:"super_admin"`
}

type sessionClaims struct {
	UserID   string   `json:"user_id"`
	TenantID string   `json:"tenant_id"`
	Roles    []string `json:"roles"`
	jwt.RegisteredClaims
}

func NewService(cfg Config, roles map[string]Role) (*Service, error) {
	if strings.TrimSpace(cfg.JWT.Secret) == "" {
		return nil, fmt.Errorf("auth.jwt.secret is required")
	}
	if cfg.JWT.TTL <= 0 {
		cfg.JWT.TTL = 24 * time.Hour
	}
	if strings.TrimSpace(cfg.JWT.CookieName) == "" {
		cfg.JWT.CookieName = "promptd_session"
	}
	usersByID := make(map[string]*User, len(cfg.Users))
	for i := range cfg.Users {
		user := &cfg.Users[i]
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
	return &Service{jwtConfig: cfg.JWT, usersByID: usersByID, roles: roles}, nil
}

func (s *Service) AuthenticatePassword(userID, password string) (*Principal, error) {
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
	now := time.Now()
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
	user, ok := s.usersByID[scope.UserID]
	if !ok || user.Disabled || subtle.ConstantTimeCompare([]byte(user.TenantID), []byte(scope.TenantID)) != 1 {
		return nil, ErrUnauthorized
	}
	return s.buildPrincipal(user, "internal")
}

func (s *Service) IssueSessionCookie(w http.ResponseWriter, principal *Principal) error {
	claims := sessionClaims{
		UserID:   principal.Scope.UserID,
		TenantID: principal.Scope.TenantID,
		Roles:    append([]string(nil), principal.Roles...),
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   principal.Scope.UserID,
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(s.jwtConfig.TTL)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(s.jwtConfig.Secret))
	if err != nil {
		return err
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
	return nil
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
	parsed, err := jwt.ParseWithClaims(cookie.Value, &sessionClaims{}, func(token *jwt.Token) (interface{}, error) {
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
		UserID:      principal.Scope.UserID,
		TenantID:    principal.Scope.TenantID,
		Roles:       append([]string(nil), principal.Roles...),
		Permissions: principal.Policy.Permissions,
		SuperAdmin:  principal.Policy.SuperAdmin,
	}
}
