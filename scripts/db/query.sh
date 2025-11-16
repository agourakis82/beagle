#!/bin/bash
# BEAGLE Database Query Helper

CONTAINER="beagle-postgres"
USER="beagle"
DB="beagle"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function db_query() {
    docker exec -i $CONTAINER psql -U $USER -d $DB -c "$1"
}

function list_papers() {
    echo -e "${BLUE}📚 Recent Papers:${NC}"
    db_query "SELECT id, title, authors[1] as first_author, publication_date FROM papers ORDER BY created_at DESC LIMIT 10;"
}

function list_drafts() {
    echo -e "${BLUE}📝 Recent Drafts:${NC}"
    db_query "SELECT id, section_type, LEFT(content, 50) as preview, created_at FROM drafts ORDER BY created_at DESC LIMIT 10;"
}

function list_interactions() {
    echo -e "${BLUE}💬 Recent Interactions:${NC}"
    db_query "SELECT id, LEFT(user_prompt, 40) as prompt, feedback_score, created_at FROM interactions ORDER BY created_at DESC LIMIT 10;"
}

function stats() {
    echo -e "${BLUE}📊 Database Statistics:${NC}"
    echo ""
    echo -e "${GREEN}Papers:${NC}"
    db_query "SELECT COUNT(*) as total, AVG(citation_count) as avg_citations FROM papers;"
    echo ""
    echo -e "${GREEN}Drafts:${NC}"
    db_query "SELECT section_type, COUNT(*) as count FROM drafts GROUP BY section_type;"
    echo ""
    echo -e "${GREEN}Interactions:${NC}"
    db_query "SELECT AVG(feedback_score) as avg_score, COUNT(*) as total FROM interactions WHERE feedback_score IS NOT NULL;"
}

case "$1" in
    papers)
        list_papers
        ;;
    drafts)
        list_drafts
        ;;
    interactions)
        list_interactions
        ;;
    stats)
        stats
        ;;
    query)
        shift
        db_query "$*"
        ;;
    *)
        echo "Usage: $0 {papers|drafts|interactions|stats|query <SQL>}"
        exit 1
        ;;
esac


