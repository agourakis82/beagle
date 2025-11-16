#!/bin/bash
# BEAGLE v2.0 - Complete Validation Suite

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

BEAGLE_ROOT="/home/maria/beagle"

echo "🔍 BEAGLE v2.0 - Validation Suite"
echo "=================================="
echo ""

# 1. Check services
echo -e "${YELLOW}1. Service Health Check${NC}"
python3 ${BEAGLE_ROOT}/scripts/test_sdk.py
echo ""

# 2. Check Knowledge Base structure
echo -e "${YELLOW}2. Knowledge Base Structure${NC}"
if [ -d "${BEAGLE_ROOT}/data/knowledge" ]; then
    echo -e "${GREEN}✅ KB directory exists${NC}"
    ls -la ${BEAGLE_ROOT}/data/knowledge/
else
    echo -e "${RED}❌ KB directory missing${NC}"
fi
echo ""

# 3. Check KB review file
echo -e "${YELLOW}3. KB Review File${NC}"
if [ -f "${BEAGLE_ROOT}/data/knowledge/reviews/clima_espacial_saude_mental.md" ]; then
    echo -e "${GREEN}✅ Clima espacial review exists${NC}"
    wc -l ${BEAGLE_ROOT}/data/knowledge/reviews/clima_espacial_saude_mental.md
else
    echo -e "${RED}❌ Clima espacial review missing${NC}"
fi
echo ""

# 4. Check chat script
echo -e "${YELLOW}4. Chat Script${NC}"
if [ -f "${BEAGLE_ROOT}/scripts/beagle_chat.py" ]; then
    echo -e "${GREEN}✅ beagle_chat.py exists${NC}"
    python3 -m py_compile ${BEAGLE_ROOT}/scripts/beagle_chat.py && echo -e "${GREEN}✅ Syntax valid${NC}"
else
    echo -e "${RED}❌ beagle_chat.py missing${NC}"
fi
echo ""

# 5. Test KB integration (non-interactive)
echo -e "${YELLOW}5. KB Integration Test${NC}"
python3 << 'PYEOF'
from pathlib import Path
from scripts.beagle_chat import BeagleChat

chat = BeagleChat()
kb_snippet = chat.get_kb_snippet("clima_espacial_saude_mental")
if "clima espacial" in kb_snippet.lower():
    print("✅ KB snippet loaded successfully")
    print(f"   Length: {len(kb_snippet)} chars")
else:
    print("❌ KB snippet failed")
PYEOF

echo ""
echo -e "${GREEN}✅ Validation complete!${NC}"

