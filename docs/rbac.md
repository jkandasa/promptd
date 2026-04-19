# RBAC

`promptd` uses role-based access control with per-role permissions and allow-list restrictions.

## Overview

- Permissions are boolean flags merged across the roles assigned to a user.
- Models, tools, and system prompts can also be restricted with allow-list pattern matching.
- `super_admin: true` bypasses those allow-list restrictions inside the tenant.

## Current Permissions

- `chat`
- `upload`
- `conversations_read`
- `conversations_write`
- `compact_conversation_write`
- `schedules_read`
- `schedules_write`
- `traces_read`
- `admin`

## Notes

- Manual conversation compaction requires `compact_conversation_write`.
- Automatic compaction does not require that permission.
