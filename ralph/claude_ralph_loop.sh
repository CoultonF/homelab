#!/bin/bash
# claude_ralph_loop.sh

# Configuration
PROMPT_FILE="PROMPT.md"
ITERATION_FILE="current_iteration.txt"
MAX_ITERATIONS=7
WORK_DIR="ralph_work"
LOG_FILE="ralph_execution.log"
CLAUDE_CMD="claude --dangerously-skip-permissions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize fresh context
initialize_context() {
    echo "🚀 INITIALIZING RALPH LOOP" | tee -a "$LOG_FILE"
    echo "==========================" | tee -a "$LOG_FILE"

    # Create work directory
    mkdir -p "$WORK_DIR"

    # Check for PRD file
    if [ ! -f "$PROMPT_FILE" ]; then
        echo -e "${RED}ERROR: $PROMPT_FILE not found!${NC}" | tee -a "$LOG_FILE"
        echo "Creating template PRD..." | tee -a "$LOG_FILE"
        create_template_prd
    fi

    # Start from iteration 1 if not exists
    if [ ! -f "$ITERATION_FILE" ]; then
        echo "1" > "$ITERATION_FILE"
    fi

    # Verify Claude is available
    if ! command -v claude &> /dev/null; then
        echo -e "${RED}ERROR: 'claude' command not found${NC}" | tee -a "$LOG_FILE"
        echo "Install Claude CLI first: npm install -g @anthropic-ai/claude" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Create template PRD if missing
create_template_prd() {
    cat > "$PROMPT_FILE" << 'EOF'
# Ralph Loop PRD

## Objective
Execute a Ralph loop pattern with fresh context windows on each iteration.

## Context
- Each iteration starts with a fresh context window
- State is persisted through files only
- Use Claude with --dangerously-skip-permissions flag

## Iteration Structure
1. Read previous iteration results
2. Process current task
3. Save results to files
4. Prepare context for next iteration

## Success Criteria
- Complete all iterations successfully
- Each iteration runs independently
- Results are properly saved
- No context contamination between iterations

## Constraints
- Must use --dangerously-skip-permissions flag
- Each iteration <= 5 minutes
- Store all outputs in work directory

## Initial Task
Start the Ralph loop with this PRD as context.
EOF
    echo -e "${GREEN}Created template $PROMPT_FILE${NC}" | tee -a "$LOG_FILE"
}

# Execute a single Claude iteration
execute_claude_iteration() {
    local iteration=$1
    local input_file="$WORK_DIR/input_${iteration}.txt"
    local output_file="$WORK_DIR/output_${iteration}.txt"
    local claude_input="$WORK_DIR/claude_input_${iteration}.md"
    local summary_file="$WORK_DIR/summary_${iteration}.json"

    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}🧠 CLAUDE ITERATION $iteration${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"

    # Prepare input for this iteration
    prepare_iteration_input "$iteration" "$claude_input"

    echo "📥 Input prepared: $claude_input" | tee -a "$LOG_FILE"
    echo "⏳ Executing Claude..." | tee -a "$LOG_FILE"

    # Execute Claude with dangerous permissions
    echo -e "${RED}⚠️  USING --dangerously-skip-permissions FLAG${NC}" | tee -a "$LOG_FILE"

    # Capture both stdout and stderr
    {
        echo "=== CLAUDE EXECUTION START ==="
        echo "Iteration: $iteration"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        # Read the input and pass to Claude
        cat "$claude_input" | $CLAUDE_CMD

        echo ""
        echo "=== CLAUDE EXECUTION END ==="
    } 2>&1 | tee "$output_file"

    # Extract Claude's response (assuming last block of output)
    extract_claude_response "$output_file" "$summary_file"

    echo -e "${GREEN}✅ Iteration $iteration completed${NC}" | tee -a "$LOG_FILE"
    echo "📁 Output: $output_file" | tee -a "$LOG_FILE"
    echo "📊 Summary: $summary_file" | tee -a "$LOG_FILE"
}

# Prepare input for Claude iteration
prepare_iteration_input() {
    local iteration=$1
    local output_file=$2

    # Start with the original PRD
    cat "$PROMPT_FILE" > "$output_file"

    echo -e "\n---\n" >> "$output_file"
    echo "# ITERATION $iteration" >> "$output_file"
    echo "## Context Window Reset" >> "$output_file"
    echo "This is a fresh context window. Previous context has been cleared." >> "$output_file"
    echo "" >> "$output_file"

    # Add state from previous iteration if exists
    if [ "$iteration" -gt 1 ]; then
        local prev_summary="$WORK_DIR/summary_$((iteration-1)).json"
        if [ -f "$prev_summary" ]; then
            echo "## Previous Iteration Summary" >> "$output_file"
            echo '```json' >> "$output_file"
            cat "$prev_summary" >> "$output_file"
            echo '```' >> "$output_file"
        fi
    fi

    echo "" >> "$output_file"
    echo "## Current Task" >> "$output_file"
    generate_task_for_iteration "$iteration" >> "$output_file"
}

# Generate task for specific iteration
generate_task_for_iteration() {
    local iteration=$1

    case $iteration in
        1)
            echo "1. Read and understand this PRD"
            echo "2. Create a plan for the Ralph loop"
            echo "3. Generate initial state file"
            echo "4. Prepare for iteration 2"
            ;;
        2)
            echo "1. Review the PRD and iteration 1 results"
            echo "2. Execute step 1 of the implementation"
            echo "3. Document any issues found"
            echo "4. Prepare for iteration 3"
            ;;
        3)
            echo "1. Continue implementation from previous iteration"
            echo "2. Process any accumulated data"
            echo "3. Validate results so far"
            echo "4. Prepare for iteration 4"
            ;;
        4)
            echo "1. Complete main implementation"
            echo "2. Create final validation tests"
            echo "3. Document the process"
            echo "4. Prepare for final iteration"
            ;;
        5)
            echo "1. Continue implementation from previous iteration"
            echo "2. Process current phase tasks"
            echo "3. Validate progress"
            echo "4. Prepare for iteration 6"
            ;;
        6)
            echo "1. Complete remaining implementation tasks"
            echo "2. Perform integration testing"
            echo "3. Document results"
            echo "4. Prepare for final iteration"
            ;;
        7)
            echo "1. Final validation of all iterations"
            echo "2. Create comprehensive summary"
            echo "3. Generate final report"
            echo "4. Clean up temporary files"
            ;;
        *)
            echo "1. Process iteration $iteration"
            echo "2. Continue with next iteration"
            echo "3. Update state files"
            ;;
    esac

    echo ""
    echo "## Instructions"
    echo "- This is a fresh context window"
    echo "- Use files for persistence only"
    echo "- Output should include:"
    echo "  1. Task completion status"
    echo "  2. Any errors encountered"
    echo "  3. State for next iteration"
    echo "  4. Next steps"
}

# Extract Claude's response from output
extract_claude_response() {
    local output_file=$1
    local summary_file=$2

    # Look for Claude's response pattern
    local response_start=$(grep -n "Claude:" "$output_file" | tail -1 | cut -d: -f1)

    if [ -n "$response_start" ]; then
        # Extract from "Claude:" to end or next marker
        tail -n +"$response_start" "$output_file" > "$summary_file.tmp"

        # Try to extract JSON if present
        if grep -q '{' "$summary_file.tmp" && grep -q '}' "$summary_file.tmp"; then
            sed -n '/{/,/}/p' "$summary_file.tmp" > "$summary_file"
        else
            # Just save the response
            head -50 "$summary_file.tmp" > "$summary_file"
        fi

        rm "$summary_file.tmp"
    else
        # Fallback: last 20 lines
        tail -20 "$output_file" > "$summary_file"
    fi

    # Add metadata
    echo "{\"iteration\": \"$iteration\", \"timestamp\": \"$(date +%s)\"}" > "${summary_file}.meta"
}

# Main Ralph Loop
main() {
    echo -e "${GREEN}🚀 Starting Ralph Loop with PRD: $PROMPT_FILE${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}⚠️  Using: $CLAUDE_CMD${NC}" | tee -a "$LOG_FILE"

    initialize_context

    # Get current iteration
    local current_iter=$(cat "$ITERATION_FILE")

    while [ "$current_iter" -le "$MAX_ITERATIONS" ]; do
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║    CLAUDE FRESH CONTEXT WINDOW #$current_iter      ║${NC}"
        echo -e "${BLUE}║    (Previous context cleared)                ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
        echo ""

        # Execute single Claude iteration
        execute_claude_iteration "$current_iter"

        # Update iteration counter
        current_iter=$((current_iter + 1))
        echo "$current_iter" > "$ITERATION_FILE"

        # Check if we should continue
        if [ "$current_iter" -le "$MAX_ITERATIONS" ]; then
            echo ""
            echo -e "${YELLOW}⏳ Preparing next context window in 3 seconds...${NC}"
            echo -e "${YELLOW}📝 Current context will be cleared${NC}"
            sleep 3

            # Clear shell context for demonstration
            clear
            echo -e "${GREEN}✨ Context cleared! Starting fresh...${NC}"
        fi
    done

    # Final summary
    echo ""
    echo -e "${GREEN}🎉 Ralph Loop completed!${NC}" | tee -a "$LOG_FILE"
    echo "Iterations: $MAX_ITERATIONS" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Work directory: $WORK_DIR/" | tee -a "$LOG_FILE"

    # Show summary of outputs
    echo ""
    echo -e "${BLUE}📋 Output Summary:${NC}"
    for i in $(seq 1 $MAX_ITERATIONS); do
        if [ -f "$WORK_DIR/output_${i}.txt" ]; then
            echo "  Iteration $i: $WORK_DIR/output_${i}.txt"
        fi
    done
}

# Alternative: Manual iteration control
manual_iteration() {
    local iteration=$1
    echo "$iteration" > "$ITERATION_FILE"

    echo -e "${YELLOW}🚀 Manually triggering iteration $iteration${NC}"
    echo -e "${RED}⚠️  Using: $CLAUDE_CMD${NC}"

    initialize_context
    execute_claude_iteration "$iteration"
}

# Clean function
clean_work() {
    echo -e "${YELLOW}🧹 Cleaning work directory...${NC}"
    rm -rf "$WORK_DIR"
    rm -f "$ITERATION_FILE" "$LOG_FILE"
    echo -e "${GREEN}✅ Cleaned${NC}"
}

# Usage function
show_usage() {
    echo "Ralph Loop with Claude and PRD"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  run          Run full Ralph loop (default)"
    echo "  manual [N]   Run specific iteration N"
    echo "  clean        Clean work directory"
    echo "  status       Show current status"
    echo "  reset        Reset to iteration 1"
    echo ""
    echo "Configuration:"
    echo "  PRD file:    $PROMPT_FILE"
    echo "  Max iters:   $MAX_ITERATIONS"
    echo "  Claude cmd:  $CLAUDE_CMD"
}

# Status function
show_status() {
    if [ -f "$ITERATION_FILE" ]; then
        local current=$(cat "$ITERATION_FILE")
        echo -e "Current iteration: ${YELLOW}$current${NC}/${MAX_ITERATIONS}"
    else
        echo -e "Status: ${RED}Not initialized${NC}"
    fi

    if [ -d "$WORK_DIR" ]; then
        echo -e "Work dir: ${GREEN}$WORK_DIR/${NC}"
        echo "Files:"
        ls -la "$WORK_DIR/" 2>/dev/null || echo "  (empty)"
    fi
}

# Parse arguments
case "$1" in
    "run")
        main
        ;;
    "manual")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Specify iteration number${NC}"
            exit 1
        fi
        manual_iteration "$2"
        ;;
    "clean")
        clean_work
        ;;
    "status")
        show_status
        ;;
    "reset")
        echo "1" > "$ITERATION_FILE"
        echo -e "${GREEN}✅ Reset to iteration 1${NC}"
        ;;
    ""|"help")
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_usage
        exit 1
        ;;
esac
