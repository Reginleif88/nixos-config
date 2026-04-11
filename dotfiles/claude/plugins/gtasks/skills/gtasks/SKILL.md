---
name: gtasks
description: This skill should be used when the user wants to manage Google Tasks from the terminal — viewing, creating, completing, or organizing tasks and task lists using the gtasks CLI tool.
---

# Google Tasks CLI (gtasks)

`gtasks` is a terminal client for Google Tasks. Config lives at `~/.config/gtasks/config.toml`.

## One-time Setup

```bash
gtasks login          # Opens browser for Google OAuth2 — required before any other command
gtasks logout         # Revoke stored credentials
```

## Task Lists

```bash
gtasks tasklists view            # List all task lists
gtasks tasklists add "Work"      # Create a new task list
gtasks tasklists rm              # Remove a task list (interactive selector)
```

## Tasks

```bash
# View tasks (default: current task list, sorted by position)
gtasks tasks view
gtasks tasks view -t "Work"              # Specific task list
gtasks tasks view -s due                 # Sort by due date (due|title|position)
gtasks tasks view --show-completed       # Include completed tasks

# Create
gtasks tasks add "Buy groceries"
gtasks tasks add "Report" -t "Work"      # In a specific list

# Complete / undo
gtasks tasks done       # Interactive selector → mark done
gtasks tasks undo       # Mark a completed task as not done

# Update
gtasks tasks update     # Interactive selector → edit title, due date, notes

# Remove
gtasks tasks rm         # Interactive selector → delete task
gtasks tasks clear      # Delete all completed tasks from a list
```

## Common Workflows

**Morning check-in:**
```bash
gtasks tasks view -s due --show-completed
```

**Quick capture:**
```bash
gtasks tasks add "Follow up with Alice by Friday"
```

**Close out the day:**
```bash
gtasks tasks done     # mark off completed items interactively
gtasks tasks clear    # purge completed tasks
```

## Flags Available on Most Commands

| Flag | Short | Description |
|------|-------|-------------|
| `--tasklist` | `-t` | Target a specific task list by name |
| `--sort` | `-s` | Sort order: `due`, `title`, `position` |
| `--show-completed` | | Include completed tasks in output |
