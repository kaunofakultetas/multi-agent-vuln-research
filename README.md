# multi-agent-vuln-research

An autonomous, multi-agent vulnerability research framework for [Claude Code](https://claude.ai/download). Seven specialized AI agents — including a black-box fuzzer — discover, analyze, challenge each other's findings, build PoCs, execute them in Docker, and produce graded security reports — without human intervention.

**Core principle: No finding is CONFIRMED unless a PoC runs successfully in Docker AND it survives adversarial review.**

```
  ┌────────────────────────┐
  │   STAGE 0: BASE ENV    │
  │  build target from     │
  │  source → keep running │
  └────────────┬───────────┘
               │
   ══════╤═════╧════════════════
    FOR EACH SUBSYSTEM (8-10):
   ══════╪══════════════════════
               │
     ┌─────────┴─────────┐
     │  HUNTER + FUZZER   │
     │  source + blackbox │
     └─────────┬─────────┘
               │
               ▼
  ┌────────────────────────┐
  │  MITIGATION ANALYST    │
  │  find what protects    │
  └────────────┬───────────┘
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
               │
   ══════╤═════╧════════════════
    AFTER ALL SUBSYSTEMS:
   ══════╪══════════════════════
               │
               ▼
  ┌────────────────────────┐
  │  SENIOR HUNTER PASS    │
  │  cross-component bugs  │
  └────────────┬───────────┘
               │
               ▼
  ┌────────────────────────┐
  │  CHAINING ANALYSIS     │
  │  multi-finding attacks │
  └────────────┬───────────┘
               │
               ▼
        ┌──────────────┐
        │ FINAL REPORT │
        └──────────────┘
```

## Why?

AI-assisted vulnerability research has a honesty problem. A single agent will:
- Flag everything as HIGH/CRITICAL to look thorough
- Write PoCs that "simulate" the vulnerability instead of triggering it
- Skip verification when the analysis "looks convincing enough"
- Rush later parts of the audit to finish faster

multi-agent-vuln-research solves this with four mechanisms:

1. **Adversarial review** — A Challenger agent tries to disprove each finding, then a Defender agent rebuts. The team lead rules on each. Findings that survive are real.
2. **Execution gating** — Every finding gets a PoC run against a shared Docker environment built from the target's own source code. If it doesn't trigger, it's not CONFIRMED. Period.
3. **Source + black-box** — A Hunter reads code while a Fuzzer throws payloads at the running target. Bugs that code review misses, fuzzing catches — and vice versa.
4. **Anti-shortcut enforcement** — Quality gates, completion checklists, and explicit rules prevent the agents from batching, rushing, or skipping stages on later subsystems.

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
2. Split the codebase into 8-10 subsystems — one per attack surface, no grouping
3. Work through each subsystem with the full pipeline (hunter + fuzzer → mitigation analysis → adversarial review → PoC → review → report)
4. Run a senior hunter second pass and cross-subsystem chaining analysis
5. Produce FINDINGS.md, WEAK.md, and PoCs that run against the shared environment

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
# Feed existing findings through the PoC + review pipeline (skip discovery)
/vulnresearch-from-findings ./my-existing-findings.md

# Re-run a specific PoC after manual edits
/vulnresearch-rerun ./pocs/03-ssrf-external-storage
```

## Architecture

### Agents

| Agent | File | Role |
|-------|------|------|
| **Hunter** | `.claude/agents/hunter.md` | Source code review — report ALL potential issues, no self-filtering |
| **Fuzzer** | `.claude/agents/fuzzer.md` | Black-box testing — fuzz the running target without reading source |
| **Analyst** | `.claude/agents/analyst.md` | Mitigation analyst — find what PROTECTS against each finding |
| **Devil's Advocate** | `.claude/agents/devils-advocate.md` | Dual role: Challenger (attack findings) or Defender (rebut challenges) |
| **PoC Builder** | `.claude/agents/poc-builder.md` | Two-phase: recon endpoints, then build exploit |
| **PoC Runner** | `.claude/agents/poc-runner.md` | Execute PoCs, classify failures, skeptical of false PASSes |
| **Report Synthesizer** | `.claude/agents/report-synthesizer.md` | Final graded report with full review transcripts |

### Pipeline (per subsystem)

```
Stage 0   BASE ENVIRONMENT    Build target from source, keep running (once at start)
          ───────────────────────────────────────────────────────────────────────
Stage 1   DISCOVERY            Hunter (source) + Fuzzer (black-box) → merge all findings
Stage 2   MITIGATION ANALYSIS  Analyst finds protections, not bugs (rejects → WEAK.md)
Stage 3   REVIEW ROUND 1       Challenger challenges → Defender rebuts → Team lead rules
Stage 4   PoC ENGINEERING      Phase 1: Recon endpoints. Phase 2: Build exploit
Stage 5   EXECUTION             PoC Runner classifies failures (max 2 retries for POC_BUG)
Stage 6   REVIEW ROUND 2       Challenger + Defender with PoC evidence → final classification
Stage 7   SYNTHESIS             Reports written, FINDINGS.md + WEAK.md updated, quality gate
          ───────────────────────────────────────────────────────────────────────
Stage 8   SENIOR HUNTER PASS   Re-examine critical files, cross-component logic bugs
Stage 9   CHAINING ANALYSIS    Combine WEAK.md + FINDINGS.md findings into attack chains
Stage 10  FINAL REPORT          Executive summary, cleanup pass
```

### Classification

| Classification | Requires | Goes to |
|---------------|----------|---------|
| **CONFIRMED** | PoC PASS + survived both review rounds | FINDINGS.md |
| **PLAUSIBLE** | Strong code evidence but PoC failed (POC_BUG/ENV_MISMATCH), or can't be PoC'd in Docker | FINDINGS.md |
| **REJECTED** | Disproved by evidence (TARGET_NOT_VULNERABLE, DA disproved, full mitigation found) | WEAK.md |

PLAUSIBLE is valuable — crypto flaws, race conditions, and multi-instance bugs can't always be demonstrated in a single Docker container. They belong in FINDINGS.md, not WEAK.md.

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

### Post-subsystem stages

After all subsystems complete:

- **Senior Hunter Pass** — A second-pass hunter re-examines the most critical files across all subsystems with the full findings context. Looks for cross-component logic bugs and multi-step chains that per-subsystem hunters miss.
- **Chaining Analysis** — Reads all of FINDINGS.md + WEAK.md together. Finds combinations of 2+ findings that form higher-impact attack paths. Viable chains go through the PoC pipeline; speculative chains are recorded in WEAK.md.

### WEAK.md — nothing is thrown away

Every rejected finding is preserved with:
- What it looked like and why it was flagged
- Specific evidence for why it was rejected
- Which stage killed it (Analyst triage, Review Round 1, PoC failure, Review Round 2)
- **Chaining potential** — could this combine with another finding to form an attack path?

After Stage 9, WEAK.md also includes a **Potential Chains** section with multi-finding attack paths that were too speculative for FINDINGS.md.

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
- `fuzzer.md` — adjust fuzz payloads, race condition testing, auth boundary checks
- `analyst.md` — tune mitigation analysis, protection assessment criteria
- `devils-advocate.md` — tune severity calibration guide, Challenger/Defender behavior
- `poc-builder.md` — modify Docker templates, retry strategies
- `poc-runner.md` — change failure classification criteria, verification standards
- `report-synthesizer.md` — adjust report format, classification thresholds

**Add target-specific knowledge** — create `.claude/skills/` with:
- Known CVEs in the target's dependencies
- Project-specific threat model
- Previous audit findings to compare against
- Custom Docker setup instructions

## Anti-shortcut enforcement

The #1 failure mode of AI audits is the agent rushing later subsystems. multi-agent-vuln-research prevents this with:

1. **Explicit No Shortcuts Policy** in CLAUDE.md — never combine subsystems, never skip stages, never rush later subsystems
2. **No Hunter filtering** — the Hunter reports ALL findings (LOW/MEDIUM/HIGH confidence). The pipeline filters, not the Hunter.
3. **PLAUSIBLE is valuable** — PoC failure alone doesn't kill a finding. Strong code evidence with a POC_BUG or ENV_MISMATCH failure stays in FINDINGS.md as PLAUSIBLE.
4. **Quality gate per subsystem** — a JSON checklist in `progress.json` must pass before moving on
5. **Compaction instructions** — compact after each subsystem (never mid-subsystem), then resume from disk state

## Token usage

For a typical audit of a medium-sized codebase (~50K-100K lines, 8-10 subsystems):

| Component | Tokens per subsystem | Notes |
|-----------|---------------------|-------|
| Hunter | ~200-400K | Scales with code size |
| Fuzzer | ~100-200K | Black-box payloads per subsystem |
| Mitigation Analyst | ~300-500K | Finds protections per finding |
| Review Round 1 | ~200-400K | Challenger + Defender per finding |
| PoC Recon + Build + Run | ~200-400K per finding | Two-phase build + retries |
| Review Round 2 | ~200-400K | With PoC evidence |
| Report Synthesis | ~100-200K | Per subsystem |

Post-subsystem stages (Senior Hunter + Chaining + Final Report) add ~500K-1M.

**Estimated total: 5-12M tokens for a full audit.** Token-heavy by design — thoroughness is the point.

## Resumability

All state lives on disk:
- `progress.json` — pipeline stage, subsystem status, quality gates, finding states
- `FINDINGS.md` — confirmed and plausible findings index
- `WEAK.md` — all rejected findings
- `base-environment/` — the shared target environment (Docker keeps running)
- `pocs/*/README.md` — individual reports
- `pocs/*/RESULT.md` — execution evidence

To resume after a crash, context compaction, or session restart:
```bash
claude -p "go"
```
It reads `progress.json`, verifies the base environment is still running, and picks up exactly where it left off.

## Limitations

- **Claude's safety guardrails** limit exploit complexity. The PoC Builder creates trigger/crash PoCs, not weaponized exploits. For full exploitation chains, use the PoC output as a starting point for manual development.
- **Single-provider dependency.** The framework runs entirely on Claude. Findings are bounded by Claude's reasoning capabilities on the target language/framework.
- **Docker-based PoCs only.** Vulnerabilities that require bare-metal, specific hardware, or non-containerizable environments won't get PoC verification.
- **Token cost.** A thorough audit is expensive. Budget 5-12M tokens per run.

## Contributing

Contributions welcome. Areas that would have the most impact:

- **Agent definitions** — improved prompts for any of the 7 agents
- **PoC templates** — Docker patterns for common target types (Java, Go, Rust, Node.js)
- **Verification patterns** — better verify.sh check examples for more vulnerability classes
- **Target-specific skills** — `.claude/skills/` packages for popular open-source projects
- **Cross-provider support** — adapting agent definitions for other AI coding tools

## License

MIT

## Acknowledgments

Built on [Claude Code](https://claude.ai/download) Agent Teams by Anthropic. Inspired by the adversarial review methodology used in academic security research, where findings are peer-reviewed before publication.
