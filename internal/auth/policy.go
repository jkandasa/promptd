package auth

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

type Permissions struct {
	Chat                     bool `yaml:"chat" json:"chat"`
	Upload                   bool `yaml:"upload" json:"upload"`
	ConversationsRead        bool `yaml:"conversations_read" json:"conversations_read"`
	ConversationsWrite       bool `yaml:"conversations_write" json:"conversations_write"`
	CompactConversationWrite bool `yaml:"compact_conversation_write" json:"compact_conversation_write"`
	SchedulesRead            bool `yaml:"schedules_read" json:"schedules_read"`
	SchedulesWrite           bool `yaml:"schedules_write" json:"schedules_write"`
	TracesRead               bool `yaml:"traces_read" json:"traces_read"`
	Admin                    bool `yaml:"admin" json:"admin"`
}

func fullPermissions() Permissions {
	return Permissions{
		Chat:                     true,
		Upload:                   true,
		ConversationsRead:        true,
		ConversationsWrite:       true,
		CompactConversationWrite: true,
		SchedulesRead:            true,
		SchedulesWrite:           true,
		TracesRead:               true,
		Admin:                    true,
	}
}

func (p *Permissions) Merge(other Permissions) {
	p.Chat = p.Chat || other.Chat
	p.Upload = p.Upload || other.Upload
	p.ConversationsRead = p.ConversationsRead || other.ConversationsRead
	p.ConversationsWrite = p.ConversationsWrite || other.ConversationsWrite
	p.CompactConversationWrite = p.CompactConversationWrite || other.CompactConversationWrite
	p.SchedulesRead = p.SchedulesRead || other.SchedulesRead
	p.SchedulesWrite = p.SchedulesWrite || other.SchedulesWrite
	p.TracesRead = p.TracesRead || other.TracesRead
	p.Admin = p.Admin || other.Admin
}

type StringPolicy struct {
	Allow []string `yaml:"allow"`
}

type Role struct {
	SuperAdmin    bool         `yaml:"super_admin"`
	Permissions   Permissions  `yaml:"permissions"`
	Models        StringPolicy `yaml:"models"`
	Tools         StringPolicy `yaml:"tools"`
	SystemPrompts StringPolicy `yaml:"system_prompts"`
}

type ServiceToken struct {
	ID        string `yaml:"id"`
	TokenHash string `yaml:"token_hash"`
	ExpiresAt string `yaml:"expires_at,omitempty"`
	NotBefore string `yaml:"not_before,omitempty"`
	Disabled  bool   `yaml:"disabled,omitempty"`
}

type User struct {
	ID            string         `yaml:"id"`
	TenantID      string         `yaml:"tenant_id"`
	PasswordHash  string         `yaml:"password_hash,omitempty"`
	Roles         []string       `yaml:"roles"`
	ServiceTokens []ServiceToken `yaml:"service_tokens,omitempty"`
	Disabled      bool           `yaml:"disabled,omitempty"`
}

type ResourceScope struct {
	TenantID string
	UserID   string
}

func (s ResourceScope) Key() string {
	return s.TenantID + ":" + s.UserID
}

type Principal struct {
	User   *User
	Scope  ResourceScope
	Roles  []string
	Policy EffectivePolicy
	Via    string
}

type globPattern struct {
	raw string
	re  *regexp.Regexp
}

func compileGlob(pattern string) (globPattern, error) {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return globPattern{}, fmt.Errorf("empty pattern")
	}
	var b strings.Builder
	b.WriteString("^")
	for _, r := range pattern {
		switch r {
		case '*':
			b.WriteString(".*")
		case '?':
			b.WriteString(".")
		default:
			b.WriteString(regexp.QuoteMeta(string(r)))
		}
	}
	b.WriteString("$")
	re, err := regexp.Compile(b.String())
	if err != nil {
		return globPattern{}, fmt.Errorf("compile pattern %q: %w", pattern, err)
	}
	return globPattern{raw: pattern, re: re}, nil
}

func (g globPattern) Match(value string) bool {
	return g.re != nil && g.re.MatchString(value)
}

type modelPattern struct {
	provider globPattern
	model    globPattern
}

func compileModelPattern(rule string) (modelPattern, error) {
	rule = strings.TrimSpace(rule)
	if rule == "*" {
		provider, err := compileGlob("*")
		if err != nil {
			return modelPattern{}, err
		}
		model, err := compileGlob("*")
		if err != nil {
			return modelPattern{}, err
		}
		return modelPattern{provider: provider, model: model}, nil
	}
	parts := strings.SplitN(rule, ":", 2)
	if len(parts) != 2 {
		return modelPattern{}, fmt.Errorf("invalid model rule %q; expected <provider-pattern>:<model-pattern> or *", rule)
	}
	provider, err := compileGlob(parts[0])
	if err != nil {
		return modelPattern{}, err
	}
	model, err := compileGlob(parts[1])
	if err != nil {
		return modelPattern{}, err
	}
	return modelPattern{provider: provider, model: model}, nil
}

func (m modelPattern) Match(provider, model string) bool {
	return m.provider.Match(provider) && m.model.Match(model)
}

type EffectivePolicy struct {
	Permissions    Permissions
	SuperAdmin     bool
	ModelPatterns  []modelPattern
	ToolPatterns   []globPattern
	PromptPatterns []globPattern
	RoleNames      []string
}

func (p EffectivePolicy) AllowModel(provider, model string) bool {
	if p.SuperAdmin {
		return true
	}
	for _, pattern := range p.ModelPatterns {
		if pattern.Match(provider, model) {
			return true
		}
	}
	return false
}

func (p EffectivePolicy) AllowTool(name string) bool {
	if p.SuperAdmin {
		return true
	}
	for _, pattern := range p.ToolPatterns {
		if pattern.Match(name) {
			return true
		}
	}
	return false
}

func (p EffectivePolicy) AllowPrompt(name string) bool {
	if p.SuperAdmin {
		return true
	}
	for _, pattern := range p.PromptPatterns {
		if pattern.Match(name) {
			return true
		}
	}
	return false
}

func (p EffectivePolicy) FilterPromptNames(names []string) []string {
	if p.SuperAdmin {
		return append([]string(nil), names...)
	}
	filtered := make([]string, 0, len(names))
	for _, name := range names {
		if p.AllowPrompt(name) {
			filtered = append(filtered, name)
		}
	}
	return filtered
}

func (p EffectivePolicy) FilterAllowedToolNames(names []string) []string {
	if p.SuperAdmin {
		return append([]string(nil), names...)
	}
	filtered := make([]string, 0, len(names))
	for _, name := range names {
		if p.AllowTool(name) {
			filtered = append(filtered, name)
		}
	}
	return filtered
}

func CompileEffectivePolicy(roleNames []string, roles map[string]Role) (EffectivePolicy, error) {
	policy := EffectivePolicy{}
	for _, roleName := range roleNames {
		role, ok := roles[roleName]
		if !ok {
			return EffectivePolicy{}, fmt.Errorf("unknown role %q", roleName)
		}
		policy.RoleNames = append(policy.RoleNames, roleName)
		policy.SuperAdmin = policy.SuperAdmin || role.SuperAdmin
		policy.Permissions.Merge(role.Permissions)
		for _, rule := range role.Models.Allow {
			compiled, err := compileModelPattern(rule)
			if err != nil {
				return EffectivePolicy{}, err
			}
			policy.ModelPatterns = append(policy.ModelPatterns, compiled)
		}
		for _, rule := range role.Tools.Allow {
			compiled, err := compileGlob(rule)
			if err != nil {
				return EffectivePolicy{}, err
			}
			policy.ToolPatterns = append(policy.ToolPatterns, compiled)
		}
		for _, rule := range role.SystemPrompts.Allow {
			compiled, err := compileGlob(rule)
			if err != nil {
				return EffectivePolicy{}, err
			}
			policy.PromptPatterns = append(policy.PromptPatterns, compiled)
		}
	}
	if policy.SuperAdmin {
		policy.Permissions = fullPermissions()
	}
	sort.Strings(policy.RoleNames)
	return policy, nil
}
