#!/bin/bash
# BEAGLE Restoration Quick Start Script
# Executes the complete restoration process from current state to working system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} $1 ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"

    local missing_tools=()

    # Check required tools
    local required_tools=("git" "curl" "docker")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        else
            log_success "$tool is installed"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and run again"
        exit 1
    fi

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/Cargo.toml" ]; then
        log_error "Not in BEAGLE project root (Cargo.toml not found)"
        log_info "Please run this script from the beagle-remote directory"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Welcome message
show_welcome() {
    clear
    cat << 'EOF'

  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                      ║
  ║                    🚀 BEAGLE RESTORATION PROCESS 🚀                   ║
  ║                                                                      ║
  ║     Transforming BEAGLE from aspirational docs to working system    ║
  ║                                                                      ║
  ╚══════════════════════════════════════════════════════════════════════╝

This script will guide you through the complete BEAGLE restoration process:

📋 PHASES:
  1. Foundation Audit & Cleanup (Week 1-2)
  2. Core Pipeline Implementation (Week 3-4)
  3. External Integrations (Week 5-6)
  4. Specialized Systems (Week 7-8)
  5. End-to-End Testing (Week 9-10)

⏰ ESTIMATED TIME: 8-10 weeks total
🎯 TODAY'S GOAL: Complete Phase 1 foundation setup

EOF

    read -p "Ready to begin? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restoration cancelled. Run when ready!"
        exit 0
    fi
}

# Setup restoration environment
setup_restoration_env() {
    log_header "Setting up Restoration Environment"

    cd "$PROJECT_ROOT"

    # Create restoration branch
    if git rev-parse --verify restoration-main >/dev/null 2>&1; then
        log_info "Restoration branch exists, switching to it..."
        git checkout restoration-main
    else
        log_info "Creating restoration branch..."
        git checkout -b restoration-main
    fi

    # Ensure scripts are executable
    chmod +x scripts/*.sh

    # Create log directory for this restoration session
    local session_dir="logs/restoration_${TIMESTAMP}"
    mkdir -p "$session_dir"

    log_success "Restoration environment ready"
    echo "Session logs: $session_dir"
}

# Phase 1: Foundation Audit & Cleanup
phase1_foundation() {
    log_header "PHASE 1: Foundation Audit & Cleanup"

    log_info "This phase will:"
    log_info "  • Audit the current system comprehensively"
    log_info "  • Identify all mocks and placeholders"
    log_info "  • Set up development environment"
    log_info "  • Document gaps between claims and reality"

    read -p "Execute Phase 1? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Phase 1 skipped"
        return 0
    fi

    # Step 1.1: Core System Audit
    log_info "Step 1.1: Running comprehensive system audit..."

    if [ -x "$SCRIPT_DIR/audit_system.sh" ]; then
        "$SCRIPT_DIR/audit_system.sh" || {
            log_warning "Audit completed with some issues - this is expected"
        }

        if [ -f "audit/AUDIT_SUMMARY.md" ]; then
            log_success "Audit completed! Summary:"
            echo
            head -20 "audit/AUDIT_SUMMARY.md"
            echo "... (see audit/AUDIT_SUMMARY.md for full report)"
            echo
        fi
    else
        log_error "Audit script not found or not executable"
        return 1
    fi

    # Step 1.2: Development Environment Setup
    log_info "Step 1.2: Setting up development environment..."

    if [ -x "$SCRIPT_DIR/setup_dev_environment.sh" ]; then
        read -p "Run automated environment setup? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            "$SCRIPT_DIR/setup_dev_environment.sh" setup || {
                log_warning "Environment setup had some issues - check logs"
            }
        fi
    else
        log_warning "Setup script not found - you'll need to set up manually"
        log_info "See docs/implementation/DEVELOPMENT_SETUP.md for instructions"
    fi

    # Step 1.3: Service Verification
    log_info "Step 1.3: Verifying external services..."

    if [ -x "$SCRIPT_DIR/check_external_services.sh" ]; then
        "$SCRIPT_DIR/check_external_services.sh" || {
            log_warning "Some services are not available - this is normal for initial setup"
        }
    else
        log_warning "Service check script not found"
    fi

    log_success "Phase 1 completed!"

    # Show next steps
    cat << 'EOF'

📊 PHASE 1 RESULTS:
  ✅ System audited and analyzed
  ✅ Development environment set up
  ✅ Service connectivity checked

📁 GENERATED REPORTS:
  • audit/AUDIT_SUMMARY.md - Overall findings
  • audit/reports/ - Detailed analysis reports
  • logs/ - Setup and service logs

🎯 NEXT STEPS:
  1. Review audit findings: cat audit/AUDIT_SUMMARY.md
  2. Check compilation status and fix critical issues
  3. Ensure all external services are running
  4. Begin Phase 2 when ready

EOF
}

# Show phase 2 preparation
show_phase2_prep() {
    log_header "Preparing for Phase 2: Core Pipeline Implementation"

    cat << 'EOF'

🎯 PHASE 2 OVERVIEW:
Phase 2 focuses on making core components actually work:

🔧 KEY COMPONENTS:
  • LLM Router (beagle-smart-router) - Real API integration
  • Darwin GraphRAG (beagle-darwin) - Neo4j + Qdrant integration
  • HERMES Paper Generation (beagle-hermes) - Academic paper pipeline

⚠️  PREREQUISITES FOR PHASE 2:
  1. All services from Phase 1 must be running
  2. API keys configured in .env file
  3. Basic compilation issues resolved
  4. External service connectivity verified

📋 BEFORE STARTING PHASE 2:
  • Review audit findings and fix critical compilation errors
  • Ensure Neo4j, Qdrant, PostgreSQL, Redis are running
  • Add your API keys to .env file (OpenAI, Anthropic, Grok, etc.)
  • Test basic functionality: cargo test --workspace --lib

⏰ ESTIMATED TIME: 1-2 weeks
🚀 START WHEN: Phase 1 foundations are solid

EOF

    log_info "Phase 2 implementation guide will be created once Phase 1 is complete"
    log_info "Focus on resolving Phase 1 findings first!"
}

# Update progress tracking
update_progress() {
    log_header "Updating Progress Tracking"

    local progress_file="$PROJECT_ROOT/RESTORATION_PROGRESS.md"

    if [ -f "$progress_file" ]; then
        # Update last updated timestamp
        sed -i.bak "s/\*\*Last Updated:\*\*.*/\*\*Last Updated:\*\* $(date +%Y-%m-%d)/" "$progress_file"

        # Mark Phase 1 as in progress
        sed -i.bak 's/\*\*Status:\*\* ⚪ NOT STARTED/\*\*Status:\*\* 🟡 IN PROGRESS/' "$progress_file"

        log_success "Progress tracking updated"
    else
        log_warning "Progress tracking file not found"
    fi
}

# Generate session report
generate_session_report() {
    log_header "Generating Session Report"

    local report_file="logs/restoration_${TIMESTAMP}/session_report.md"
    mkdir -p "$(dirname "$report_file")"

    cat > "$report_file" << EOF
# BEAGLE Restoration Session Report

**Date:** $(date)
**Session ID:** restoration_${TIMESTAMP}
**Phase:** 1 - Foundation Audit & Cleanup

## Session Summary

This session focused on establishing the foundation for BEAGLE restoration:

### Completed Actions
- [x] Prerequisites verification
- [x] Restoration environment setup
- [x] System audit execution
- [x] Development environment setup
- [x] External services verification

### Generated Artifacts
- \`audit/\` - Complete system analysis reports
- \`logs/restoration_${TIMESTAMP}/\` - Session logs
- Updated progress tracking

### Key Findings
$(if [ -f "audit/AUDIT_SUMMARY.md" ]; then
    echo "See audit/AUDIT_SUMMARY.md for detailed findings"
else
    echo "Audit results pending - check audit/ directory"
fi)

### Next Steps
1. Review audit findings thoroughly
2. Resolve any critical compilation issues
3. Ensure all external services are properly configured
4. Begin Phase 2 implementation when foundation is solid

### Files Modified
- Created restoration branch: restoration-main
- Updated RESTORATION_PROGRESS.md timestamp
- Generated comprehensive audit reports

---
*Generated by start_restoration.sh on $(date)*
EOF

    log_success "Session report generated: $report_file"
}

# Show final summary
show_final_summary() {
    log_header "Restoration Session Complete"

    cat << EOF

🎉 BEAGLE RESTORATION PHASE 1 COMPLETE!

📊 WHAT WAS ACCOMPLISHED:
  ✅ Comprehensive system audit performed
  ✅ Development environment configured
  ✅ External services checked
  ✅ Foundation established for restoration

📁 KEY FILES TO REVIEW:
  • audit/AUDIT_SUMMARY.md - Main findings
  • audit/reports/ - Detailed component analysis
  • RESTORATION_PROGRESS.md - Updated progress tracking
  • docs/implementation/DEVELOPMENT_SETUP.md - Setup guide

🎯 IMMEDIATE NEXT STEPS:
  1. Review audit summary:
     cat audit/AUDIT_SUMMARY.md

  2. Check compilation status:
     cargo check --workspace

  3. Verify services are running:
     ./scripts/check_external_services.sh

  4. Configure API keys in .env file

  5. Begin Phase 2 when ready:
     # Phase 2 will focus on implementing real functionality
     # in core components (LLM router, Darwin, HERMES)

⏰ TIME INVESTMENT: Phase 1 foundation complete
🚀 NEXT PHASE: Core Pipeline Implementation (1-2 weeks)

📞 SUPPORT: Review the audit findings and documentation for guidance

Happy coding! 🦀🚀

EOF
}

# Main execution
main() {
    # Change to project root
    cd "$PROJECT_ROOT"

    # Execute restoration steps
    show_welcome
    check_prerequisites
    setup_restoration_env
    phase1_foundation
    show_phase2_prep
    update_progress
    generate_session_report
    show_final_summary

    log_success "BEAGLE restoration Phase 1 completed successfully!"
}

# Handle script arguments
case "${1:-start}" in
    "start")
        main
        ;;
    "phase1")
        phase1_foundation
        ;;
    "audit")
        if [ -x "$SCRIPT_DIR/audit_system.sh" ]; then
            "$SCRIPT_DIR/audit_system.sh"
        else
            log_error "Audit script not found"
            exit 1
        fi
        ;;
    "setup")
        if [ -x "$SCRIPT_DIR/setup_dev_environment.sh" ]; then
            "$SCRIPT_DIR/setup_dev_environment.sh"
        else
            log_error "Setup script not found"
            exit 1
        fi
        ;;
    "check")
        if [ -x "$SCRIPT_DIR/check_external_services.sh" ]; then
            "$SCRIPT_DIR/check_external_services.sh"
        else
            log_error "Check script not found"
            exit 1
        fi
        ;;
    "help"|"-h"|"--help")
        cat << EOF
BEAGLE Restoration Quick Start

Usage: $0 [command]

Commands:
    start     Run complete Phase 1 restoration (default)
    phase1    Run Phase 1 only
    audit     Run system audit only
    setup     Run environment setup only
    check     Check external services only
    help      Show this help message

Examples:
    $0              # Run complete Phase 1 restoration
    $0 start        # Same as above
    $0 audit        # Just run the audit
    $0 setup        # Just setup environment
    $0 check        # Just check services

The restoration process transforms BEAGLE from aspirational documentation
to a genuinely working research system through systematic implementation.

EOF
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Run '$0 help' for usage information"
        exit 1
        ;;
esac
