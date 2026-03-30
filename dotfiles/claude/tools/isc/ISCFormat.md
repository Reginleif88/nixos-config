# ISC (Ideal State Criteria) Format Reference

The ISC is a living document that tracks the gap between current state and ideal state through measurable success criteria.

## ISC Table Structure

```markdown
## ISC: [Request Summary]

**Effort:** [LEVEL] | **Phase:** [PHASE] | **Iteration:** [N]

| # | What Ideal Looks Like | Source | Verify | Status | [P] |
|---|------------------------|--------|--------|--------|-----|
| 1 | [Criterion 1]          | [SRC]  | [VFY]  | [STAT] | [✓] |
| 2 | [Criterion 2]          | [SRC]  | [VFY]  | [STAT] | [✓] |
```

## Row Fields

### ID (#)
- Sequential number, assigned at creation, never changes

### What Ideal Looks Like
- Description of success criterion
- Should be specific and testable
- Gets refined during BUILD phase

**Evolution:**
```
OBSERVE: "Logout button"
THINK:   "Logout button in navbar"
BUILD:   "Logout button visible in navbar (top-right, matches existing style)"
```

### Source

| Source | Meaning | Example |
|--------|---------|---------|
| **EXPLICIT** | Directly stated by user | "Add a logout button" |
| **INFERRED** | Derived from user context | "Uses TypeScript" (from prefs) |
| **IMPLICIT** | Universal standards | "Tests pass", "No security issues" |

### Status

| Status | Meaning | Set During |
|--------|---------|------------|
| **PENDING** | Not started | Initial state |
| **ACTIVE** | Work in progress | EXECUTE phase |
| **DONE** | Successfully completed | EXECUTE phase |
| **ADJUSTED** | Completed with deviation | EXECUTE or VERIFY |
| **BLOCKED** | Cannot proceed | EXECUTE or VERIFY |

### Parallel [P]
- ✓ = Can run in parallel with other rows
- (empty) = Must run sequentially
- Set during PLAN phase

## JSON Storage Format

ISC is stored at `~/.claude/MEMORY/Work/current-isc.json`:

```json
{
  "request": "Add logout button to navbar",
  "effort": "STANDARD",
  "created": "2024-01-15T10:30:00Z",
  "lastModified": "2024-01-15T11:45:00Z",
  "phase": "EXECUTE",
  "iteration": 1,
  "rows": [
    {
      "id": 1,
      "description": "Logout button visible in navbar",
      "source": "EXPLICIT",
      "status": "DONE",
      "parallel": true,
      "timestamp": "2024-01-15T10:30:00Z"
    }
  ],
  "log": [
    "[2024-01-15T10:30:00Z] ISC created for: Add logout button",
    "[2024-01-15T11:00:00Z] Row 1: PENDING → ACTIVE",
    "[2024-01-15T11:30:00Z] Row 1: ACTIVE → DONE"
  ]
}
```

## ISC Lifecycle

```
CREATE (OBSERVE)
    ↓
COMPLETE (THINK) - add missing rows
    ↓
ORDER (PLAN) - set parallel, sequence
    ↓
REFINE (BUILD) - make testable
    ↓
STATUS CHANGES (EXECUTE) - PENDING → ACTIVE → DONE
    ↓
VERIFY RESULTS (VERIFY) - PASS/ADJUSTED/BLOCKED
    ↓
ARCHIVE (LEARN) - save and clear
```

## CLI Commands

```bash
ISC=~/.claude/tools/isc/ISCManager.ts

# Create new ISC
bun run $ISC create --request "Add feature X" --effort STANDARD

# Add rows (with optional verification)
bun run $ISC add -d "Feature works" -s EXPLICIT --verify-method browser --verify-criteria "Feature visible"
bun run $ISC add -d "Uses TypeScript" -s INFERRED
bun run $ISC add -d "Tests pass" -s IMPLICIT

# Update status
bun run $ISC update --row 1 --status ACTIVE
bun run $ISC update --row 1 --status DONE
bun run $ISC update --row 2 --status BLOCKED --reason "API unavailable"

# Set verification result
bun run $ISC verify --row 1 --result PASS
bun run $ISC verify --row 2 --result ADJUSTED --reason "250ms vs 200ms"

# Change phase
bun run $ISC phase -p EXECUTE

# View ISC
bun run $ISC show
bun run $ISC show -o json

# View log / summary
bun run $ISC log
bun run $ISC summary

# Archive and clear
bun run $ISC clear
```

## Best Practices

### Row Descriptions
- **Specific** over vague: "Button top-right" not "Button somewhere"
- **Testable**: Must be verifiable somehow
- **Outcome-focused**: "User sees X" not "Code does Y"

### Source Assignment
- When in doubt, use INFERRED
- EXPLICIT only for direct quotes from request
- IMPLICIT for universal quality standards

### Status Management
- Update immediately when status changes
- Never skip ACTIVE - always mark work in progress
- Always include reason for BLOCKED/ADJUSTED

### Parallelization
- Default to parallel unless clear dependency
- Mark [P] only during PLAN phase
- Don't parallelize if rows touch same files
