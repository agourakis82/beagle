#!/bin/bash
# BEAGLE Self-Update CLI
# Uses Claude Code CLI to improve BEAGLE based on feedback

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BEAGLE Self-Update (via Claude CLI)            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}⚠️  Claude CLI not found${NC}"
    echo ""
    echo "To use BEAGLE self-update:"
    echo "1. Install Claude Code: https://claude.ai/download"
    echo "2. Login: claude auth login"
    echo "3. Run this script again"
    exit 1
fi

# Check if logged in
if ! claude auth status &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Claude CLI${NC}"
    echo ""
    echo "Please login first:"
    echo "  claude auth login"
    exit 1
fi

echo -e "${GREEN}✅ Claude CLI available${NC}"
echo ""

# Get feedback/issue description
if [ -z "$1" ]; then
    echo "Usage: $0 <feedback|issue|feature>"
    echo ""
    echo "Examples:"
    echo "  $0 \"Reduce memory usage in paper search\""
    echo "  $0 \"Add support for bioRxiv papers\""
    echo "  $0 \"Fix slow Neo4j queries\""
    exit 1
fi

FEEDBACK="$1"
DRY_RUN="${2:-true}"

echo -e "${BLUE}Feedback: ${FEEDBACK}${NC}"
echo -e "${BLUE}Dry run: ${DRY_RUN}${NC}"
echo ""

# Create temporary file for claude interaction
TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << EOF
You are BEAGLE's self-improvement AI. A scientific research platform built in Rust.

User feedback: ${FEEDBACK}

Based on this feedback, provide:
1. Root cause analysis
2. Specific files that need changes
3. Concrete code improvements
4. Tests to verify the fix

Be specific and actionable. Focus on production-quality Rust code.

Workspace structure:
- crates/beagle-llm/ - LLM clients and routing
- crates/beagle-search/ - PubMed/arXiv search
- crates/beagle-agents/ - Research agents
- crates/beagle-core/ - Core context
- crates/beagle-memory/ - Neo4j graph storage

Provide a detailed improvement plan.
EOF

echo -e "${GREEN}Analyzing feedback with Claude...${NC}"
claude chat --model claude-sonnet-4.5 < "$TEMP_FILE" | tee analysis.md

echo ""
echo -e "${GREEN}✅ Analysis complete!${NC}"
echo -e "${YELLOW}📋 Review the plan in: analysis.md${NC}"
echo ""

if [ "$DRY_RUN" != "false" ]; then
    echo -e "${YELLOW}This was a dry run. No changes made.${NC}"
    echo "To apply changes, run:"
    echo "  $0 \"$FEEDBACK\" false"
else
    echo -e "${GREEN}Ready to apply changes.${NC}"
    echo "TODO: Implement change application logic"
fi

rm "$TEMP_FILE"
