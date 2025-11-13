#!/bin/bash
#
# vLLM Diagnosis and Baseline Benchmark
# =====================================
# Verifica versão vLLM, engine usado e cria benchmark baseline
#
# USO:
#   ./diagnose_vllm.sh

set -euo pipefail

# Cores
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

info "════════════════════════════════════════════════════════════════════"
info "vLLM Diagnosis and Baseline Benchmark"
info "════════════════════════════════════════════════════════════════════"
echo ""

# Verificar virtual environment
VENV_DIR="$HOME/vllm-env"
if [ ! -d "$VENV_DIR" ]; then
    error "Virtual environment não encontrado em $VENV_DIR"
    exit 1
fi

info "[1/3] Verificando versão vLLM e engine..."

source "$VENV_DIR/bin/activate"

python3 << 'PYEOF'
import vllm
import os
import sys
import subprocess

print("=" * 60)
print("🔍 VLLM CURRENT STATE")
print("=" * 60)

version = vllm.__version__
print(f"vLLM version: {version}")

# Parse version
try:
    major, minor = version.split('.')[:2]
    v_numeric = float(f"{major}.{minor}")
    
    if v_numeric >= 0.11:
        print("✅ Version >= 0.11.0 - V1 engine is default")
        needs_upgrade = False
    else:
        print(f"⚠️  Version {version} < 0.11.0 - UPGRADE RECOMMENDED")
        needs_upgrade = True
except:
    print("⚠️  Could not parse version")
    needs_upgrade = False

# Check V1 env var
v1_env = os.environ.get("VLLM_USE_V1", "not set")
print(f"\nVLLM_USE_V1 env var: {v1_env}")

# Check current process
print("\n🔍 Checking running vLLM process...")
try:
    result = subprocess.run(
        ["ps", "aux"], 
        capture_output=True, 
        text=True
    )
    vllm_procs = [line for line in result.stdout.split('\n') 
                  if 'vllm' in line.lower() and 'python' in line and 'api_server' in line]
    
    if vllm_procs:
        print(f"Found {len(vllm_procs)} vLLM process(es):")
        for proc in vllm_procs[:3]:  # Show first 3
            # Extract relevant parts
            parts = proc.split()
            if len(parts) > 10:
                cmd = ' '.join(parts[10:])
                print(f"  PID: {parts[1]}")
                print(f"  CMD: {cmd[:120]}...")
    else:
        print("❌ No vLLM API server process found")
except Exception as e:
    print(f"⚠️  Error checking processes: {e}")

print("\n" + "=" * 60)
if needs_upgrade:
    print("RECOMMENDATION: UPGRADE vLLM")
    print("  pip install --upgrade vllm")
else:
    print("RECOMMENDATION: VERSION OK")
print("=" * 60)
PYEOF

echo ""

# Criar script de benchmark
info "[2/3] Criando script de benchmark baseline..."

cat > "$HOME/benchmark_baseline.sh" << 'EOF'
#!/bin/bash
#
# Baseline Performance Test
# =========================
# Mede latência e throughput do servidor vLLM atual

set -e

VLLM_URL="${1:-http://localhost:8000}"

echo "⏱️  Baseline performance test..."
echo "URL: $VLLM_URL"
echo ""

# Detectar modelo
MODEL_RESPONSE=$(curl -s "$VLLM_URL/v1/models")
MODEL_ID=$(echo "$MODEL_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data'][0]['id'] if data.get('data') else '')" 2>/dev/null || echo "")

if [ -z "$MODEL_ID" ]; then
    MODEL_ID=$(echo "$MODEL_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$MODEL_ID" ]; then
    echo "❌ Não foi possível detectar modelo"
    exit 1
fi

echo "Modelo: $MODEL_ID"
echo ""

# Teste de latência e throughput
echo "Executando request..."
start=$(date +%s%N)

RESPONSE=$(curl -s -X POST "$VLLM_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL_ID\",
    \"prompt\": \"Explain the pharmacokinetics of SSRIs:\",
    \"max_tokens\": 100,
    \"temperature\": 0.7
  }")

end=$(date +%s%N)
latency=$(( (end - start) / 1000000 ))

echo "Latency: ${latency}ms"
echo $latency > /tmp/baseline_latency.txt

# Extract tokens generated
tokens=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('usage', {}).get('completion_tokens', 0))" 2>/dev/null || echo "0")

if [ -z "$tokens" ] || [ "$tokens" = "0" ]; then
    # Fallback: tentar extrair manualmente
    tokens=$(echo "$RESPONSE" | grep -o '"completion_tokens":[0-9]*' | cut -d':' -f2 || echo "0")
fi

echo "Tokens: $tokens"
echo $tokens > /tmp/baseline_tokens.txt

if [ "$tokens" -gt 0 ] && [ "$latency" -gt 0 ]; then
    throughput=$(python3 -c "print(int($tokens * 1000 / $latency))" 2>/dev/null || echo "0")
    echo "Throughput: ${throughput} tok/s"
    echo $throughput > /tmp/baseline_throughput.txt
else
    echo "⚠️  Não foi possível calcular throughput"
fi

echo ""
echo "✅ Baseline capturado!"
echo "  Latency: $(cat /tmp/baseline_latency.txt)ms"
echo "  Tokens: $(cat /tmp/baseline_tokens.txt)"
if [ -f /tmp/baseline_throughput.txt ]; then
    echo "  Throughput: $(cat /tmp/baseline_throughput.txt) tok/s"
fi
EOF

chmod +x "$HOME/benchmark_baseline.sh"
success "Script de benchmark criado: ~/benchmark_baseline.sh"

echo ""

# Executar benchmark se servidor estiver rodando
info "[3/3] Verificando servidor e executando benchmark..."

VLLM_URL="http://localhost:8000"

if curl -s -f "$VLLM_URL/v1/models" > /dev/null 2>&1; then
    success "Servidor está rodando em $VLLM_URL"
    echo ""
    "$HOME/benchmark_baseline.sh" "$VLLM_URL"
else
    warn "Servidor não está respondendo em http://localhost:8000"
    echo ""
    info "Para executar benchmark depois:"
    echo "  ${GREEN}~/benchmark_baseline.sh${NC}"
    echo ""
    info "Ou com URL customizada:"
    echo "  ${GREEN}~/benchmark_baseline.sh http://localhost:8001${NC}"
fi

echo ""
info "════════════════════════════════════════════════════════════════════"
success "Diagnóstico concluído!"
info "════════════════════════════════════════════════════════════════════"

