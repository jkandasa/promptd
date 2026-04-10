package storage

import "errors"

// ErrNotFound is returned by Load and Delete when the conversation does not exist.
var ErrNotFound = errors.New("conversation not found")
