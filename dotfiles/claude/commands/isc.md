---
description: Start ISC-tracked task execution with structured success criteria
argument-hint: Task description (e.g., "Add dark mode to settings page")
allowed-tools: ["Bash(bun run ~/.claude/tools/isc/ISCManager.ts *)"]
---

# ISC Task Execution

You are executing a task using the Ideal State Criteria (ISC) system.
ISC tracks the gap between current state and ideal state through measurable success criteria.

## Task: $ARGUMENTS

## Phase 1: OBSERVE (Define Criteria)

1. Understand the request thoroughly — read relevant code first
2. Create the ISC:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts create -r "$ARGUMENTS"
   ```
3. Define 3-8 success criteria (what does "done" look like?):
   - **EXPLICIT** criteria: directly from the user's request
   - **INFERRED** criteria: derived from context (tech stack, conventions)
   - **IMPLICIT** criteria: universal quality standards (tests pass, no regressions)

   For each criterion:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts add \
     -d "Criterion description" -s EXPLICIT \
     --verify-method test --verify-criteria "How to verify this"
   ```

4. If the request is unclear, run the interview protocol:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts interview -r "$ARGUMENTS"
   ```
   Ask the user the interview questions before proceeding.

## Phase 2: PLAN

1. Set phase:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts phase -p PLAN
   ```
2. Review criteria, add any missing ones discovered during exploration
3. Mark parallel-safe rows and identify dependencies

## Phase 3: BUILD + EXECUTE

1. Set phase:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts phase -p EXECUTE
   ```
2. For each criterion, mark ACTIVE when starting, DONE when complete:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts update --row N --status ACTIVE
   # ... do the work ...
   bun run ~/.claude/tools/isc/ISCManager.ts update --row N --status DONE
   ```
3. If a criterion needs adjustment:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts update --row N --status ADJUSTED --reason "why"
   ```
4. If blocked:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts update --row N --status BLOCKED --reason "why"
   ```
   Ask the user how to proceed.

## Phase 4: VERIFY

1. Set phase:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts phase -p VERIFY
   ```
2. Verify each criterion against its success_criteria:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts verify --row N --result PASS
   ```
3. Show final state:
   ```bash
   bun run ~/.claude/tools/isc/ISCManager.ts show
   bun run ~/.claude/tools/isc/ISCManager.ts summary
   ```

## Phase 5: LEARN (Archive)

If all criteria pass:
```bash
bun run ~/.claude/tools/isc/ISCManager.ts clear
```

## Rules
- Always create ISC BEFORE starting work
- Update status in real-time as you work
- Never skip the VERIFY phase
- If blocked, mark BLOCKED with reason and ask the user
- Show the ISC table after completing all criteria
