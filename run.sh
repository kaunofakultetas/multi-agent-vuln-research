#!/bin/bash
set -euo pipefail

mkdir -p logs


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
    claude -p "$prompt" --output-format stream-json --verbose --include-partial-messages < /dev/null 2>&1 \
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
# ============================================================
SUBSYSTEMS=$(jq -r '.subsystems[].name' progress.json)

for subsystem in $SUBSYSTEMS; do
    status=$(jq -r --arg s "$subsystem" '.subsystems[] | select(.name == $s) | .status' progress.json)
    if [ "$status" = "complete" ]; then
        echo "Skipping $subsystem (already complete)"
        continue
    fi

    run_claude "subsystem-${subsystem}" "
Process subsystem '${subsystem}' through the FULL pipeline (Stages 1–7) as
defined in CLAUDE.md. Read progress.json for current state and resume if
partially done. Run ALL stages in order: Hunter, Fuzzer, Analyst, Challenger,
Defender, PoC engineering + execution, second Challenger + Defender review,
and Synthesis. Do NOT skip any stage. Do NOT move to the next subsystem.
Update progress.json quality gate and mark this subsystem complete when done.
"
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