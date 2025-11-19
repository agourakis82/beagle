#!/bin/bash
#
# Deep Cluster Audit - Mapeia TUDO em todos os nodes
#
# Conecta via Tailscale e mapeia completamente:
# - Hardware (CPU, RAM, GPU, storage, temperaturas)
# - Storage profundo (todos diretórios, arquivos grandes, Docker volumes)
# - Docker (containers, images, volumes, networks, disk usage)
# - Processos, serviços e portas abertas
# - RDMA 100Gbps (InfiniBand)
# - Windows/WSL no tower (drive C diagnóstico)
#
# Gera relatório Markdown completo com recomendações.
#
# Uso: ./deep_cluster_audit.sh

set -eo pipefail

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Diretório temporário para dados coletados
readonly TEMP_DIR=$(mktemp -d /tmp/cluster_audit_XXXXXX)
readonly REPORT_DIR="docs"
readonly REPORT_FILE="${REPORT_DIR}/CLUSTER_AUDIT_$(date +%Y-%m-%d_%H%M%S).md"

# Senhas SSH (se necessário)
readonly MARIA_SSH_PASSWORD="${MARIA_SSH_PASSWORD:-123456}"
readonly TOWER_SSH_PASSWORD="${TOWER_SSH_PASSWORD:-}"

# Nodes detectados (inicializa arrays associativos)
declare -A NODES=()
declare -A NODE_IPS=()
declare -A NODE_TYPES=()
declare -A RDMA_IPS=()

# Detecta se estamos rodando localmente em algum node
LOCAL_HOSTNAME=$(hostname 2>/dev/null || echo "")
IS_LOCAL_TOWER=false
IS_LOCAL_MARIA=false

# ============================================================================
# UTILIDADES
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Executa comando remoto via tailscale ssh
# $1 = hostname do node
# $2 = comando a executar
# $3 = usar WSL? (true/false, default false)
remote_exec() {
    local node="$1"
    local cmd="$2"
    local use_wsl="${3:-false}"
    
    # Se for o node local, executa diretamente
    if [[ "$node" == "tower" && "$IS_LOCAL_TOWER" == "true" ]]; then
        # Tower local - executa via WSL se use_wsl=true, senão direto
        if [[ "$use_wsl" == "true" ]]; then
            wsl.exe -e bash -c "$cmd" 2>/dev/null || bash -c "$cmd" 2>/dev/null || echo "ERROR: Failed to execute locally on $node"
        else
            bash -c "$cmd" 2>/dev/null || echo "ERROR: Failed to execute locally on $node"
        fi
        return
    fi
    
    if [[ "$node" == "maria" && "$IS_LOCAL_MARIA" == "true" ]]; then
        # Maria local - executa direto
        bash -c "$cmd" 2>/dev/null || echo "ERROR: Failed to execute locally on $node"
        return
    fi
    
    # Opções SSH comuns
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    
    # Timeout de 30 segundos por comando
    if [[ "$use_wsl" == "true" && "$node" == "tower" ]]; then
        # Para tower remoto, executa via WSL
        timeout 30 tailscale ssh "$node" -- wsl.exe -e bash -c "$cmd" 2>/dev/null || \
            timeout 30 tailscale ssh "$node" -- bash -c "wsl.exe -e bash -c '$(echo "$cmd" | sed "s/'/'\"'\"'/g")'" 2>/dev/null || \
            echo "ERROR: Failed to execute on $node (timeout or error)"
    else
        # Tenta tailscale ssh primeiro
        timeout 30 tailscale ssh "$node" -- bash -c "$cmd" 2>/dev/null || {
            # Fallback para SSH direto
            # Se for maria e tem senha configurada, usa sshpass com autenticação por senha
            if [[ "$node" == *"maria"* || "$node" == *"darwin-t560"* || "$node" == *"t560"* ]]; then
                if command -v sshpass &> /dev/null && [[ -n "$MARIA_SSH_PASSWORD" ]]; then
                    local ssh_cmd="timeout 30 ssh $ssh_opts -o PubkeyAuthentication=no -o PreferredAuthentications=password $node bash -c '$(echo "$cmd" | sed "s/'/'\"'\"'/g")' 2>/dev/null"
                    sshpass -p "$MARIA_SSH_PASSWORD" $ssh_cmd || \
                        echo "ERROR: Failed to execute on $node (timeout or error)"
                else
                    local ssh_cmd="timeout 30 ssh $ssh_opts $node bash -c '$(echo "$cmd" | sed "s/'/'\"'\"'/g")' 2>/dev/null"
                    eval "$ssh_cmd" || echo "ERROR: Failed to execute on $node (timeout or error)"
                fi
            else
                local ssh_cmd="timeout 30 ssh $ssh_opts $node bash -c '$(echo "$cmd" | sed "s/'/'\"'\"'/g")' 2>/dev/null"
                eval "$ssh_cmd" || echo "ERROR: Failed to execute on $node (timeout or error)"
            fi
        }
    fi
}

# Executa PowerShell remoto no tower (Windows)
remote_exec_powershell() {
    local node="$1"
    local ps_cmd="$2"
    
    # Se for tower local, executa PowerShell direto
    if [[ "$node" == "tower" && "$IS_LOCAL_TOWER" == "true" ]]; then
        powershell.exe -Command "$ps_cmd" 2>/dev/null || \
            cmd.exe /c "powershell.exe -Command \"$ps_cmd\"" 2>/dev/null || \
            echo "ERROR: Failed to execute PowerShell locally on $node"
        return
    fi
    
    # Timeout de 60 segundos para comandos PowerShell (podem ser lentos)
    timeout 60 tailscale ssh "$node" -- powershell.exe -Command "$ps_cmd" 2>/dev/null || \
        timeout 60 tailscale ssh "$node" -- cmd.exe /c "powershell.exe -Command \"$ps_cmd\"" 2>/dev/null || \
        echo "ERROR: Failed to execute PowerShell on $node (timeout or error)"
}

# Salva output de comando remoto
# $1 = node
# $2 = categoria (hardware, storage, docker, etc)
# $3 = comando
# $4 = usar WSL? (true/false)
save_remote_output() {
    local node="$1"
    local category="$2"
    local cmd="$3"
    local use_wsl="${4:-false}"
    
    local output_file="${TEMP_DIR}/${node}_${category}.txt"
    
    log_info "  Coletando $category de $node..."
    
    # Tenta coletar, mas não falha se der erro (continua com outros comandos)
    if [[ "$use_wsl" == "true" ]]; then
        remote_exec "$node" "$cmd" true > "$output_file" 2>&1 || true
    else
        remote_exec "$node" "$cmd" false > "$output_file" 2>&1 || true
    fi
    
    # Remove linhas de erro comuns que não são relevantes
    sed -i '/^ERROR: Failed to execute/d' "$output_file" 2>/dev/null || true
    sed -i '/dial tcp.*timeout/d' "$output_file" 2>/dev/null || true
    sed -i '/Connection closed/d' "$output_file" 2>/dev/null || true
    
    # Se o arquivo estiver vazio ou só tiver erros, marca como não disponível
    if [[ ! -s "$output_file" ]] || grep -qE "ERROR|timeout|Connection closed|Bad Gateway" "$output_file" 2>/dev/null; then
        echo "N/A: Node não acessível ou comando não disponível" > "$output_file" 2>/dev/null || true
    fi
}

# ============================================================================
# DETECÇÃO DE NODES
# ============================================================================

detect_nodes() {
    log_info "Detectando nodes via Tailscale..."
    
    # Detecta se estamos rodando localmente
    if [[ -n "$LOCAL_HOSTNAME" ]]; then
        if echo "$LOCAL_HOSTNAME" | grep -qiE "tower|demetrios|demetriospcs|5860"; then
            IS_LOCAL_TOWER=true
            log_info "Detectado: rodando localmente no tower (demetriosPCS)"
        elif echo "$LOCAL_HOSTNAME" | grep -qiE "maria|t560|darwin-t560"; then
            IS_LOCAL_MARIA=true
            log_info "Detectado: rodando localmente no maria"
        fi
    fi
    
    if ! command -v tailscale &> /dev/null; then
        log_error "tailscale CLI não encontrado. Instale o Tailscale CLI."
        exit 1
    fi
    
    # Pega status do Tailscale
    local status_output=$(tailscale status 2>/dev/null || echo "")
    
    if [[ -z "$status_output" ]]; then
        log_error "Não foi possível obter status do Tailscale. Verifique se está autenticado."
        exit 1
    fi
    
    # Detecta maria (T560 Ubuntu) - procura por "maria", "t560", "darwin-t560"
    local maria_hostname=""
    if echo "$status_output" | grep -qiE "maria|t560|darwin-t560"; then
        maria_hostname=$(echo "$status_output" | grep -iE "maria|t560|darwin-t560" | grep -vE "offline|last seen" | head -1 | awk '{print $2}' || echo "")
        
        if [[ -z "$maria_hostname" ]]; then
            maria_hostname=$(echo "$status_output" | grep -iE "maria|t560|darwin-t560" | head -1 | awk '{print $2}' || echo "")
        fi
        
        if [[ -n "$maria_hostname" ]]; then
            local maria_ip=$(echo "$status_output" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -iE "$maria_hostname|maria|t560|darwin-t560" | head -1 | awk '{print $1}' || \
                tailscale ip -4 "$maria_hostname" 2>/dev/null || echo "")
            
            if [[ -n "$maria_ip" ]]; then
                NODES["maria"]="$maria_hostname"
                NODE_IPS["maria"]="$maria_ip"
                if [[ "$IS_LOCAL_MARIA" == "true" ]]; then
                    NODE_TYPES["maria"]="linux_local"
                else
                    NODE_TYPES["maria"]="linux"
                fi
                RDMA_IPS["maria"]="10.100.0.1"
                log_success "Node 'maria' (T560) detectado: $maria_hostname ($maria_ip)$([ "$IS_LOCAL_MARIA" == "true" ] && echo " [LOCAL]")"
            fi
        fi
    fi
    
    # Detecta tower (5860 Windows/WSL) - procura por "tower", "5860", "demetrios-pcs"
    local tower_hostname=""
    if echo "$status_output" | grep -qiE "tower|5860|demetrios-pcs"; then
        tower_hostname=$(echo "$status_output" | grep -iE "tower|5860|demetrios-pcs" | grep -vE "offline|last seen" | grep -i "windows" | head -1 | awk '{print $2}' || echo "")
        
        if [[ -z "$tower_hostname" ]]; then
            tower_hostname=$(echo "$status_output" | grep -iE "tower|5860|demetrios-pcs" | grep -i "windows" | head -1 | awk '{print $2}' || echo "")
        fi
        
        if [[ -n "$tower_hostname" ]]; then
            local tower_ip=$(echo "$status_output" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -iE "$tower_hostname|tower|5860|demetrios-pcs" | head -1 | awk '{print $1}' || \
                tailscale ip -4 "$tower_hostname" 2>/dev/null || echo "")
            
            if [[ -n "$tower_ip" ]]; then
                NODES["tower"]="$tower_hostname"
                NODE_IPS["tower"]="$tower_ip"
                if [[ "$IS_LOCAL_TOWER" == "true" ]]; then
                    NODE_TYPES["tower"]="windows_wsl_local"
                else
                    NODE_TYPES["tower"]="windows_wsl"
                fi
                RDMA_IPS["tower"]="10.100.0.2"
                log_success "Node 'tower' (5860) detectado: $tower_hostname ($tower_ip)$([ "$IS_LOCAL_TOWER" == "true" ] && echo " [LOCAL]")"
            fi
        fi
    fi
    
    # Fallback: tenta conectar diretamente se não encontrou
    if [[ ${#NODES[@]} -eq 0 ]]; then
        log_warn "Não foi possível detectar nodes automaticamente. Tentando conexão direta..."
        
        # Tenta maria
        if tailscale ssh maria -- echo "OK" 2>/dev/null | grep -q "OK"; then
            NODES["maria"]="maria"
            NODE_IPS["maria"]=$(tailscale ip -4 maria 2>/dev/null || echo "unknown")
            NODE_TYPES["maria"]="linux"
            RDMA_IPS["maria"]="10.100.0.1"
        fi
        
        # Tenta tower
        if tailscale ssh tower -- echo "OK" 2>/dev/null | grep -q "OK"; then
            NODES["tower"]="tower"
            NODE_IPS["tower"]=$(tailscale ip -4 tower 2>/dev/null || echo "unknown")
            NODE_TYPES["tower"]="windows_wsl"
            RDMA_IPS["tower"]="10.100.0.2"
        fi
    fi
    
    if [[ ${#NODES[@]} -eq 0 ]]; then
        log_error "Nenhum node detectado. Verifique conexão Tailscale."
        exit 1
    fi
    
    log_success "Detectados ${#NODES[@]} node(s): ${!NODES[*]}"
}

# ============================================================================
# COLETA DE DADOS - HARDWARE & SISTEMA
# ============================================================================

collect_hardware_data() {
    local node="$1"
    local node_type="${NODE_TYPES[$node]}"
    
    log_info "Coletando hardware e sistema de $node..."
    
    # Informações básicas do sistema
    save_remote_output "$node" "system_basic" "hostname && uname -a && uptime"
    save_remote_output "$node" "cpu" "lscpu"
    save_remote_output "$node" "memory" "free -h"
    save_remote_output "$node" "blockdevices" "lsblk -f"
    save_remote_output "$node" "filesystems" "df -h"
    
    # SMART status dos drives
    save_remote_output "$node" "smart_nvme" "for dev in /dev/nvme*; do [ -e \$dev ] && echo \"=== \$dev ===\" && nvme smart-log \$dev 2>/dev/null || true; done"
    save_remote_output "$node" "smart_sata" "for dev in /dev/sd[a-z]; do [ -e \$dev ] && echo \"=== \$dev ===\" && smartctl -a \$dev 2>/dev/null || true; done"
    
    # GPU (se disponível)
    save_remote_output "$node" "gpu" "nvidia-smi 2>/dev/null || echo 'No NVIDIA GPU found'"
    
    # Temperaturas
    save_remote_output "$node" "sensors" "sensors 2>/dev/null || echo 'No sensors available'"
    
    # Hardware info (requer sudo, pode falhar)
    save_remote_output "$node" "dmidecode" "sudo dmidecode -t system -t memory -t processor 2>/dev/null || echo 'dmidecode requires sudo or not available'"
}

# ============================================================================
# COLETA DE DADOS - STORAGE PROFUNDO
# ============================================================================

collect_storage_data() {
    local node="$1"
    local node_type="${NODE_TYPES[$node]}"
    
    log_info "Coletando storage profundo de $node..."
    
    # Top 30 maiores diretórios no root
    save_remote_output "$node" "storage_root" "du -sh /* 2>/dev/null | sort -hr | head -30"
    
    # Top 20 maiores em /home
    save_remote_output "$node" "storage_home" "du -sh /home/* 2>/dev/null | sort -hr | head -20"
    
    # Top 20 maiores em /var
    save_remote_output "$node" "storage_var" "du -sh /var/* 2>/dev/null | sort -hr | head -20"
    
    # Top 20 maiores em /opt
    save_remote_output "$node" "storage_opt" "du -sh /opt/* 2>/dev/null | sort -hr | head -20"
    
    # Arquivos maiores que 1GB (com timeout - pode ser muito lento)
    save_remote_output "$node" "large_files" "timeout 120 find /home /opt /mnt -type f -size +1G 2>/dev/null | head -50 || echo 'N/A: timeout ou nenhum arquivo > 1GB encontrado'"
    
    # Contagem de repos git (com timeout - pode ser muito lento em Windows)
    save_remote_output "$node" "git_repos" "timeout 60 find /home /opt /mnt -type d -name '.git' 2>/dev/null | wc -l || echo 'N/A: timeout or error'"
    
    # node_modules (se existir) (com timeout)
    save_remote_output "$node" "node_modules" "timeout 60 find /home /opt /mnt -type d -name 'node_modules' 2>/dev/null | xargs du -sh 2>/dev/null | sort -hr | head -20 || echo 'No node_modules found or timeout'"
    
    # Docker data (se existir)
    save_remote_output "$node" "docker_data_dirs" "if [ -d /var/lib/docker ]; then du -sh /var/lib/docker/* 2>/dev/null | sort -hr | head -20; fi"
    
    # WSL específico (tower)
    if [[ "$node_type" == "windows_wsl" ]]; then
        save_remote_output "$node" "wsl_storage" "du -sh ~/* 2>/dev/null | sort -hr | head -20" true
        save_remote_output "$node" "wsl_large_files" "find ~ -type f -size +500M 2>/dev/null | head -30" true
    fi
}

# ============================================================================
# COLETA DE DADOS - DOCKER
# ============================================================================

collect_docker_data() {
    local node="$1"
    local node_type="${NODE_TYPES[$node]}"
    local use_wsl="false"
    
    if [[ "$node_type" == "windows_wsl" ]]; then
        use_wsl="true"
    fi
    
    log_info "Coletando dados Docker de $node..."
    
    # Containers
    save_remote_output "$node" "docker_containers" "docker ps -a 2>/dev/null || echo 'Docker not available or not running'" "$use_wsl"
    
    # Images
    save_remote_output "$node" "docker_images" "docker images 2>/dev/null || echo 'Docker not available'" "$use_wsl"
    
    # Volumes
    save_remote_output "$node" "docker_volumes" "docker volume ls 2>/dev/null || echo 'Docker not available'" "$use_wsl"
    
    # Disk usage detalhado
    save_remote_output "$node" "docker_disk_usage" "docker system df -v 2>/dev/null || echo 'Docker not available'" "$use_wsl"
    
    # Networks
    save_remote_output "$node" "docker_networks" "docker network ls 2>/dev/null || echo 'Docker not available'" "$use_wsl"
    
    # Docker info
    save_remote_output "$node" "docker_info" "docker info 2>/dev/null || echo 'Docker not available'" "$use_wsl"
    
    # Paths dos volumes (se docker volume ls funcionou)
    save_remote_output "$node" "docker_volume_paths" "
        if command -v docker &> /dev/null && command -v jq &> /dev/null; then
            docker volume ls -q | while read vol; do
                echo \"=== \$vol ===\"
                docker volume inspect \"\$vol\" 2>/dev/null | jq -r '.[0].Mountpoint' 2>/dev/null || echo 'N/A'
            done
        else
            echo 'Docker or jq not available'
        fi
    " "$use_wsl"
    
    # Tamanho dos diretórios Docker
    save_remote_output "$node" "docker_root_dirs" "
        if command -v docker &> /dev/null; then
            docker_root=\$(docker info 2>/dev/null | grep 'Docker Root Dir' | cut -d: -f2 | tr -d ' ')
            if [ -n \"\$docker_root\" ] && [ -d \"\$docker_root\" ]; then
                du -sh \"\$docker_root\"/* 2>/dev/null | sort -hr | head -20
            else
                echo 'Docker root dir not found'
            fi
        else
            echo 'Docker not available'
        fi
    " "$use_wsl"
}

# ============================================================================
# COLETA DE DADOS - PROCESSOS & SERVIÇOS
# ============================================================================

collect_process_data() {
    local node="$1"
    
    log_info "Coletando processos e serviços de $node..."
    
    # Top 30 processos por memória
    save_remote_output "$node" "processes_memory" "ps aux --sort=-%mem 2>/dev/null | head -30 || ps aux | sort -k4 -rn | head -30"
    
    # Top 30 processos por CPU
    save_remote_output "$node" "processes_cpu" "ps aux --sort=-%cpu 2>/dev/null | head -30 || ps aux | sort -k3 -rn | head -30"
    
    # Serviços systemd rodando
    save_remote_output "$node" "services_running" "systemctl list-units --type=service --state=running 2>/dev/null | head -50 || echo 'systemctl not available'"
    
    # Serviços systemd falhados
    save_remote_output "$node" "services_failed" "systemctl list-units --type=service --state=failed 2>/dev/null || echo 'systemctl not available'"
    
    # Portas abertas
    save_remote_output "$node" "ports_listening" "ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null || echo 'ss/netstat not available'"
    
    # Contagem de arquivos abertos
    save_remote_output "$node" "open_files_count" "lsof 2>/dev/null | wc -l || echo 'lsof not available'"
}

# ============================================================================
# COLETA DE DADOS - REDE & RDMA
# ============================================================================

collect_network_data() {
    local node="$1"
    
    log_info "Coletando dados de rede e RDMA de $node..."
    
    # Status Tailscale
    save_remote_output "$node" "tailscale_status" "tailscale status 2>/dev/null || echo 'tailscale not available'"
    
    # IP Tailscale
    save_remote_output "$node" "tailscale_ip" "tailscale ip -4 2>/dev/null || tailscale ip -4 addr show tailscale0 2>/dev/null || echo 'tailscale not available'"
    
    # RDMA InfiniBand
    save_remote_output "$node" "rdma_ibstatus" "ibstatus 2>/dev/null || ibstat 2>/dev/null || echo 'RDMA/InfiniBand not available or not configured'"
    
    # Mapeamento RDMA
    save_remote_output "$node" "rdma_devices" "ibdev2netdev 2>/dev/null || echo 'ibdev2netdev not available'"
    
    # Interfaces de rede
    save_remote_output "$node" "network_interfaces" "ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo 'ip/ifconfig not available'"
    
    # Configuração ethtool (procurar interface 100Gbps)
    save_remote_output "$node" "ethtool_interfaces" "
        for iface in \$(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '); do
            echo \"=== \$iface ===\"
            ethtool \"\$iface\" 2>/dev/null | grep -E 'Speed|Link|Advertised' || echo 'Not a physical interface or ethtool not available'
        done
    "
}

# Teste de rede entre nodes
test_rdma_connection() {
    log_info "Testando conexão RDMA entre nodes..."
    
    local maria_rdma="${RDMA_IPS[maria]:-}"
    local tower_rdma="${RDMA_IPS[tower]:-}"
    
    if [[ -z "$maria_rdma" || -z "$tower_rdma" ]]; then
        log_warn "IPs RDMA não configurados. Pulando teste."
        return
    fi
    
    # Tenta iniciar iperf3 server no tower e testar do maria
    if [[ -n "${NODES[tower]:-}" && -n "${NODES[maria]:-}" ]]; then
        log_info "  Iniciando iperf3 server no tower..."
        remote_exec "tower" "which iperf3 >/dev/null 2>&1 && iperf3 -s -D 2>/dev/null || echo 'iperf3 not available on tower'" true
        
        sleep 2
        
        log_info "  Testando conexão do maria para tower..."
        save_remote_output "maria" "rdma_test" "iperf3 -c $tower_rdma -t 10 2>/dev/null || echo 'iperf3 test failed or not available'"
        
        # Para o server
        remote_exec "tower" "pkill iperf3 2>/dev/null || true" true
    fi
}

# ============================================================================
# COLETA DE DADOS - WINDOWS/TOWER ESPECÍFICO (Drive C)
# ============================================================================

collect_tower_windows_data() {
    local node="tower"
    
    if [[ -z "${NODES[$node]:-}" ]]; then
        return
    fi
    
    log_info "Coletando dados específicos do Windows (tower) - Drive C..."
    
    # PowerShell: Physical Disks
    log_info "  Coletando physical disks..."
    remote_exec_powershell "$node" "
        Get-PhysicalDisk | Select-Object DeviceID, MediaType, Size, HealthStatus, OperationalStatus | 
        Format-Table -AutoSize | Out-String
    " > "${TEMP_DIR}/${node}_windows_physicaldisks.txt" 2>&1
    
    # PowerShell: Volumes
    log_info "  Coletando volumes..."
    remote_exec_powershell "$node" "
        Get-Volume | Select-Object DriveLetter, FileSystemLabel, Size, SizeRemaining, HealthStatus | 
        Format-Table -AutoSize | Out-String
    " > "${TEMP_DIR}/${node}_windows_volumes.txt" 2>&1
    
    # PowerShell: Top 30 arquivos grandes em C:\
    log_info "  Coletando arquivos grandes em C:\\..."
    remote_exec_powershell "$node" "
        Get-ChildItem C:\\ -Recurse -ErrorAction SilentlyContinue -File | 
        Where-Object { \$_.Length -gt 1GB } | 
        Sort-Object Length -Descending | 
        Select-Object -First 30 FullName, 
            @{Name='SizeGB';Expression={[math]::Round(\$_.Length/1GB,2)}} | 
        Format-Table -AutoSize | Out-String
    " > "${TEMP_DIR}/${node}_windows_large_files.txt" 2>&1
    
    # PowerShell: Top 20 diretórios maiores em C:\
    log_info "  Coletando diretórios maiores em C:\\..."
    remote_exec_powershell "$node" "
        \$dirs = @{}
        Get-ChildItem C:\\ -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            \$size = (Get-ChildItem \$_.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            \$dirs[\$_.FullName] = \$size
        }
        \$dirs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | 
        ForEach-Object { 
            [PSCustomObject]@{
                Path = \$_.Key
                SizeGB = [math]::Round(\$_.Value/1GB,2)
            }
        } | Format-Table -AutoSize | Out-String
    " > "${TEMP_DIR}/${node}_windows_large_dirs.txt" 2>&1
    
    # PowerShell: WindowsApps
    log_info "  Coletando tamanho de WindowsApps..."
    remote_exec_powershell "$node" "
        if (Test-Path 'C:\\Program Files\\WindowsApps') {
            \$size = (Get-ChildItem 'C:\\Program Files\\WindowsApps' -Recurse -File -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            Write-Host \"WindowsApps total: \$([math]::Round(\$size/1GB,2)) GB\"
        } else {
            Write-Host 'WindowsApps not found'
        }
    " > "${TEMP_DIR}/${node}_windows_windowsapps.txt" 2>&1
    
    # PowerShell: Program Files
    log_info "  Coletando tamanho de Program Files..."
    remote_exec_powershell "$node" "
        \$dirs = @('C:\\Program Files', 'C:\\Program Files (x86)', 'C:\\ProgramData')
        foreach (\$dir in \$dirs) {
            if (Test-Path \$dir) {
                \$size = (Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue | 
                         Measure-Object -Property Length -Sum).Sum
                Write-Host \"\$dir : \$([math]::Round(\$size/1GB,2)) GB\"
            }
        }
    " > "${TEMP_DIR}/${node}_windows_programfiles.txt" 2>&1
    
    # PowerShell: Users
    log_info "  Coletando tamanho de Users..."
    remote_exec_powershell "$node" "
        if (Test-Path 'C:\\Users') {
            Get-ChildItem 'C:\\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                \$size = (Get-ChildItem \$_.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                         Measure-Object -Property Length -Sum).Sum
                [PSCustomObject]@{
                    User = \$_.Name
                    SizeGB = [math]::Round(\$size/1GB,2)
                }
            } | Format-Table -AutoSize | Out-String
        } else {
            Write-Host 'Users not found'
        }
    " > "${TEMP_DIR}/${node}_windows_users.txt" 2>&1
    
    # PowerShell: Temp files
    log_info "  Coletando temp files..."
    remote_exec_powershell "$node" "
        \$tempDirs = @('C:\\Windows\\Temp', 'C:\\Temp', \$env:TEMP)
        foreach (\$dir in \$tempDirs) {
            if (Test-Path \$dir) {
                \$size = (Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue | 
                         Measure-Object -Property Length -Sum).Sum
                \$count = (Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue).Count
                Write-Host \"\$dir : \$([math]::Round(\$size/1GB,2)) GB (\$count files)\"
            }
        }
    " > "${TEMP_DIR}/${node}_windows_temp.txt" 2>&1
    
    # WSL distros e tamanho
    log_info "  Coletando WSL distros..."
    remote_exec_powershell "$node" "
        wsl.exe --list --verbose 2>&1 | Out-String
    " > "${TEMP_DIR}/${node}_wsl_distros.txt" 2>&1
    
    # Docker data root no Windows (se existir)
    log_info "  Verificando Docker data root no Windows..."
    remote_exec_powershell "$node" "
        \$dockerData = \$env:ProgramData + '\\Docker'
        if (Test-Path \$dockerData) {
            \$size = (Get-ChildItem \$dockerData -Recurse -File -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            Write-Host \"Docker data root: \$dockerData\"
            Write-Host \"Size: \$([math]::Round(\$size/1GB,2)) GB\"
        } else {
            Write-Host 'Docker data root not found in ProgramData'
        }
    " > "${TEMP_DIR}/${node}_windows_docker_data.txt" 2>&1
}

# ============================================================================
# COLETA COMPLETA POR NODE
# ============================================================================

collect_node_data() {
    local node="$1"
    local node_type="${NODE_TYPES[$node]}"
    
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Coletando dados completos de: $node ($node_type)"
    log_info "═══════════════════════════════════════════════════════════════"
    
    collect_hardware_data "$node"
    collect_storage_data "$node"
    collect_docker_data "$node"
    collect_process_data "$node"
    collect_network_data "$node"
    
    # Dados específicos do Windows (tower)
    if [[ "$node_type" == "windows_wsl" ]]; then
        collect_tower_windows_data
    fi
    
    log_success "Coleta de $node concluída"
}

# ============================================================================
# ANÁLISE DE DADOS COLETADOS
# ============================================================================

analyze_storage() {
    local node="$1"
    
    log_info "Analisando storage de $node..."
    
    local analysis_file="${TEMP_DIR}/${node}_analysis.txt"
    
    {
        echo "=== ANÁLISE DE STORAGE ==="
        echo ""
        
        # Resumo de filesystems com uso percentual
        if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
            echo "FILESYSTEMS (Uso > 70% destacado):"
            echo ""
            while IFS= read -r line; do
                if echo "$line" | grep -qE "^/dev|^tmpfs|^overlay"; then
                    local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//' || echo "0")
                    if [[ "$usage" -gt 70 ]]; then
                        echo "⚠️  $line"  # Destaca uso alto
                    else
                        echo "$line"
                    fi
                fi
            done < "${TEMP_DIR}/${node}_filesystems.txt" | head -20
            echo ""
        fi
        
        # Top 10 maiores diretórios com gráfico ASCII
        if [[ -f "${TEMP_DIR}/${node}_storage_root.txt" ]]; then
            echo "TOP 10 MAIORES DIRETÓRIOS:"
            echo ""
            local count=0
            local max_size=0
            
            # Primeiro, encontra o maior tamanho para escala
            while IFS= read -r line; do
                if [[ $count -lt 10 ]]; then
                    local size_str=$(echo "$line" | awk '{print $1}' || echo "0")
                    # Converte para bytes aproximados para comparação
                    if echo "$size_str" | grep -qE "T$"; then
                        local size_num=$(echo "$size_str" | sed 's/T//' | awk '{print $1*1000000000000}')
                    elif echo "$size_str" | grep -qE "G$"; then
                        local size_num=$(echo "$size_str" | sed 's/G//' | awk '{print $1*1000000000}')
                    elif echo "$size_str" | grep -qE "M$"; then
                        local size_num=$(echo "$size_str" | sed 's/M//' | awk '{print $1*1000000}')
                    else
                        local size_num=$(echo "$size_str" | sed 's/K//' | awk '{print $1*1000}')
                    fi
                    if (( $(echo "$size_num > $max_size" | bc -l 2>/dev/null || echo "0") )); then
                        max_size=$size_num
                    fi
                    count=$((count + 1))
                fi
            done < "${TEMP_DIR}/${node}_storage_root.txt"
            
            # Imprime top 10 com barra ASCII
            count=0
            while IFS= read -r line; do
                if [[ $count -lt 10 ]]; then
                    local size_str=$(echo "$line" | awk '{print $1}' || echo "0")
                    local dir=$(echo "$line" | awk '{print $2}' || echo "")
                    
                    # Calcula barra (50 chars max)
                    local size_num=0
                    if echo "$size_str" | grep -qE "T$"; then
                        size_num=$(echo "$size_str" | sed 's/T//' | awk '{print $1*1000000000000}')
                    elif echo "$size_str" | grep -qE "G$"; then
                        size_num=$(echo "$size_str" | sed 's/G//' | awk '{print $1*1000000000}')
                    elif echo "$size_str" | grep -qE "M$"; then
                        size_num=$(echo "$size_str" | sed 's/M//' | awk '{print $1*1000000}')
                    else
                        size_num=$(echo "$size_str" | sed 's/K//' | awk '{print $1*1000}')
                    fi
                    
                    local bar_len=0
                    if (( $(echo "$max_size > 0" | bc -l 2>/dev/null || echo "0") )); then
                        bar_len=$(echo "scale=0; ($size_num / $max_size) * 50" | bc 2>/dev/null || echo "0")
                    fi
                    
                    local bar=""
                    for ((i=0; i<bar_len; i++)); do
                        bar="${bar}█"
                    done
                    
                    printf "%-10s │%-50s│ %s\n" "$size_str" "$bar" "$dir"
                    count=$((count + 1))
                fi
            done < "${TEMP_DIR}/${node}_storage_root.txt"
            echo ""
        fi
        
        # Arquivos grandes
        if [[ -f "${TEMP_DIR}/${node}_large_files.txt" ]]; then
            local large_count=$(wc -l < "${TEMP_DIR}/${node}_large_files.txt" 2>/dev/null || echo "0")
            echo "ARQUIVOS > 1GB: $large_count encontrados"
            head -15 "${TEMP_DIR}/${node}_large_files.txt"
            echo ""
        fi
        
        # Docker disk usage
        if [[ -f "${TEMP_DIR}/${node}_docker_disk_usage.txt" ]]; then
            echo "DOCKER DISK USAGE:"
            head -30 "${TEMP_DIR}/${node}_docker_disk_usage.txt"
            echo ""
        fi
        
        # Identifica problemas comuns
        echo "PROBLEMAS IDENTIFICADOS:"
        echo ""
        
        # Verifica uso de disco
        if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
            local high_usage=$(cat "${TEMP_DIR}/${node}_filesystems.txt" | grep -E "^/dev" | awk '$5+0 > 85 {print $6 " (" $5 " usado)"}' || echo "")
            if [[ -n "$high_usage" ]]; then
                echo "⚠️  Filesystem com uso > 85%:"
                echo "$high_usage" | sed 's/^/   /'
                echo ""
            fi
        fi
        
        # Verifica node_modules
        if [[ -f "${TEMP_DIR}/${node}_node_modules.txt" ]] && [[ -s "${TEMP_DIR}/${node}_node_modules.txt" ]]; then
            local node_modules_size=$(head -1 "${TEMP_DIR}/${node}_node_modules.txt" | awk '{print $1}' || echo "")
            if [[ -n "$node_modules_size" ]]; then
                echo "⚠️  node_modules encontrado (pode ser limpo): $node_modules_size total"
                head -5 "${TEMP_DIR}/${node}_node_modules.txt"
                echo ""
            fi
        fi
        
    } > "$analysis_file"
}

analyze_tower_drive_c() {
    local node="tower"
    
    if [[ -z "${NODES[$node]:-}" ]]; then
        return
    fi
    
    log_info "Analisando Drive C do tower..."
    
    local analysis_file="${TEMP_DIR}/${node}_drive_c_analysis.txt"
    local total_recoverable=0
    
    {
        echo "=== DIAGNÓSTICO DRIVE C (TOWER) ==="
        echo ""
        
        # Volumes com uso
        if [[ -f "${TEMP_DIR}/${node}_windows_volumes.txt" ]]; then
            echo "VOLUMES DISPONÍVEIS:"
            echo ""
            cat "${TEMP_DIR}/${node}_windows_volumes.txt"
            echo ""
            
            # Extrai uso do drive C
            local c_drive_usage=$(cat "${TEMP_DIR}/${node}_windows_volumes.txt" | grep -E "^C[[:space:]]" | head -1 || echo "")
            if [[ -n "$c_drive_usage" ]]; then
                echo "⚠️  DRIVE C STATUS:"
                echo "$c_drive_usage" | sed 's/^/   /'
                echo ""
            fi
        fi
        
        # Top diretórios em C:\ com gráfico
        if [[ -f "${TEMP_DIR}/${node}_windows_large_dirs.txt" ]]; then
            echo "TOP 20 DIRETÓRIOS EM C:\\:"
            echo ""
            
            # Tenta extrair tamanhos em GB para análise
            while IFS= read -r line; do
                if echo "$line" | grep -qE "SizeGB|GB"; then
                    local size_gb=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
                    local path=$(echo "$line" | grep -oE "C:\\\\.*" || echo "")
                    
                    if [[ -n "$path" ]]; then
                        # Identifica categorias recuperáveis
                        if echo "$path" | grep -qE "Temp|Cache|Downloads|\.tmp"; then
                            echo "🟢 $line (RECUPERÁVEL)"
                            total_recoverable=$(echo "$total_recoverable + $size_gb" | bc 2>/dev/null || echo "$total_recoverable")
                        elif echo "$path" | grep -qE "Program Files\\WindowsApps"; then
                            echo "🟡 $line (AVALIAR)"
                        elif echo "$path" | grep -qE "Program Files\\Docker"; then
                            echo "🔵 $line (MOVER PARA OUTRO DRIVE)"
                            total_recoverable=$(echo "$total_recoverable + $size_gb" | bc 2>/dev/null || echo "$total_recoverable")
                        else
                            echo "   $line"
                        fi
                    else
                        echo "   $line"
                    fi
                else
                    echo "   $line"
                fi
            done < "${TEMP_DIR}/${node}_windows_large_dirs.txt"
            echo ""
        fi
        
        # WindowsApps (geralmente não recuperável, mas pode ser otimizado)
        if [[ -f "${TEMP_DIR}/${node}_windows_windowsapps.txt" ]]; then
            echo "WINDOWSAPPS:"
            cat "${TEMP_DIR}/${node}_windows_windowsapps.txt"
            echo "ℹ️  WindowsApps geralmente não pode ser removido, mas pode ser otimizado removendo apps não usados"
            echo ""
        fi
        
        # Program Files
        if [[ -f "${TEMP_DIR}/${node}_windows_programfiles.txt" ]]; then
            echo "PROGRAM FILES:"
            cat "${TEMP_DIR}/${node}_windows_programfiles.txt"
            echo ""
        fi
        
        # Users
        if [[ -f "${TEMP_DIR}/${node}_windows_users.txt" ]]; then
            echo "USERS (por tamanho):"
            cat "${TEMP_DIR}/${node}_windows_users.txt"
            echo ""
        fi
        
        # Temp files (RECUPERÁVEL)
        if [[ -f "${TEMP_DIR}/${node}_windows_temp.txt" ]]; then
            echo "TEMP FILES (RECUPERÁVEL):"
            cat "${TEMP_DIR}/${node}_windows_temp.txt"
            
            # Soma temp files
            local temp_total=$(cat "${TEMP_DIR}/${node}_windows_temp.txt" | grep -oE "[0-9]+\.[0-9]+" | awk '{sum+=$1} END {print sum}' || echo "0")
            echo ""
            echo "💰 Espaço total em temp files: ~${temp_total} GB (RECUPERÁVEL)"
            total_recoverable=$(echo "$total_recoverable + $temp_total" | bc 2>/dev/null || echo "$total_recoverable")
            echo ""
        fi
        
        # Docker data (MOVER PARA OUTRO DRIVE)
        if [[ -f "${TEMP_DIR}/${node}_windows_docker_data.txt" ]]; then
            echo "DOCKER DATA ROOT:"
            cat "${TEMP_DIR}/${node}_windows_docker_data.txt"
            
            # Extrai tamanho
            local docker_size=$(cat "${TEMP_DIR}/${node}_windows_docker_data.txt" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
            if [[ -n "$docker_size" ]] && (( $(echo "$docker_size > 0" | bc -l 2>/dev/null || echo "0") )); then
                echo ""
                echo "💰 Docker data pode ser movido para outro drive: ~${docker_size} GB"
                total_recoverable=$(echo "$total_recoverable + $docker_size" | bc 2>/dev/null || echo "$total_recoverable")
            fi
            echo ""
        fi
        
        # Resumo de espaço recuperável
        echo "---"
        echo ""
        echo "💰 ESPAÇO RECUPERÁVEL ESTIMADO:"
        echo "   Total: ~${total_recoverable} GB"
        echo ""
        echo "Breakdown:"
        echo "   - Temp files: ~$(cat "${TEMP_DIR}/${node}_windows_temp.txt" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | awk '{sum+=$1} END {print sum}' || echo "0") GB"
        echo "   - Docker data (mover): ~$(cat "${TEMP_DIR}/${node}_windows_docker_data.txt" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0") GB"
        echo "   - Outros (avaliar): Ver diretórios acima"
        echo ""
        
    } > "$analysis_file"
    
    # Salva total recuperável para uso no relatório
    echo "$total_recoverable" > "${TEMP_DIR}/${node}_total_recoverable_gb.txt"
}

# Gera comandos de limpeza segura
generate_cleanup_commands() {
    local node="tower"
    
    if [[ -z "${NODES[$node]:-}" ]]; then
        return
    fi
    
    log_info "Gerando comandos de limpeza para tower..."
    
    local cleanup_file="${TEMP_DIR}/${node}_cleanup_commands.txt"
    local total_recoverable=$(cat "${TEMP_DIR}/${node}_total_recoverable_gb.txt" 2>/dev/null || echo "0")
    
    {
        echo "=== COMANDOS DE LIMPEZA SEGURA (TOWER) ==="
        echo ""
        echo "⚠️  IMPORTANTE: Execute com cuidado. Faça backup antes!"
        echo ""
        echo "💰 Espaço total estimado recuperável: ~${total_recoverable} GB"
        echo ""
        
        echo "## COMANDO 1: Limpar temp files do Windows (pode liberar 10-50GB+)"
        echo ""
        echo "\`\`\`powershell"
        echo "# Execute no PowerShell como Administrador"
        echo "\$tempDirs = @('C:\\Windows\\Temp', 'C:\\Temp', \$env:TEMP);"
        echo "\$totalFreed = 0;"
        echo "foreach (\$dir in \$tempDirs) {"
        echo "    if (Test-Path \$dir) {"
        echo "        \$sizeBefore = (Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum;"
        echo "        Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue;"
        echo "        Get-ChildItem \$dir -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue;"
        echo "        \$sizeAfter = (Get-ChildItem \$dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum;"
        echo "        \$freed = [math]::Round((\$sizeBefore - \$sizeAfter)/1GB, 2);"
        echo "        Write-Host \"Liberado de \$dir : \$freed GB\";"
        echo "        \$totalFreed += \$freed;"
        echo "    }"
        echo "}"
        echo "Write-Host \"Total liberado: \$([math]::Round(\$totalFreed, 2)) GB\""
        echo "\`\`\`"
        echo ""
        
        echo "## COMANDO 2: Mover Docker data root para outro drive (ex: D:\\) (pode liberar 20-100GB+)"
        echo ""
        echo "⚠️  Este comando move Docker data. Certifique-se de que:"
        echo "   1. Todos os containers estão parados"
        echo "   2. Você tem espaço no drive de destino"
        echo "   3. Você fez backup dos volumes importantes"
        echo ""
        echo "**Passo 1: Parar containers**"
        echo "\`\`\`bash"
        echo "# Execute no WSL"
        echo "wsl.exe -e docker stop \$(wsl.exe -e docker ps -q)"
        echo "wsl.exe -e docker system prune -a --volumes -f  # Limpa imagens não usadas (opcional)"
        echo "\`\`\`"
        echo ""
        echo "**Passo 2: Mover Docker data**"
        echo "\`\`\`powershell"
        echo "# Execute no PowerShell como Administrador"
        echo "\$oldPath = \$env:ProgramData + '\\Docker';"
        echo "\$newPath = 'D:\\Docker';  # Ajuste para o drive desejado"
        echo ""
        echo "if (Test-Path \$oldPath) {"
        echo "    # Cria diretório destino"
        echo "    New-Item -ItemType Directory -Path \$newPath -Force | Out-Null;"
        echo "    "
        echo "    # Move dados (robocopy preserva permissões)"
        echo "    robocopy \$oldPath \$newPath /MIR /R:3 /W:5 /NP /NDL /NFL;"
        echo "    "
        echo "    # VERIFICA antes de deletar o antigo!"
        echo "    Write-Host 'Verifique se todos os arquivos foram copiados antes de continuar';"
        echo "    Write-Host 'Para deletar o antigo: Remove-Item \$oldPath -Recurse -Force';"
        echo "    "
        echo "    # Após mover, configure Docker para usar novo path (requer reiniciar Docker/WSL)"
        echo "} else {"
        echo "    Write-Host 'Docker data root não encontrado em \$oldPath';"
        echo "}"
        echo "\`\`\`"
        echo ""
        
        echo "## COMANDO 3: Limpar cache do Windows Update (pode liberar 5-30GB+)"
        echo ""
        echo "\`\`\`powershell"
        echo "# Execute no PowerShell como Administrador"
        echo "Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue;"
        echo "Stop-Service -Name cryptSvc -Force -ErrorAction SilentlyContinue;"
        echo "Stop-Service -Name bits -Force -ErrorAction SilentlyContinue;"
        echo "Stop-Service -Name msiserver -Force -ErrorAction SilentlyContinue;"
        echo ""
        echo "\$updateCachePath = 'C:\\Windows\\SoftwareDistribution\\Download';"
        echo "if (Test-Path \$updateCachePath) {"
        echo "    \$sizeBefore = (Get-ChildItem \$updateCachePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum;"
        echo "    Remove-Item \$updateCachePath -Recurse -Force -ErrorAction SilentlyContinue;"
        echo "    Write-Host \"Cache do Windows Update limpo: \$([math]::Round(\$sizeBefore/1GB, 2)) GB liberados\";"
        echo "} else {"
        echo "    Write-Host 'Cache do Windows Update não encontrado';"
        echo "}"
        echo ""
        echo "Start-Service -Name wuauserv -ErrorAction SilentlyContinue;"
        echo "Start-Service -Name cryptSvc -ErrorAction SilentlyContinue;"
        echo "Start-Service -Name bits -ErrorAction SilentlyContinue;"
        echo "Start-Service -Name msiserver -ErrorAction SilentlyContinue;"
        echo "\`\`\`"
        echo ""
        
        echo "## COMANDO 4 (BONUS): Limpar logs antigos do Windows (pode liberar 1-10GB+)"
        echo ""
        echo "\`\`\`powershell"
        echo "# Execute no PowerShell como Administrador"
        echo "\$logsPath = 'C:\\Windows\\Logs';"
        echo "if (Test-Path \$logsPath) {"
        echo "    \$oldLogs = Get-ChildItem \$logsPath -Recurse -File | Where-Object { \$_.LastWriteTime -lt (Get-Date).AddDays(-30) };"
        echo "    \$sizeBefore = (\$oldLogs | Measure-Object -Property Length -Sum).Sum;"
        echo "    \$oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue;"
        echo "    Write-Host \"Logs antigos removidos: \$([math]::Round(\$sizeBefore/1GB, 2)) GB\";"
        echo "    "
        echo "    # Limpa event logs antigos"
        echo "    wevtutil el | ForEach-Object { wevtutil cl \"\$_\" /f 2>&1 | Out-Null };"
        echo "    Write-Host 'Event logs limpos';"
        echo "}"
        echo "\`\`\`"
        echo ""
        
        echo "## COMANDO 5 (BONUS): Limpar WSL distros não usadas"
        echo ""
        echo "\`\`\`bash"
        echo "# Lista distros WSL"
        echo "wsl.exe --list --verbose"
        echo ""
        echo "# Para remover uma distro (substitua <DistroName>):"
        echo "# wsl.exe --unregister <DistroName>"
        echo ""
        echo "# Exemplo: remover Ubuntu se não estiver usando"
        echo "# wsl.exe --unregister Ubuntu"
        echo "\`\`\`"
        echo ""
        
        echo "---"
        echo ""
        echo "## Ordem Recomendada de Execução:"
        echo ""
        echo "1. **COMANDO 1** (temp files) - Mais seguro, pode liberar 10-50GB"
        echo "2. **COMANDO 3** (Windows Update) - Seguro, pode liberar 5-30GB"
        echo "3. **COMANDO 4** (logs antigos) - Seguro, pode liberar 1-10GB"
        echo "4. **COMANDO 2** (Docker data) - Requer cuidado, pode liberar 20-100GB"
        echo "5. **COMANDO 5** (WSL distros) - Avaliar caso a caso"
        echo ""
        echo "**Total estimado recuperável: ${total_recoverable} GB+**"
        echo ""
        
    } > "$cleanup_file"
}

# ============================================================================
# GERAÇÃO DE RELATÓRIO MARKDOWN
# ============================================================================

generate_report() {
    log_info "Gerando relatório Markdown completo..."
    
    mkdir -p "$REPORT_DIR"
    
    {
        echo "# Cluster Deep Audit Report"
        echo ""
        echo "**Gerado em:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "---"
        echo ""
        
        echo "## Resumo Executivo"
        echo ""
        echo "Este relatório contém auditoria completa de todos os nodes do cluster:"
        for node in "${!NODES[@]}"; do
            echo "- **$node** (${NODE_TYPES[$node]}) - IP: ${NODE_IPS[$node]:-unknown}"
        done
        echo ""
        
        # Seção por node
        for node in "${!NODES[@]}"; do
            echo "---"
            echo ""
            echo "## Node: $node (${NODE_TYPES[$node]})"
            echo ""
            
            # Informações básicas
            if [[ -f "${TEMP_DIR}/${node}_system_basic.txt" ]]; then
                echo "### Sistema"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_system_basic.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # CPU
            if [[ -f "${TEMP_DIR}/${node}_cpu.txt" ]]; then
                echo "### CPU"
                echo "\`\`\`"
                head -20 "${TEMP_DIR}/${node}_cpu.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Memória
            if [[ -f "${TEMP_DIR}/${node}_memory.txt" ]]; then
                echo "### Memória"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_memory.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # GPU
            if [[ -f "${TEMP_DIR}/${node}_gpu.txt" ]]; then
                echo "### GPU"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_gpu.txt" | head -50
                echo "\`\`\`"
                echo ""
            fi
            
            # Filesystems
            if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
                echo "### Filesystems"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_filesystems.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Top diretórios
            if [[ -f "${TEMP_DIR}/${node}_storage_root.txt" ]]; then
                echo "### Top 20 Maiores Diretórios"
                echo "\`\`\`"
                head -20 "${TEMP_DIR}/${node}_storage_root.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Arquivos grandes
            if [[ -f "${TEMP_DIR}/${node}_large_files.txt" ]]; then
                local large_count=$(wc -l < "${TEMP_DIR}/${node}_large_files.txt" 2>/dev/null || echo "0")
                echo "### Arquivos Grandes (>1GB)"
                echo "**Total encontrado:** $large_count"
                echo "\`\`\`"
                head -30 "${TEMP_DIR}/${node}_large_files.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Docker
            if [[ -f "${TEMP_DIR}/${node}_docker_containers.txt" ]]; then
                echo "### Docker Containers"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_docker_containers.txt" | head -50
                echo "\`\`\`"
                echo ""
            fi
            
            if [[ -f "${TEMP_DIR}/${node}_docker_disk_usage.txt" ]]; then
                echo "### Docker Disk Usage"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_docker_disk_usage.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Processos
            if [[ -f "${TEMP_DIR}/${node}_processes_memory.txt" ]]; then
                echo "### Top Processos (por Memória)"
                echo "\`\`\`"
                head -20 "${TEMP_DIR}/${node}_processes_memory.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # RDMA
            if [[ -f "${TEMP_DIR}/${node}_rdma_ibstatus.txt" ]]; then
                echo "### RDMA/InfiniBand Status"
                echo "\`\`\`"
                cat "${TEMP_DIR}/${node}_rdma_ibstatus.txt"
                echo "\`\`\`"
                echo ""
            fi
            
            # Windows específico (tower)
            if [[ "${NODE_TYPES[$node]}" == "windows_wsl" ]]; then
                echo "### Windows - Drive C Diagnóstico"
                echo ""
                
                if [[ -f "${TEMP_DIR}/${node}_windows_volumes.txt" ]]; then
                    echo "#### Volumes"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_volumes.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_large_dirs.txt" ]]; then
                    echo "#### Top Diretórios em C:\\"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_large_dirs.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_windowsapps.txt" ]]; then
                    echo "#### WindowsApps"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_windowsapps.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_programfiles.txt" ]]; then
                    echo "#### Program Files"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_programfiles.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_users.txt" ]]; then
                    echo "#### Users"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_users.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_temp.txt" ]]; then
                    echo "#### Temp Files"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_temp.txt"
                    echo "\`\`\`"
                    echo ""
                fi
                
                if [[ -f "${TEMP_DIR}/${node}_windows_docker_data.txt" ]]; then
                    echo "#### Docker Data Root"
                    echo "\`\`\`"
                    cat "${TEMP_DIR}/${node}_windows_docker_data.txt"
                    echo "\`\`\`"
                    echo ""
                fi
            fi
        done
        
        # Análise e Recomendações
        echo "---"
        echo ""
        echo "## Análise e Recomendações"
        echo ""
        
        # Análise do tower (drive C)
        if [[ -n "${NODES[tower]:-}" && -f "${TEMP_DIR}/tower_drive_c_analysis.txt" ]]; then
            echo "### Diagnóstico Drive C (Tower)"
            echo ""
            cat "${TEMP_DIR}/tower_drive_c_analysis.txt"
            echo ""
        fi
        
        # Análise de storage de cada node
        for node in "${!NODES[@]}"; do
            if [[ -f "${TEMP_DIR}/${node}_analysis.txt" ]]; then
                echo "### Análise de Storage: $node"
                echo ""
                cat "${TEMP_DIR}/${node}_analysis.txt"
                echo ""
            fi
        done
        
        # Comandos de limpeza
        if [[ -n "${NODES[tower]:-}" && -f "${TEMP_DIR}/tower_cleanup_commands.txt" ]]; then
            echo "### Comandos de Limpeza Segura (Tower)"
            echo ""
            cat "${TEMP_DIR}/tower_cleanup_commands.txt"
            echo ""
        fi
        
        # Resumo geral
        echo "### Resumo Geral do Cluster"
        echo ""
        echo "#### Nodes Auditados"
        echo ""
        for node in "${!NODES[@]}"; do
            echo "- **$node** (${NODE_TYPES[$node]})"
            echo "  - IP Tailscale: ${NODE_IPS[$node]:-unknown}"
            if [[ -n "${RDMA_IPS[$node]:-}" ]]; then
                echo "  - IP RDMA: ${RDMA_IPS[$node]}"
            fi
            
            # Resumo de storage
            if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
                local usage=$(cat "${TEMP_DIR}/${node}_filesystems.txt" | grep -E "^/dev" | awk '$5+0 > 85 {print $6 " (" $5 " usado)"}' | head -1 || echo "")
                if [[ -n "$usage" ]]; then
                    echo "  - ⚠️  Storage crítico: $usage"
                fi
            fi
            echo ""
        done
        
        echo "#### Gargalos Identificados"
        echo ""
        
        # Verifica uso alto de disco
        for node in "${!NODES[@]}"; do
            if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
                local high_usage=$(cat "${TEMP_DIR}/${node}_filesystems.txt" | grep -E "^/dev" | awk '$5+0 > 85 {print $6 " (" $5 " usado)"}' || echo "")
                if [[ -n "$high_usage" ]]; then
                    echo "- **$node**: Filesystem com uso > 85%"
                    echo "  - $high_usage"
                    echo ""
                fi
            fi
        done
        
        # Verifica Docker disk usage alto
        for node in "${!NODES[@]}"; do
            if [[ -f "${TEMP_DIR}/${node}_docker_disk_usage.txt" ]] && grep -qE "Local Volumes|Build Cache" "${TEMP_DIR}/${node}_docker_disk_usage.txt" 2>/dev/null; then
                echo "- **$node**: Docker usando espaço significativo - verificar seção Docker acima"
                echo ""
            fi
        done
        
        # Verifica processos pesados
        for node in "${!NODES[@]}"; do
            if [[ -f "${TEMP_DIR}/${node}_processes_memory.txt" ]]; then
                local heavy_procs=$(head -5 "${TEMP_DIR}/${node}_processes_memory.txt" | grep -vE "^USER|^$" | awk '{if ($4+0 > 10) print $11 " (" $4 "% mem)"}' | head -3 || echo "")
                if [[ -n "$heavy_procs" ]]; then
                    echo "- **$node**: Processos pesados (>10% mem):"
                    echo "$heavy_procs" | sed 's/^/  - /'
                    echo ""
                fi
            fi
        done
        
        echo "#### Espaço Recuperável Estimado (Tower)"
        echo ""
        if [[ -n "${NODES[tower]:-}" && -f "${TEMP_DIR}/tower_total_recoverable_gb.txt" ]]; then
            local tower_recoverable=$(cat "${TEMP_DIR}/tower_total_recoverable_gb.txt" || echo "0")
            echo "- **Total estimado: ~${tower_recoverable} GB**"
            echo ""
            echo "Breakdown:"
            if [[ -f "${TEMP_DIR}/tower_windows_temp.txt" ]]; then
                local temp_total=$(cat "${TEMP_DIR}/tower_windows_temp.txt" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | awk '{sum+=$1} END {print sum}' || echo "0")
                echo "  - Temp files: ~${temp_total} GB"
            fi
            if [[ -f "${TEMP_DIR}/tower_windows_docker_data.txt" ]]; then
                local docker_size=$(cat "${TEMP_DIR}/tower_windows_docker_data.txt" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
                if [[ -n "$docker_size" ]] && (( $(echo "$docker_size > 0" | bc -l 2>/dev/null || echo "0") )); then
                    echo "  - Docker data (mover): ~${docker_size} GB"
                fi
            fi
            echo "  - Windows Update cache: ~5-30 GB"
            echo "  - Logs antigos: ~1-10 GB"
        else
            echo "- Ver análise específica acima para detalhes"
        fi
        echo ""
        
        echo "#### RDMA 100Gbps Status"
        echo ""
        local rdma_detected=false
        for node in "${!NODES[@]}"; do
            if [[ -f "${TEMP_DIR}/${node}_rdma_ibstatus.txt" ]] && ! grep -qE "not available|not configured" "${TEMP_DIR}/${node}_rdma_ibstatus.txt" 2>/dev/null; then
                rdma_detected=true
                echo "- **$node**: ✅ RDMA detectado"
                if [[ -f "${TEMP_DIR}/${node}_rdma_devices.txt" ]]; then
                    echo "  - Dispositivos:"
                    cat "${TEMP_DIR}/${node}_rdma_devices.txt" | grep -vE "^===" | head -5 | sed 's/^/    /'
                fi
            else
                echo "- **$node**: ⚠️  RDMA não detectado ou não configurado"
            fi
            echo ""
        done
        
        if [[ "$rdma_detected" == "true" ]]; then
            echo "**Teste de Performance RDMA:**"
            if [[ -f "${TEMP_DIR}/maria_rdma_test.txt" ]]; then
                echo ""
                echo "\`\`\`"
                cat "${TEMP_DIR}/maria_rdma_test.txt"
                echo "\`\`\`"
            else
                echo "⚠️  Teste iperf3 não executado ou falhou"
            fi
            echo ""
        fi
        
        echo "#### Recomendações Imediatas"
        echo ""
        
        if [[ -n "${NODES[tower]:-}" ]]; then
            echo "**Para Tower (Drive C lotado):**"
            echo ""
            echo "1. Execute COMANDO 1 (limpar temp files) - Mais seguro, ~10-50GB"
            echo "2. Execute COMANDO 3 (limpar Windows Update) - Seguro, ~5-30GB"
            echo "3. Avalie COMANDO 2 (mover Docker data) - Requer cuidado, ~20-100GB"
            echo ""
        fi
        
        for node in "${!NODES[@]}"; do
            # Verifica uso alto de disco
            if [[ -f "${TEMP_DIR}/${node}_filesystems.txt" ]]; then
                local critical=$(cat "${TEMP_DIR}/${node}_filesystems.txt" | grep -E "^/dev" | awk '$5+0 > 90 {print $6}' | head -1 || echo "")
                if [[ -n "$critical" ]]; then
                    echo "**Para $node (Storage crítico > 90%):**"
                    echo ""
                    echo "1. Limpar logs antigos: \`find /var/log -type f -name '*.log' -mtime +30 -delete\`"
                    echo "2. Limpar Docker não usado: \`docker system prune -a --volumes -f\`"
                    echo "3. Verificar arquivos grandes: Ver seção 'Arquivos Grandes' acima"
                    echo ""
                fi
            fi
        done
        
        echo "---"
        echo ""
        echo "**Fim do Relatório**"
        echo ""
        echo "*Dados temporários salvos em: $TEMP_DIR*"
        echo "*Execute 'rm -rf $TEMP_DIR' para limpar após revisar o relatório*"
        
    } > "$REPORT_FILE"
    
    log_success "Relatório gerado: $REPORT_FILE"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  CLUSTER DEEP AUDIT - MAPEAMENTO COMPLETO"
    log_info "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Limpa diretório temp se existir de execução anterior
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    mkdir -p "$TEMP_DIR"
    
    # Detecta nodes
    detect_nodes
    
    # Coleta dados de cada node
    for node in "${!NODES[@]}"; do
        collect_node_data "$node"
        analyze_storage "$node"
    done
    
    # Análise específica do tower
    if [[ -n "${NODES[tower]:-}" ]]; then
        analyze_tower_drive_c
        generate_cleanup_commands
    fi
    
    # Teste RDMA
    test_rdma_connection
    
    # Gera relatório
    generate_report
    
    echo ""
    log_success "═══════════════════════════════════════════════════════════════"
    log_success "  AUDITORIA COMPLETA!"
    log_success "═══════════════════════════════════════════════════════════════"
    echo ""
    log_info "Relatório: $REPORT_FILE"
    log_info "Dados temporários: $TEMP_DIR"
    echo ""
    log_warn "Para limpar dados temporários: rm -rf $TEMP_DIR"
    echo ""
}

# Trap para limpeza em caso de erro
trap 'log_error "Script interrompido. Dados temporários em: $TEMP_DIR"' ERR INT TERM

# Executa main
main

