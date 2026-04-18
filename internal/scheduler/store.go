package scheduler

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

// ErrNotFound is returned when a schedule or execution does not exist.
var ErrNotFound = errors.New("not found")

// Store manages on-disk persistence for schedules and their executions.
//
// Layout:
//
//	<dir>/schedules/<id>.yaml
//	<dir>/schedules/executions/<schedule_id>/<timestamp>-<exec_id>.yaml
type Store struct {
	schedulesDir  string
	executionsDir string
	mu            sync.RWMutex
}

// NewStore creates (and if necessary, initialises) the storage directories.
func NewStore(dir string) (*Store, error) {
	schedulesDir := filepath.Join(dir, "schedules")
	executionsDir := filepath.Join(dir, "schedules", "executions")
	for _, d := range []string{schedulesDir, executionsDir} {
		if err := os.MkdirAll(d, 0755); err != nil {
			return nil, fmt.Errorf("create dir %s: %w", d, err)
		}
	}
	return &Store{schedulesDir: schedulesDir, executionsDir: executionsDir}, nil
}

// SaveSchedule writes (or overwrites) a schedule to disk.
func (s *Store) SaveSchedule(sc *Schedule) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.saveSchedule(sc)
}

func (s *Store) saveSchedule(sc *Schedule) error {
	path := filepath.Join(s.schedulesDir, sc.ID+".yaml")
	data, err := yaml.Marshal(sc)
	if err != nil {
		return fmt.Errorf("marshal schedule: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return fmt.Errorf("write schedule: %w", err)
	}
	return os.Rename(tmp, path)
}

// LoadSchedule reads a schedule by ID.
func (s *Store) LoadSchedule(id string) (*Schedule, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.loadSchedule(id)
}

func (s *Store) loadSchedule(id string) (*Schedule, error) {
	path := filepath.Join(s.schedulesDir, id+".yaml")
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

// ListSchedules returns all schedules sorted newest-first.
func (s *Store) ListSchedules() ([]*Schedule, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	entries, err := os.ReadDir(s.schedulesDir)
	if err != nil {
		return nil, fmt.Errorf("read schedules dir: %w", err)
	}
	var list []*Schedule
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		id := strings.TrimSuffix(e.Name(), ".yaml")
		sc, err := s.loadSchedule(id)
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

// DeleteSchedule removes a schedule and all its executions.
func (s *Store) DeleteSchedule(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	path := filepath.Join(s.schedulesDir, id+".yaml")
	if err := os.Remove(path); err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return fmt.Errorf("delete schedule: %w", err)
	}
	// Best-effort removal of execution files.
	_ = os.RemoveAll(filepath.Join(s.executionsDir, id))
	return nil
}

// SaveExecution writes an execution and prunes old ones when retain > 0.
func (s *Store) SaveExecution(exec *Execution, retainHistory int) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Join(s.executionsDir, exec.ScheduleID)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create execution dir: %w", err)
	}

	ts := exec.TriggeredAt.UTC().Format("20060102-150405")
	path := filepath.Join(dir, ts+"-"+exec.ID+".yaml")

	data, err := yaml.Marshal(exec)
	if err != nil {
		return fmt.Errorf("marshal execution: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
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
	sort.Strings(files) // timestamp prefix gives chronological order
	for len(files) > keep {
		_ = os.Remove(filepath.Join(dir, files[0]))
		files = files[1:]
	}
}

// ListExecutions returns executions for a schedule, newest first.
func (s *Store) ListExecutions(scheduleID string) ([]*Execution, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	dir := filepath.Join(s.executionsDir, scheduleID)
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

// DeleteExecution removes one execution file.
func (s *Store) DeleteExecution(scheduleID, execID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Join(s.executionsDir, scheduleID)
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
