#!/bin/bash
# /ralph/start_ralph.sh - Launcher for Ralph loop

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get project root (parent of ralph folder)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RALPH_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Ralph Loop Launcher            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Project Root:${NC} $PROJECT_ROOT"
echo -e "${GREEN}Ralph Dir:${NC} $RALPH_DIR"
echo ""

# Verify project structure
verify_structure() {
    echo "🔍 Verifying project structure..."

    # Just verify the project root exists
    if [ -d "$PROJECT_ROOT" ]; then
        echo -e "  ✅ Found: Project root at $PROJECT_ROOT"
    else
        echo -e "  ❌ ERROR: Project root not found at $PROJECT_ROOT"
        exit 1
    fi

    echo ""
}

# Verify Claude CLI is available
verify_claude() {
    echo "🔍 Verifying Claude CLI..."

    if ! command -v claude &> /dev/null; then
        echo -e "${RED}❌ ERROR: Claude CLI not found${NC}"
        echo ""
        echo "Please install Claude CLI first:"
        echo "  npm install -g @anthropic-ai/claude"
        echo ""
        exit 1
    fi

    echo -e "  ${GREEN}✅ Claude CLI found${NC}"
    echo ""
}

# Main execution
main() {
    verify_structure
    verify_claude

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🚀 Starting Ralph Loop${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Change to ralph directory
    cd "$RALPH_DIR"

    # Execute the main Ralph loop script
    exec ./claude_ralph_loop.sh run
}

# Parse arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Ralph Loop Launcher"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  Start Ralph loop (default)"
        echo "  help       Show this help message"
        echo "  verify     Only verify structure, don't run"
        echo ""
        echo "This script will:"
        echo "  1. Verify project structure"
        echo "  2. Check Claude CLI availability"
        echo "  3. Launch claude_ralph_loop.sh"
        ;;
    "verify")
        verify_structure
        verify_claude
        echo -e "${GREEN}✅ Verification complete${NC}"
        ;;
    "")
        main
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run with 'help' for usage information"
        exit 1
        ;;
esac