#!/bin/bash
set -euo pipefail

mkdir -p logs

# ============================================================
# Throwaway VM: give Claude unrestricted access.
# --dangerously-skip-permissions bypasses ALL permission checks
# (docker, network, bash) so headless `claude -p` never stalls on
# an un-answerable approval prompt. Running as root normally blocks
# that flag; IS_SANDBOX=1 lifts the root guard.
# ============================================================
export IS_SANDBOX=1


# ============================================================
# Helper function to run Claude
# ============================================================
run_claude() {
    local label="$1"
    local prompt="$2"
    local logfile="logs/${label}-$(date +%Y%m%d-%H%M%S).log"

    echo ""
    echo "============================================================"
    echo "  $label — $(date)"
    echo "============================================================"
    echo "=== $label — $(date) ===" >> "$logfile"
    
    # Stream text live (not raw JSON) with a minimal parser.
    claude -p "$prompt" --model 'claude-opus-4-6[1m]' --dangerously-skip-permissions --output-format stream-json --verbose --include-partial-messages --effort max < /dev/null 2>&1 \
        | jq --unbuffered -Rrj '
            (fromjson? // empty)
            | if .type == "stream_event" and .event.type == "content_block_delta" then
                (.event.delta.text // "")
              elif .type == "assistant" then
                (
                  .message.content[]?
                  | select(.type == "tool_use")
                  | "\n  [" + (.name // "tool") + "] "
                    + (.input.command // .input.file_path // .input.pattern // .input.path // "")
                    + "\n"
                )
              elif .type == "result" then
                "\n--- Session ended ---\n"
              else
                empty
              end
        ' \
        | tee -a "$logfile"
}





# ============================================================
# STAGE 0: Initialize environment, identify subsystems
# ============================================================
run_claude "stage0-init" "
Stage 0. Look around the project: read directory structure, README, Dockerfiles,
docker-compose files, package.json, Makefile — whatever exists. Figure out the
project, language, source location, dependencies. Build the shared base
environment per CLAUDE.md Stage 0. Identify 8-10 subsystems and write them to
progress.json. Do NOT start testing subsystems yet — only initialize and identify.
"

if [ ! -f progress.json ]; then
    echo "ERROR: progress.json was not created by Stage 0. Aborting."
    exit 1
fi

# ============================================================
# STAGES 1-7: Process each subsystem
#
# Each subsystem runs in ONE long-lived claude session that must keep its turn
# alive across all 7 stages (see CLAUDE.md "Headless Execution — NEVER Yield
# Mid-Subsystem"). As a SAFETY NET only, if that session dies anyway (crash /
# OOM / context limit), we re-invoke it: a fresh session reads progress.json +
# FINDINGS.md + WEAK.md and resumes from the first unfinished stage. We keep
# re-invoking until progress.json marks the subsystem "complete".
# ============================================================
MAX_ATTEMPTS_PER_SUBSYSTEM="${MAX_ATTEMPTS_PER_SUBSYSTEM:-8}"

# complete if status==complete OR the quality gate says all stages are done
subsystem_complete() {
    jq -e --arg s "$1" '
        .subsystems[] | select(.name == $s)
        | (.status == "complete") or ((.quality_gate.all_stages_completed // false) == true)
    ' progress.json > /dev/null 2>&1
}

# a snapshot of forward progress; if it does not change across a whole attempt,
# the run made no progress and we stop retrying to avoid an infinite loop
subsystem_fingerprint() {
    local s="$1" pj findings pocs
    pj=$(jq -rc --arg s "$s" '(.subsystems[] | select(.name==$s) | [.status, (.current_stage // "-"), ((.quality_gate // {}) | tostring)]) // []' progress.json 2>/dev/null || true)
    findings=$( [ -f FINDINGS.md ] && wc -l < FINDINGS.md || echo 0 )
    pocs=$( ls -d pocs/*/ 2>/dev/null | wc -l || true )
    echo "${pj}|F:${findings}|P:${pocs}"
}

SUBSYSTEMS=$(jq -r '.subsystems[].name' progress.json)

for subsystem in $SUBSYSTEMS; do
    if subsystem_complete "$subsystem"; then
        echo "Skipping $subsystem (already complete)"
        continue
    fi

    attempt=0
    last_fp=""
    stalls=0
    while ! subsystem_complete "$subsystem"; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$MAX_ATTEMPTS_PER_SUBSYSTEM" ]; then
            echo "!!! '$subsystem' still not complete after $MAX_ATTEMPTS_PER_SUBSYSTEM attempts — moving on. Inspect progress.json."
            break
        fi

        echo ">>> Subsystem '$subsystem' — attempt $attempt/$MAX_ATTEMPTS_PER_SUBSYSTEM"
        run_claude "subsystem-${subsystem}-a${attempt}" "
Process subsystem '${subsystem}' through the FULL pipeline (Stages 1-7) as
defined in CLAUDE.md.

DO NOT STOP until this subsystem is marked \"complete\" in progress.json. Obey
CLAUDE.md 'Headless Execution — NEVER Yield Mid-Subsystem': keep THIS session's
turn alive across every stage. If you spawn a background agent, do NOT end your
turn to 'wait' — block in the foreground (synchronous spawn, or a foreground
'sleep' poll loop on logs/agents/<name>.done) until its result is back, then
continue to the next stage.

First read progress.json, FINDINGS.md and WEAK.md and RESUME from the first
stage that has not completed for '${subsystem}'. Do not redo finished stages.
Run every remaining stage in order: Hunter, Fuzzer, Analyst, Challenger,
Defender, PoC build + execution, second Challenger + Defender review, Synthesis.
Persist after EACH stage (progress.json agent_log + current_stage, FINDINGS.md,
WEAK.md, pocs/) so a later invocation can resume if this one is killed. Do NOT
move on to any other subsystem. Mark this subsystem \"complete\" only when all
stages ran and the quality gate passed.
" || true

        # stall detection: no forward progress recorded this whole attempt
        fp=$(subsystem_fingerprint "$subsystem")
        if [ -n "$last_fp" ] && [ "$fp" = "$last_fp" ]; then
            stalls=$((stalls + 1))
            echo "    (no progress recorded on attempt $attempt; stall $stalls/2)"
            if [ "$stalls" -ge 2 ]; then
                echo "!!! '$subsystem' made no progress in 2 consecutive attempts — moving on to avoid an infinite loop. Inspect progress.json."
                break
            fi
        else
            stalls=0
        fi
        last_fp="$fp"
    done

    if subsystem_complete "$subsystem"; then
        echo ">>> Subsystem '$subsystem' COMPLETE after $attempt attempt(s)."
    fi
done

# ============================================================
# STAGE 8: Senior Hunter second pass
# ============================================================
run_claude "stage8-senior-hunter" "
Stage 8: Senior Hunter second pass. All subsystems are complete. Read
FINDINGS.md, WEAK.md, and progress.json. Re-examine the 3-5 most
security-critical files across ALL subsystems. Look for cross-component logic
bugs and multi-step chains. Revisit WEAK.md for findings that could gain
reachability from other findings. Any new findings go through Stages 2-7.
Update progress.json when done.
"

# ============================================================
# STAGE 9: Cross-subsystem chaining
# ============================================================
run_claude "stage9-chaining" "
Stage 9: Cross-subsystem chaining analysis. Read ALL of FINDINGS.md and
WEAK.md. Find combinations of 2+ findings that form higher-impact attack
chains. Viable chains get full PoC pipeline treatment (Stages 2-7).
Speculative chains go to WEAK.md under 'Potential Chains'.
Update progress.json when done.
"

# ============================================================
# STAGE 10: Final report
# ============================================================
run_claude "stage10-final-report" "
Stage 10: Final report. Clean up FINDINGS.md and WEAK.md. Verify every PoC
directory has README.md and RESULT.md. Write the executive summary in
FINDINGS.md. Update progress.json to mark the audit complete.
"

echo ""
echo "============================================================"
echo "  Vulnerability research complete — $(date)"
echo "============================================================"
