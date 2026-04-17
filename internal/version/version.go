// Package version exposes build-time metadata injected via -ldflags.
// All variables default to placeholder values when the binary is built
// without explicit ldflags (e.g. plain `go build` during development).
package version

import (
	"fmt"
	"runtime"
	"sync"
)

// Injected at build time via -ldflags "-X promptd/internal/version.<Var>=...".
var (
	gitCommit string
	buildDate string

	// version has a static fallback so plain `go run`/`go build` still works.
	version string = "dev"

	once     sync.Once
	_version Version
)

// Version holds build-time and runtime metadata.
type Version struct {
	Version   string `json:"version"   yaml:"version"`
	GitCommit string `json:"gitCommit" yaml:"gitCommit"`
	BuildDate string `json:"buildDate" yaml:"buildDate"`
	GoVersion string `json:"goVersion" yaml:"goVersion"`
	Compiler  string `json:"compiler"  yaml:"compiler"`
	Platform  string `json:"platform"  yaml:"platform"`
	Arch      string `json:"arch"      yaml:"arch"`
}

// Get returns the singleton Version, populated once on first call.
func Get() Version {
	once.Do(func() {
		_version = Version{
			Version:   version,
			GitCommit: gitCommit,
			BuildDate: buildDate,
			GoVersion: runtime.Version(),
			Compiler:  runtime.Compiler,
			Platform:  runtime.GOOS,
			Arch:      runtime.GOARCH,
		}
	})
	return _version
}

// String returns a human-readable summary of the version.
func (v Version) String() string {
	return fmt.Sprintf(
		"{version:%s, buildDate:%s, gitCommit:%s, goVersion:%s, compiler:%s, platform:%s, arch:%s}",
		v.Version, v.BuildDate, v.GitCommit, v.GoVersion, v.Compiler, v.Platform, v.Arch,
	)
}
