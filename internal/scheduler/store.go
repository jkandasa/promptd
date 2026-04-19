package scheduler

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"promptd/internal/storage"

	"gopkg.in/yaml.v3"
)

var ErrNotFound = errors.New("not found")

type Store struct {
	root string
	mu   sync.RWMutex
}

func NewStore(root string) (*Store, error) {
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	return &Store{root: root}, nil
}

func (s *Store) scopeSchedulesDir(scope storage.Scope) string {
	return filepath.Join(s.root, "tenants", scope.TenantID, "users", scope.UserID, "schedules")
}

func (s *Store) scopeExecutionsDir(scope storage.Scope) string {
	return filepath.Join(s.scopeSchedulesDir(scope), "executions")
}

func (s *Store) ensureScope(scope storage.Scope) error {
	for _, dir := range []string{s.scopeSchedulesDir(scope), s.scopeExecutionsDir(scope)} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) SaveSchedule(scope storage.Scope, sc *Schedule) error {
	if err := s.ensureScope(scope); err != nil {
		return err
	}
	sc.TenantID = scope.TenantID
	sc.UserID = scope.UserID
	s.mu.Lock()
	defer s.mu.Unlock()
	path := filepath.Join(s.scopeSchedulesDir(scope), sc.ID+".yaml")
	data, err := yaml.Marshal(sc)
	if err != nil {
		return fmt.Errorf("marshal schedule: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("write schedule: %w", err)
	}
	return os.Rename(tmp, path)
}

func (s *Store) LoadSchedule(scope storage.Scope, id string) (*Schedule, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	path := filepath.Join(s.scopeSchedulesDir(scope), id+".yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("read schedule: %w", err)
	}
	var sc Schedule
	if err := yaml.Unmarshal(data, &sc); err != nil {
		return nil, fmt.Errorf("unmarshal schedule: %w", err)
	}
	return &sc, nil
}

func (s *Store) ListSchedules(scope storage.Scope) ([]*Schedule, error) {
	if err := s.ensureScope(scope); err != nil {
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	entries, err := os.ReadDir(s.scopeSchedulesDir(scope))
	if err != nil {
		return nil, fmt.Errorf("read schedules dir: %w", err)
	}
	var list []*Schedule
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		id := strings.TrimSuffix(e.Name(), ".yaml")
		sc, err := s.LoadSchedule(scope, id)
		if err != nil {
			continue
		}
		list = append(list, sc)
	}
	sort.Slice(list, func(i, j int) bool {
		return list[i].CreatedAt.After(list[j].CreatedAt)
	})
	return list, nil
}

func (s *Store) ListAllSchedules() ([]*Schedule, error) {
	var list []*Schedule
	root := filepath.Join(s.root, "tenants")
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() || filepath.Ext(path) != ".yaml" || strings.Contains(path, string(filepath.Separator)+"executions"+string(filepath.Separator)) {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		var sc Schedule
		if err := yaml.Unmarshal(data, &sc); err != nil {
			return nil
		}
		list = append(list, &sc)
		return nil
	})
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	return list, nil
}

func (s *Store) DeleteSchedule(scope storage.Scope, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	path := filepath.Join(s.scopeSchedulesDir(scope), id+".yaml")
	if err := os.Remove(path); err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return fmt.Errorf("delete schedule: %w", err)
	}
	_ = os.RemoveAll(filepath.Join(s.scopeExecutionsDir(scope), id))
	return nil
}

func (s *Store) SaveExecution(scope storage.Scope, exec *Execution, retainHistory int) error {
	if err := s.ensureScope(scope); err != nil {
		return err
	}
	exec.TenantID = scope.TenantID
	exec.UserID = scope.UserID
	s.mu.Lock()
	defer s.mu.Unlock()
	dir := filepath.Join(s.scopeExecutionsDir(scope), exec.ScheduleID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create execution dir: %w", err)
	}
	ts := exec.TriggeredAt.UTC().Format("20060102-150405")
	path := filepath.Join(dir, ts+"-"+exec.ID+".yaml")
	data, err := yaml.Marshal(exec)
	if err != nil {
		return fmt.Errorf("marshal execution: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("write execution: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("rename execution: %w", err)
	}
	if retainHistory > 0 {
		s.pruneExecutions(dir, retainHistory)
	}
	return nil
}

func (s *Store) pruneExecutions(dir string, keep int) {
	entries, _ := os.ReadDir(dir)
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".yaml") {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)
	for len(files) > keep {
		_ = os.Remove(filepath.Join(dir, files[0]))
		files = files[1:]
	}
}

func (s *Store) ListExecutions(scope storage.Scope, scheduleID string) ([]*Execution, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	dir := filepath.Join(s.scopeExecutionsDir(scope), scheduleID)
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read execution dir: %w", err)
	}
	var list []*Execution
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			continue
		}
		var exec Execution
		if err := yaml.Unmarshal(data, &exec); err != nil {
			continue
		}
		list = append(list, &exec)
	}
	sort.Slice(list, func(i, j int) bool {
		return list[i].TriggeredAt.After(list[j].TriggeredAt)
	})
	return list, nil
}

func (s *Store) DeleteExecution(scope storage.Scope, scheduleID, execID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	dir := filepath.Join(s.scopeExecutionsDir(scope), scheduleID)
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return fmt.Errorf("read execution dir: %w", err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), "-"+execID+".yaml") {
			return os.Remove(filepath.Join(dir, e.Name()))
		}
	}
	return ErrNotFound
}
