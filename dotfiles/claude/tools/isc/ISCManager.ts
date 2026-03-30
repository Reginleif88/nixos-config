#!/usr/bin/env bun

/**
 * ISCManager - Manage Ideal State Criteria tables
 *
 * Tracks the gap between current state and ideal state through
 * measurable success criteria with verification methods.
 *
 * Usage:
 *   bun run ISCManager.ts create --request "Add dark mode"
 *   bun run ISCManager.ts add --description "Tests pass" --source IMPLICIT
 *   bun run ISCManager.ts update --row 1 --status DONE
 *   bun run ISCManager.ts show
 *   bun run ISCManager.ts verify --row 1 --result PASS
 */

import { parseArgs } from "util";
import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync } from "fs";

type Source = "EXPLICIT" | "INFERRED" | "IMPLICIT";
type Status = "PENDING" | "ACTIVE" | "DONE" | "ADJUSTED" | "BLOCKED";
type VerifyResult = "PASS" | "ADJUSTED" | "BLOCKED";
type VerifyMethod = "browser" | "test" | "grep" | "api" | "lint" | "manual" | "agent" | "inferred";

interface Verification {
  method: VerifyMethod;
  command?: string;
  success_criteria: string;
  passed?: boolean;
  verified_at?: string;
}

interface ISCRow {
  id: number;
  description: string;
  source: Source;
  status: Status;
  parallel: boolean;
  result?: string;
  adjustedReason?: string;
  blockedReason?: string;
  verifyResult?: VerifyResult;
  timestamp: string;
  verification?: Verification;
}

interface ISCTable {
  request: string;
  effort: string;
  created: string;
  lastModified: string;
  phase: string;
  iteration: number;
  rows: ISCRow[];
  log: string[];
}

const HOME = process.env.HOME || "~";
const ISC_DIR = `${HOME}/.claude/MEMORY/Work`;
const CURRENT_ISC_PATH = `${ISC_DIR}/current-isc.json`;

function ensureDir() {
  if (!existsSync(ISC_DIR)) {
    mkdirSync(ISC_DIR, { recursive: true });
  }
}

function loadISC(): ISCTable | null {
  if (!existsSync(CURRENT_ISC_PATH)) {
    return null;
  }
  const content = readFileSync(CURRENT_ISC_PATH, "utf-8");
  if (!content.trim()) return null;
  return JSON.parse(content) as ISCTable;
}

function saveISC(isc: ISCTable) {
  ensureDir();
  isc.lastModified = new Date().toISOString();
  writeFileSync(CURRENT_ISC_PATH, JSON.stringify(isc, null, 2));
}

function createISC(request: string, effort: string): ISCTable {
  const isc: ISCTable = {
    request,
    effort,
    created: new Date().toISOString(),
    lastModified: new Date().toISOString(),
    phase: "OBSERVE",
    iteration: 1,
    rows: [],
    log: [`[${new Date().toISOString()}] ISC created for: ${request}`],
  };
  saveISC(isc);
  return isc;
}

function addRow(
  isc: ISCTable,
  description: string,
  source: Source,
  parallel: boolean = true,
  verification?: { method: VerifyMethod; command?: string; criteria: string }
): ISCRow {
  const row: ISCRow = {
    id: isc.rows.length + 1,
    description,
    source,
    status: "PENDING",
    parallel,
    timestamp: new Date().toISOString(),
  };

  if (verification) {
    row.verification = {
      method: verification.method,
      command: verification.command,
      success_criteria: verification.criteria,
    };
  }

  isc.rows.push(row);
  const verifyNote = verification ? ` [verify: ${verification.method}]` : "";
  isc.log.push(
    `[${new Date().toISOString()}] Added row ${row.id}: ${description} (${source})${verifyNote}`
  );
  saveISC(isc);
  return row;
}

function updateRowStatus(
  isc: ISCTable,
  rowId: number,
  status: Status,
  reason?: string
): ISCRow | null {
  const row = isc.rows.find((r) => r.id === rowId);
  if (!row) return null;

  const oldStatus = row.status;
  row.status = status;

  if (status === "ADJUSTED" && reason) {
    row.adjustedReason = reason;
  }
  if (status === "BLOCKED" && reason) {
    row.blockedReason = reason;
  }

  isc.log.push(
    `[${new Date().toISOString()}] Row ${rowId}: ${oldStatus} → ${status}${reason ? ` (${reason})` : ""}`
  );
  saveISC(isc);
  return row;
}

function setVerifyResult(
  isc: ISCTable,
  rowId: number,
  result: VerifyResult,
  reason?: string
): ISCRow | null {
  const row = isc.rows.find((r) => r.id === rowId);
  if (!row) return null;

  row.verifyResult = result;
  if (result === "ADJUSTED" && reason) {
    row.adjustedReason = reason;
    row.status = "ADJUSTED";
  }
  if (result === "BLOCKED" && reason) {
    row.blockedReason = reason;
    row.status = "BLOCKED";
  }
  if (result === "PASS") {
    row.status = "DONE";
  }

  if (row.verification) {
    row.verification.passed = result === "PASS";
    row.verification.verified_at = new Date().toISOString();
  }

  isc.log.push(
    `[${new Date().toISOString()}] Verify row ${rowId}: ${result}${reason ? ` (${reason})` : ""}`
  );
  saveISC(isc);
  return row;
}

function setPhase(isc: ISCTable, phase: string) {
  const oldPhase = isc.phase;
  isc.phase = phase;
  isc.log.push(`[${new Date().toISOString()}] Phase: ${oldPhase} → ${phase}`);
  saveISC(isc);
}

function incrementIteration(isc: ISCTable) {
  isc.iteration++;
  isc.log.push(
    `[${new Date().toISOString()}] Starting iteration ${isc.iteration}`
  );
  saveISC(isc);
}

const VALID_PHASES = ["OBSERVE", "THINK", "PLAN", "BUILD", "EXECUTE", "VERIFY", "LEARN"] as const;

const VERIFY_ICONS: Record<VerifyMethod, string> = {
  browser: "🌐",
  test: "🧪",
  grep: "🔎",
  api: "📡",
  lint: "✨",
  manual: "👁️",
  agent: "🤖",
  inferred: "💫",
};

const STATUS_EMOJI: Record<Status, string> = {
  PENDING: "⏳",
  ACTIVE: "🔄",
  DONE: "✅",
  ADJUSTED: "🔧",
  BLOCKED: "🚫",
};

function formatTable(isc: ISCTable): string {
  let output = `## 🎯 IDEAL STATE CRITERIA\n\n`;
  output += `**Request:** ${isc.request}\n`;
  output += `**Effort:** ${isc.effort} | **Phase:** ${isc.phase} | **Iteration:** ${isc.iteration}\n\n`;
  output += `| # | What Ideal Looks Like | Source | Verify | Status | [P] |\n`;
  output += `|---|----------------------|--------|--------|--------|-----|\n`;

  for (const row of isc.rows) {
    let desc = row.description;
    if (row.adjustedReason) {
      desc += ` *(adjusted: ${row.adjustedReason})*`;
    }
    if (row.blockedReason) {
      desc += ` *(blocked: ${row.blockedReason})*`;
    }

    let verifyDisplay = "—";
    if (row.verification) {
      const icon = VERIFY_ICONS[row.verification.method] || "❓";
      verifyDisplay = `${icon} ${row.verification.method}`;
      if (row.verification.passed !== undefined) {
        verifyDisplay += row.verification.passed ? " ✅" : " ❌";
      }
    }

    const statusDisplay = `${STATUS_EMOJI[row.status]} ${row.status}`;
    const parallelDisplay = row.parallel ? "✓" : "";

    output += `| ${row.id} | ${desc} | ${row.source} | ${verifyDisplay} | ${statusDisplay} | ${parallelDisplay} |\n`;
  }

  output += `\n**Verify:** 🌐 browser | 🧪 test | 🔎 grep | 📡 api | ✨ lint | 👁️ manual | 🤖 agent | 💫 inferred\n`;

  return output;
}

function formatLog(isc: ISCTable): string {
  let output = `## Evolution Log\n\n`;
  for (const entry of isc.log) {
    output += `${entry}\n`;
  }
  return output;
}

function getSummary(isc: ISCTable): {
  total: number;
  pending: number;
  active: number;
  done: number;
  adjusted: number;
  blocked: number;
  parallelizable: number;
} {
  return {
    total: isc.rows.length,
    pending: isc.rows.filter((r) => r.status === "PENDING").length,
    active: isc.rows.filter((r) => r.status === "ACTIVE").length,
    done: isc.rows.filter((r) => r.status === "DONE").length,
    adjusted: isc.rows.filter((r) => r.status === "ADJUSTED").length,
    blocked: isc.rows.filter((r) => r.status === "BLOCKED").length,
    parallelizable: isc.rows.filter((r) => r.parallel && r.status === "PENDING")
      .length,
  };
}

const INTERVIEW_QUESTIONS = [
  "What does success look like when this is done?",
  "Who will use this and what will they do with it?",
  "What would make you show this to your friends?",
  "What existing thing is this most similar to?",
  "What should this definitely NOT do?",
];

async function main() {
  const { values, positionals } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      request: { type: "string", short: "r" },
      effort: { type: "string", short: "e", default: "STANDARD" },
      description: { type: "string", short: "d" },
      source: { type: "string", short: "s" },
      row: { type: "string" },
      status: { type: "string" },
      result: { type: "string" },
      reason: { type: "string" },
      phase: { type: "string", short: "p" },
      parallel: { type: "boolean", default: true },
      "no-parallel": { type: "boolean", default: false },
      output: { type: "string", short: "o", default: "text" },
      help: { type: "boolean", short: "h" },
      "verify-method": { type: "string" },
      "verify-criteria": { type: "string" },
      "verify-command": { type: "string" },
    },
    allowPositionals: true,
  });

  const command = positionals[0];

  if (values.help || !command) {
    console.log(`
ISCManager - Manage Ideal State Criteria tables

USAGE:
  bun run ISCManager.ts <command> [options]

COMMANDS:
  create        Create new ISC table
  add           Add a row to current ISC (with optional verification)
  update        Update row status
  verify        Set verification result for a row
  phase         Set current phase
  iterate       Increment iteration counter
  show          Display current ISC table
  log           Show evolution log
  summary       Show status summary
  clear         Archive and clear current ISC
  interview     Output interview questions for unclear request

OPTIONS:
  -r, --request <text>       Request text (for create)
  -e, --effort <level>       Effort level (for create, default: STANDARD)
  -d, --description <text>   Row description (for add)
  -s, --source <type>        Source: EXPLICIT, INFERRED, IMPLICIT
  --row <id>                 Row ID (for update/verify)
  --status <status>          Status: PENDING, ACTIVE, DONE, ADJUSTED, BLOCKED
  --result <result>          Verify result: PASS, ADJUSTED, BLOCKED
  --reason <text>            Reason for adjustment/block
  -p, --phase <phase>        Phase name (for phase command)
  --parallel                 Row can run in parallel (default: true)
  --no-parallel              Row must run sequentially
  -o, --output <fmt>         Output format: text, json, markdown
  -h, --help                 Show this help
  --verify-method <method>   Verify method: browser, test, grep, api, lint, manual, agent, inferred
  --verify-criteria <text>   Success criteria for verification
  --verify-command <cmd>     Optional command to run for verification

EXAMPLES:
  bun run ISCManager.ts create -r "Add dark mode to settings"
  bun run ISCManager.ts add -d "Toggle works" -s EXPLICIT --verify-method browser --verify-criteria "Toggle visible"
  bun run ISCManager.ts add -d "Tests pass" -s IMPLICIT
  bun run ISCManager.ts update --row 1 --status ACTIVE
  bun run ISCManager.ts update --row 1 --status DONE
  bun run ISCManager.ts verify --row 1 --result PASS
  bun run ISCManager.ts show
`);
    return;
  }

  switch (command) {
    case "create": {
      if (!values.request) {
        console.error("Error: --request is required for create");
        process.exit(1);
      }
      const isc = createISC(values.request, values.effort || "STANDARD");
      console.log(`ISC created for: ${values.request}`);
      console.log(`Effort: ${isc.effort}`);
      console.log(`Saved to: ${CURRENT_ISC_PATH}`);
      break;
    }

    case "add": {
      const isc = loadISC();
      if (!isc) {
        console.error("Error: No current ISC. Use 'create' first.");
        process.exit(1);
      }
      if (!values.description) {
        console.error("Error: --description is required for add");
        process.exit(1);
      }
      const source = (values.source?.toUpperCase() || "EXPLICIT") as Source;
      if (!["EXPLICIT", "INFERRED", "IMPLICIT"].includes(source)) {
        console.error("Error: --source must be EXPLICIT, INFERRED, or IMPLICIT");
        process.exit(1);
      }

      let verification: { method: VerifyMethod; command?: string; criteria: string } | undefined;
      if (values["verify-method"]) {
        const method = values["verify-method"] as VerifyMethod;
        const validMethods = ["browser", "test", "grep", "api", "lint", "manual", "agent", "inferred"];
        if (!validMethods.includes(method)) {
          console.error(`Error: --verify-method must be one of: ${validMethods.join(", ")}`);
          process.exit(1);
        }
        if (!values["verify-criteria"]) {
          console.error("Error: --verify-criteria is required when using --verify-method");
          process.exit(1);
        }
        verification = {
          method,
          criteria: values["verify-criteria"],
          command: values["verify-command"],
        };
      }

      const isParallel = values["no-parallel"] ? false : values.parallel;
      const row = addRow(isc, values.description, source, isParallel, verification);
      console.log(`Added row ${row.id}: ${row.description} (${row.source})`);
      if (verification) {
        console.log(`  Verification: ${verification.method} - ${verification.criteria}`);
      }
      break;
    }

    case "update": {
      const isc = loadISC();
      if (!isc) {
        console.error("Error: No current ISC. Use 'create' first.");
        process.exit(1);
      }
      if (!values.row) {
        console.error("Error: --row is required for update");
        process.exit(1);
      }
      if (!values.status) {
        console.error("Error: --status is required for update");
        process.exit(1);
      }
      const status = values.status.toUpperCase() as Status;
      if (!["PENDING", "ACTIVE", "DONE", "ADJUSTED", "BLOCKED"].includes(status)) {
        console.error("Error: Invalid status. Must be: PENDING, ACTIVE, DONE, ADJUSTED, BLOCKED");
        process.exit(1);
      }
      const row = updateRowStatus(isc, parseInt(values.row), status, values.reason);
      if (!row) {
        console.error(`Error: Row ${values.row} not found`);
        process.exit(1);
      }
      console.log(`Row ${row.id}: ${row.status}`);
      break;
    }

    case "verify": {
      const isc = loadISC();
      if (!isc) {
        console.error("Error: No current ISC.");
        process.exit(1);
      }
      if (!values.row || !values.result) {
        console.error("Error: --row and --result are required for verify");
        process.exit(1);
      }
      const result = values.result.toUpperCase() as VerifyResult;
      if (!["PASS", "ADJUSTED", "BLOCKED"].includes(result)) {
        console.error("Error: --result must be PASS, ADJUSTED, or BLOCKED");
        process.exit(1);
      }
      const row = setVerifyResult(isc, parseInt(values.row), result, values.reason);
      if (!row) {
        console.error(`Error: Row ${values.row} not found`);
        process.exit(1);
      }
      console.log(`Row ${row.id} verified: ${result}`);
      break;
    }

    case "phase": {
      const isc = loadISC();
      if (!isc) {
        console.error("Error: No current ISC.");
        process.exit(1);
      }
      if (!values.phase) {
        console.error("Error: --phase is required");
        process.exit(1);
      }
      const phaseValue = values.phase.toUpperCase();
      if (!VALID_PHASES.includes(phaseValue as any)) {
        console.error(`Error: Invalid phase. Must be: ${VALID_PHASES.join(", ")}`);
        process.exit(1);
      }
      setPhase(isc, phaseValue);
      console.log(`Phase set to: ${isc.phase}`);
      break;
    }

    case "iterate": {
      const isc = loadISC();
      if (!isc) {
        console.error("Error: No current ISC.");
        process.exit(1);
      }
      incrementIteration(isc);
      console.log(`Now on iteration: ${isc.iteration}`);
      break;
    }

    case "show": {
      const isc = loadISC();
      if (!isc) {
        console.error("No current ISC.");
        process.exit(1);
      }
      if (values.output === "json") {
        console.log(JSON.stringify(isc, null, 2));
      } else {
        console.log(formatTable(isc));
      }
      break;
    }

    case "log": {
      const isc = loadISC();
      if (!isc) {
        console.error("No current ISC.");
        process.exit(1);
      }
      console.log(formatLog(isc));
      break;
    }

    case "summary": {
      const isc = loadISC();
      if (!isc) {
        console.error("No current ISC.");
        process.exit(1);
      }
      const summary = getSummary(isc);
      if (values.output === "json") {
        console.log(JSON.stringify({ ...summary, phase: isc.phase, iteration: isc.iteration }, null, 2));
      } else {
        console.log(`ISC Summary: ${isc.request}`);
        console.log(`Phase: ${isc.phase} | Iteration: ${isc.iteration}`);
        console.log(`Total: ${summary.total} | Pending: ${summary.pending} | Active: ${summary.active}`);
        console.log(`Done: ${summary.done} | Adjusted: ${summary.adjusted} | Blocked: ${summary.blocked}`);
        console.log(`Parallelizable: ${summary.parallelizable}`);
      }
      break;
    }

    case "clear": {
      if (existsSync(CURRENT_ISC_PATH)) {
        const isc = loadISC();
        if (isc) {
          const archivePath = `${ISC_DIR}/archive-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
          writeFileSync(archivePath, JSON.stringify(isc, null, 2));
          console.log(`Archived to: ${archivePath}`);
        }
        unlinkSync(CURRENT_ISC_PATH);
        console.log("Current ISC cleared.");
      } else {
        console.log("No current ISC to clear.");
      }
      break;
    }

    case "interview": {
      console.log("═══════════════════════════════════════════════════════════");
      console.log("  INTERVIEW PROTOCOL - Clarify Ideal State");
      console.log("═══════════════════════════════════════════════════════════");
      if (values.request) {
        console.log(`\nRequest: "${values.request}"\n`);
      }
      console.log("When ideal state is unclear, ask these questions:\n");
      for (let i = 0; i < INTERVIEW_QUESTIONS.length; i++) {
        console.log(`  ${i + 1}. ${INTERVIEW_QUESTIONS[i]}`);
      }
      console.log("\n───────────────────────────────────────────────────────────");
      console.log("Use answers to create clear, testable ISC rows.");
      console.log("═══════════════════════════════════════════════════════════");
      break;
    }

    default:
      console.error(`Unknown command: ${command}`);
      console.error("Use --help for usage information");
      process.exit(1);
  }
}

main().catch(console.error);
