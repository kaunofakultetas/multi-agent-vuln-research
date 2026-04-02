# multi-agent-vuln-research

An autonomous, multi-agent vulnerability research framework for [Claude Code](https://claude.ai/download). Six specialized AI agents discover, analyze, debate, build PoCs, execute them in Docker, and produce graded security reports — without human intervention.

**Core principle: No finding is CONFIRMED unless a PoC runs successfully in Docker AND it survives adversarial review.**

```
  ┌────────────────────────┐
  │   STAGE 0: BASE ENV    │
  │  build target from     │
  │  source → keep running │
  └────────────┬───────────┘
               │
   ══════╤═════╧════════════
    FOR EACH SUBSYSTEM:
   ══════╪══════════════════
               │
        ┌──────┴───────┐
        │    HUNTER    │
        │   discover   │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │   ANALYST    │
        │    verify    │
        └──────┬───────┘
               │
               ▼
  ┌────────────────────────┐
  │   ADVERSARIAL REVIEW   │
  │   "Is this real?"      │
  │ Challenger → Defender  │
  │ → Team lead rules      │
  └────────────┬───────────┘
               │
               ▼
  ┌────────────────────────┐
  │  PoC BUILD + EXECUTE   │
  │  recon first, then     │
  │  exploit → retry ×2    │
  └────────────┬───────────┘
               │
               ▼
  ┌────────────────────────┐
  │   ADVERSARIAL REVIEW   │
  │  "Correctly rated?"    │
  │  with PoC evidence     │
  └────────────┬───────────┘
               │
               ▼
        ┌──────────────┐
        │  SYNTHESIZER │
        │ final report │
        └──────────────┘
```

## Why?

AI-assisted vulnerability research has a honesty problem. A single agent will:
- Flag everything as HIGH/CRITICAL to look thorough
- Write PoCs that "simulate" the vulnerability instead of triggering it
- Skip verification when the analysis "looks convincing enough"
- Rush later parts of the audit to finish faster

multi-agent-vuln-research solves this with three mechanisms:

1. **Adversarial review** — A Challenger agent tries to disprove each finding, then a Defender agent rebuts. The team lead rules on each. Findings that survive are real.
2. **Execution gating** — Every finding gets a PoC run against a shared Docker environment built from the target's own source code. If it doesn't trigger, it's not CONFIRMED. Period.
3. **Anti-shortcut enforcement** — Quality gates, completion checklists, and explicit rules prevent the agents from batching, rushing, or skipping stages on later subsystems.

## What you get

```
├── FINDINGS.md                         # Summary index with links to each report
├── WEAK.md                             # Rejected findings preserved for chain analysis
├── progress.json                       # Full pipeline state (resumable)
├── base-environment/
│   ├── docker-compose.yml              # Shared persistent target environment
│   ├── Dockerfile                      # Built FROM the source code being analyzed
│   ├── setup.sh                        # One-time target initialization
│   ├── lib.sh                          # Shared helper functions for PoCs
│   └── .env                            # Shared config (ports, passwords, etc.)
├── pocs/
│   ├── 01-share-password-hash-leak/
│   │   ├── README.md                   # Full report: root cause, review log, evidence, fix
│   │   ├── exploit.py                  # Working exploit
│   │   ├── verify.sh                   # Runs exploit against shared env, verifies, captures evidence
│   │   └── RESULT.md                   # Execution evidence (PASS/FAIL)
│   ├── 02-csrf-header-bypass/
│   │   └── ...
```

The base environment stays running for the entire audit. PoCs run against it:
```bash
cd base-environment && docker compose up -d --wait
cd ../pocs/01-share-password-hash-leak
bash verify.sh   # runs exploit against shared env, verifies, captures evidence
```

## Requirements

- [Claude Code](https://claude.ai/download) with an active subscription (Pro/Team/Enterprise)
- Docker and Docker Compose
- Python 3, bash, curl
- A machine where you're comfortable running untrusted Docker containers (sandbox/VM recommended)

## Installation

```bash
git clone https://github.com/kaunofakultetas/multi-agent-vuln-research.git
cd multi-agent-vuln-research
```

## Usage

### 1. Set up your target

Copy or clone the target source code into the project directory:

```bash
# Example: auditing Nextcloud
git clone https://github.com/nextcloud/server.git
```

### 2. Run

```bash
claude -p "go"
```


That's it. The agents will:
1. Look around, identify the project, and build a base environment from the target's source code
2. Group the codebase into 5-7 subsystems by attack surface
3. Work through each subsystem with the full pipeline (discovery → analysis → adversarial review → PoC → review → report)
4. Produce FINDINGS.md, WEAK.md, and PoCs that run against the shared environment

### 3. Walk away

The pipeline is designed for long-running unattended sessions. State is written to disk continuously via `progress.json`, so if the session crashes or compacts, it resumes where it left off.

Run in screen/tmux for SSH resilience:
```bash
screen -S vulnresearch
claude
# type: go
# detach: Ctrl+A, D
# reattach later: screen -r vulnresearch
```

Headless mode:
```bash
claude -p "go" 2>&1 | tee run.log
```

### 4. Review results

After the pipeline finishes, open a new interactive session in the same directory:

```bash
claude
```

Ask anything:
```
summarize the findings
explain the adversarial review on finding 03
are there any chains between weak findings?
why did the PoC for 05 fail?
```

### Alternative entry points

```
# Feed existing findings through the PoC + debate pipeline (skip discovery)
/vulnresearch-from-findings ./my-existing-findings.md

# Re-run a specific PoC after manual edits
/vulnresearch-rerun ./pocs/03-ssrf-external-storage
```

## Architecture

### Agents

| Agent | File | Role |
|-------|------|------|
| **Hunter** | `.claude/agents/hunter.md` | Offensive discovery — find every potential issue |
| **Analyst** | `.claude/agents/analyst.md` | Deep root-cause analysis, reachability, PoC blueprints |
| **Devil's Advocate** | `.claude/agents/devils-advocate.md` | Adversarial critic — try to disprove every finding |
| **PoC Builder** | `.claude/agents/poc-builder.md` | Create runnable exploit + Docker environment per finding |
| **PoC Runner** | `.claude/agents/poc-runner.md` | Execute PoCs, capture evidence, skeptical of false PASSes |
| **Report Synthesizer** | `.claude/agents/report-synthesizer.md` | Final graded report with full debate transcripts |

### Pipeline (per subsystem)

```
Stage 0  BASE ENVIRONMENT   Build target from source, keep running (once at start)
         ─────────────────────────────────────────────────────────────────────
Stage 1  DISCOVERY           Hunter scans subsystem, self-filters LOW to WEAK.md
Stage 2  ANALYSIS            Analyst verifies root cause + reachability (rejects → WEAK.md)
Stage 3  REVIEW ROUND 1      Challenger challenges → Defender rebuts → Team lead rules
Stage 4  PoC ENGINEERING     Phase 1: Recon endpoints. Phase 2: Build exploit
Stage 5  EXECUTION            PoC Runner runs against shared env (max 2 retries for POC_BUG)
Stage 6  REVIEW ROUND 2      Challenger + Defender with PoC evidence → final classification
Stage 7  SYNTHESIS            Reports written, FINDINGS.md + WEAK.md updated, quality gate
```

### Classification

| Classification | Requires |
|---------------|----------|
| **CONFIRMED** | PoC PASS + survived both review rounds |
| **PLAUSIBLE** | Strong analysis but PoC failed (POC_BUG after retries) or ENV_MISMATCH |
| **REJECTED** | Disproved by evidence → logged in WEAK.md for chaining review |

### PoC failure classification

Not all PoC failures are equal:

| Failure type | Meaning | Counts against finding? |
|-------------|---------|------------------------|
| `TARGET_NOT_VULNERABLE` | Server correctly blocked the attack | Yes |
| `POC_BUG` | Script error, wrong endpoint, bash syntax | No — Builder fixes, retry |
| `ENV_MISMATCH` | Source code differs from running target | No — flagged for manual review |

### Adversarial review

Sequential challenge/rebuttal with separate agents (not simultaneous messaging):

```
REVIEW ROUND 1 — "Is this real?"
  Challenger:  "validate_input() at line 298 caps the buffer to 256 bytes"
  Defender:    "validate_input() only runs on the v2 path. The v1 path skips it"
  Team lead:   Defender refuted the challenge. Finding survives.

REVIEW ROUND 2 — "Is this correctly rated?"
  Challenger:  "PoC only proved a crash, not code execution. Requires non-default config"
  Defender:    "Fair on crash vs RCE. But the config is common in enterprise deployments"
  Team lead:   Mixed — downgrade from CRITICAL to HIGH. Real DoS, plausible RCE.
```

### WEAK.md — nothing is thrown away

Every rejected finding is preserved with:
- What it looked like and why it was flagged
- Specific evidence for why it was rejected
- Which stage killed it and which agent's argument won
- **Chaining potential** — could this combine with another finding to form an attack path?

## Configuration

### Settings

`.claude/settings.json` enables agent teams and allows all tools:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash", "Read", "Edit", "MultiEdit", "Write",
      "Glob", "Grep", "LS", "Task", "Agent",
      "WebFetch", "WebSearch"
    ]
  },
  "sandbox": {
    "enabled": false
  }
}
```

### Customization

**Adjust agent behavior** — edit the agent definitions in `.claude/agents/`:
- `hunter.md` — change discovery depth, add target-specific patterns
- `analyst.md` — adjust reachability analysis, CVSS scoring approach
- `devils-advocate.md` — tune severity calibration guide, skepticism level
- `poc-builder.md` — modify Docker templates, retry strategies
- `poc-runner.md` — change verification standards
- `report-synthesizer.md` — adjust report format, classification thresholds

**Add target-specific knowledge** — create `.claude/skills/` with:
- Known CVEs in the target's dependencies
- Project-specific threat model
- Previous audit findings to compare against
- Custom Docker setup instructions

## Anti-shortcut enforcement

The #1 failure mode of AI audits is the agent rushing later subsystems. multi-agent-vuln-research prevents this with:

1. **Explicit No Shortcuts Policy** in CLAUDE.md with ❌/✅ examples
2. **Quality gate per subsystem** — a JSON checklist written to `progress.json` that must pass before moving on
3. **Debate exchange minimums** — at least 3 exchanges per finding per round, tracked in the checklist
4. **Compaction instructions** — when context fills up, the agent is told to compact and resume, not rush to finish

## Token usage

For a typical audit of a medium-sized codebase (~50K-100K lines, ~10 subsystems):

| Component | Tokens per subsystem | Notes |
|-----------|---------------------|-------|
| Hunter | ~200-400K | Scales with code size |
| Analyst | ~300-500K | Deep analysis per finding |
| Debate Round 1 | ~200-400K | 3-4 exchanges × findings |
| PoC Build + Run | ~200-400K per finding | Includes retries |
| Debate Round 2 | ~200-400K | With PoC evidence |
| Report Synthesis | ~100-200K | Per subsystem |

**Estimated total: 3-8M tokens for a full audit.** Token-heavy by design — thoroughness is the point.

## Resumability

All state lives on disk:
- `progress.json` — pipeline stage, subsystem status, quality gates, finding states
- `FINDINGS.md` — confirmed and plausible findings index
- `WEAK.md` — all rejected findings
- `pocs/*/README.md` — individual reports
- `pocs/*/RESULT.md` — execution evidence

To resume after a crash, context compaction, or session restart:
```bash
claude
```
```
go
```
It reads `progress.json` and picks up exactly where it left off.

## Limitations

- **Claude's safety guardrails** limit exploit complexity. The PoC Builder creates trigger/crash PoCs, not weaponized exploits. For full exploitation chains, use the PoC output as a starting point for manual development.
- **Single-provider dependency.** The framework runs entirely on Claude. Findings are bounded by Claude's reasoning capabilities on the target language/framework.
- **Docker-based PoCs only.** Vulnerabilities that require bare-metal, specific hardware, or non-containerizable environments won't get PoC verification.
- **Token cost.** A thorough audit is expensive. Budget 3-8M tokens per run.

## Contributing

Contributions welcome. Areas that would have the most impact:

- **Agent definitions** — improved prompts for any of the 6 agents
- **PoC templates** — Docker patterns for common target types (Java, Go, Rust, Node.js)
- **Verification patterns** — better verify.sh check examples for more vulnerability classes
- **Target-specific skills** — `.claude/skills/` packages for popular open-source projects
- **Cross-provider support** — adapting agent definitions for other AI coding tools

## License

MIT

## Acknowledgments

Built on [Claude Code](https://claude.ai/download) Agent Teams by Anthropic. Inspired by the adversarial review methodology used in academic security research, where findings are peer-reviewed before publication.
