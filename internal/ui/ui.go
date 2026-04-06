// Package ui embeds the compiled React/Ant Design web UI.
// The dist/ directory is produced by running `pnpm build` inside web/.
package ui

import (
	"embed"
	"io/fs"
)

//go:embed dist
var distFS embed.FS

// FS returns a sub-filesystem rooted at the dist/ directory.
// Serve it with http.FileServer(http.FS(ui.FS())).
func FS() fs.FS {
	sub, err := fs.Sub(distFS, "dist")
	if err != nil {
		panic("ui: failed to sub dist FS: " + err.Error())
	}
	return sub
}
