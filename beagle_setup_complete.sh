#!/bin/bash

# BEAGLE v2.0 - Complete Setup Script
# Execute no servidor maria: bash beagle_setup_complete.sh

set -e  # Exit on error

echo "🚀 BEAGLE v2.0 - Complete Setup"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

BEAGLE_ROOT="/home/maria/beagle"

# ============================================
# 1. CREATE KNOWLEDGE BASE STRUCTURE
# ============================================
echo -e "${BLUE}1. Creating Knowledge Base structure...${NC}"
mkdir -p ${BEAGLE_ROOT}/data/knowledge/{papers,protocols,reviews,hypotheses}
echo -e "${GREEN}✅ Knowledge Base directories created${NC}"
echo ""

# ============================================
# 2. CREATE CLIMA ESPACIAL REVIEW
# ============================================
echo -e "${BLUE}2. Creating Clima Espacial review document...${NC}"
cat > ${BEAGLE_ROOT}/data/knowledge/reviews/clima_espacial_saude_mental.md << 'EOFKB'
# Clima Espacial e Saúde Mental - Revisão Científica

## Sumário Executivo

- **Status**: Hipóteses plausíveis, evidência fraca/modesta
- **Mecanismos**: Modulação circadiana, eixo neuroimune, atividade elétrica cerebral
- **Aplicação Clínica**: Insuficiente para recomendações específicas
- **Prioridade Pesquisa**: Alta (metodologia causal rigorosa necessária)

## Mecanismos Biológicos Propostos

### 1. Modulação Ritmos Circadianos

- Variações geomagnéticas → ionização atmosférica
- Interferência em magnetorrecepção/sistemas radicalares
- Fragmentação do sono → sintomas psiquiátricos

### 2. Eixo Neuroimune/Neuroendócrino

- Correlação: Kp alto ↔ marcadores cardiovasculares
- Estresse autonômico → descompensação psiquiátrica
- Vulnerabilidade individual (genética, histórico)

### 3. Modulação Atividade Elétrica Cerebral

- Campos geomagnéticos = "ruído eletromagnético" sutil
- Efeitos pequenos/inconsistentes em EEG/MEG
- Sem relação causal estabelecida

## Evidência Epidemiológica

**Correlações Observadas:**

- ↑ Hospitalizações psiquiátricas em períodos alta atividade geomagnética
- ↑ Crises de humor, surtos psicóticos, suicídio

**Limitações:**

- Múltiplas fontes de confundimento (sazonalidade, luz, temperatura)
- Associação fraca/modesta
- Alta heterogeneidade entre populações
- **Sem prova de causalidade**

## Variáveis Ambientais - Força da Evidência

| Variável | Evidência | Magnitude |
|----------|-----------|-----------|
| Fotoperíodo | **Forte** | Grande |
| Luz natural | **Forte** | Grande |
| Temperatura | **Forte** | Moderada |
| Poluição | **Forte** | Moderada |
| **Clima espacial** | **Fraca** | **Pequena** |

## Protocolo de Pesquisa Proposto

### Design

- **Tipo**: Observacional, séries temporais
- **População**: Depressão resistente, transtorno bipolar
- **Dados**: Prontuário + índices geomagnéticos (Kp, Ap)
- **Instrumentos**: Actigrafia, dispositivos vestíveis

### Análise Estatística

- Modelos VAR (Vector Autoregression)
- DAGs (Directed Acyclic Graphs)
- Análise causal estruturada
- Separação: correlação espúria vs. efeito real

### Endpoints

1. Internações psiquiátricas
2. Visitas emergência
3. Uso medicações (benzodiazepínicos, antipsicóticos)
4. Qualidade do sono (actigrafia)
5. Variabilidade frequência cardíaca

## Keywords

`clima espacial`, `geomagnetismo`, `psiquiatria`, `circadiano`, `melatonina`, `neuroimune`, `depressão`, `transtorno bipolar`, `causalidade`, `séries temporais`

## Referencias para Integração BEAGLE

- Indexar em Qdrant com embeddings
- Conectar com papers sobre ritmos circadianos
- Cross-reference: neurociência + física espacial
- Potencial colaboração: IPq-USP + IAG-USP
EOFKB

echo -e "${GREEN}✅ Review document created${NC}"
echo ""

# ============================================
# 3. UPDATE BEAGLE CHAT SCRIPT
# ============================================
echo -e "${BLUE}3. Updating beagle_chat.py with KB integration...${NC}"

# Backup existing if present
if [ -f "${BEAGLE_ROOT}/scripts/beagle_chat.py" ]; then
    cp ${BEAGLE_ROOT}/scripts/beagle_chat.py ${BEAGLE_ROOT}/scripts/beagle_chat.py.backup
fi

echo -e "${YELLOW}⚠️  beagle_chat.py código será gerado separadamente${NC}"
echo ""

# ============================================
# 4. INSTALL DEPENDENCIES
# ============================================
echo -e "${BLUE}4. Installing Python dependencies...${NC}"
pip3 install psycopg2-binary sentence-transformers --break-system-packages --quiet
echo -e "${GREEN}✅ Dependencies installed${NC}"
echo ""

# ============================================
# 5. RUN VALIDATION
# ============================================
echo -e "${BLUE}5. Running validation suite...${NC}"
if [ -f "${BEAGLE_ROOT}/scripts/validate_all.sh" ]; then
    bash ${BEAGLE_ROOT}/scripts/validate_all.sh
else
    echo -e "${YELLOW}⚠️  validate_all.sh not found, skipping${NC}"
fi
echo ""

# ============================================
# SUMMARY
# ============================================
echo "================================"
echo -e "${GREEN}✅ BEAGLE v2.0 Setup Complete!${NC}"
echo ""
echo "Knowledge Base created at:"
echo "  ${BEAGLE_ROOT}/data/knowledge/"
echo ""
echo "Next steps:"
echo "  1. Test chat: python3 ${BEAGLE_ROOT}/scripts/beagle_chat.py"
echo "  2. Ask: 'Como clima espacial afeta saúde mental?'"
echo "  3. View KB: Use /kb command in chat"
echo ""
echo "================================"


