# test_rdma_connectivity.ps1
# BEAGLE CLUSTER - RDMA Connectivity Test
# Testa conectividade RDMA entre tower e maria usando iperf3
# Uso: .\test_rdma_connectivity.ps1 [server_ip] [port]

param(
    [string]$ServerIP = "10.100.0.1",
    [int]$Port = 5201,
    [int]$Duration = 10
)

# Cores para output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput $Title "Cyan"
    Write-ColorOutput "========================================" "Cyan"
    Write-Host ""
}

Write-Header "BEAGLE CLUSTER - RDMA Connectivity Test"

# Verificar se iperf3 esta instalado
$iperf3Path = Get-Command iperf3 -ErrorAction SilentlyContinue

if (-not $iperf3Path) {
    Write-ColorOutput "[ERRO] iperf3 nao encontrado!" "Red"
    Write-ColorOutput "" "White"
    Write-ColorOutput "Instale iperf3:" "Yellow"
    Write-ColorOutput "  1. Via Chocolatey: choco install iperf3 -y" "Gray"
    Write-ColorOutput "  2. Ou baixe de: https://iperf.fr/iperf-download.php" "Gray"
    Write-ColorOutput "  3. Ou use winget: winget install iperf3" "Gray"
    exit 1
}

Write-ColorOutput "[OK] iperf3 encontrado: $($iperf3Path.Source)" "Green"
Write-ColorOutput "" "White"

# Verificar adaptador RDMA
$rdmaAdapters = Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }
if (-not $rdmaAdapters) {
    Write-ColorOutput "[AVISO] Nenhum adaptador RDMA habilitado detectado" "Yellow"
    Write-ColorOutput "        O teste pode nao usar RDMA (usara TCP normal)" "Yellow"
} else {
    Write-ColorOutput "[OK] Adaptadores RDMA habilitados:" "Green"
    $rdmaAdapters | ForEach-Object {
        Write-ColorOutput "  - $($_.Name)" "Gray"
    }
}

Write-ColorOutput "" "White"
Write-ColorOutput "Configuracao do teste:" "Cyan"
Write-ColorOutput "  Servidor: $ServerIP" "Gray"
Write-ColorOutput "  Porta: $Port" "Gray"
Write-ColorOutput "  Duracao: $Duration segundos" "Gray"
Write-ColorOutput "" "White"

# Verificar conectividade basica
Write-ColorOutput "Verificando conectividade basica..." "Yellow"
$pingResult = Test-Connection -ComputerName $ServerIP -Count 2 -Quiet -ErrorAction SilentlyContinue

if (-not $pingResult) {
    Write-ColorOutput "[AVISO] Ping falhou - servidor pode estar offline ou firewall bloqueando" "Yellow"
    Write-ColorOutput "        Continuando com teste iperf3 mesmo assim..." "Gray"
} else {
    Write-ColorOutput "[OK] Ping bem-sucedido" "Green"
}

Write-ColorOutput "" "White"
Write-ColorOutput "INSTRUCOES:" "Cyan"
Write-ColorOutput "  1. No servidor (maria - T560 Ubuntu), execute:" "White"
Write-ColorOutput "     iperf3 -s -B $ServerIP -p $Port" "Gray"
Write-ColorOutput "" "White"
Write-ColorOutput "  2. Apos o servidor estar rodando, pressione Enter para iniciar o teste..." "Yellow"
Write-ColorOutput "" "White"

$null = Read-Host "Pressione Enter quando o servidor estiver pronto"

# Executar teste
Write-ColorOutput "" "White"
Write-ColorOutput "Iniciando teste de throughput RDMA..." "Yellow"
Write-ColorOutput "Aguarde $Duration segundos..." "Gray"
Write-ColorOutput "" "White"

try {
    $testResult = & iperf3 -c $ServerIP -p $Port -t $Duration -f m 2>&1
    
    # Mostrar resultado
    Write-ColorOutput "=== RESULTADO DO TESTE ===" "Cyan"
    Write-ColorOutput "" "White"
    
    $testResult | ForEach-Object {
        $line = $_
        if ($line -match "sender|receiver|Gbits|Mbits|Kbits") {
            # Linhas importantes em verde
            Write-ColorOutput $line "Green"
        } elseif ($line -match "error|failed|timeout") {
            # Erros em vermelho
            Write-ColorOutput $line "Red"
        } else {
            # Outras linhas em cinza
            Write-ColorOutput $line "Gray"
        }
    }
    
    Write-ColorOutput "" "White"
    
    # Analisar resultado
    $throughput = $testResult | Select-String -Pattern "(\d+\.?\d*)\s*(Gbits|Mbits|Kbits)/sec" | Select-Object -First 1
    
    if ($throughput) {
        Write-ColorOutput "=== ANALISE ===" "Cyan"
        Write-ColorOutput "Throughput detectado: $($throughput.Matches.Value)" "Green"
        
        if ($throughput.Matches.Value -match "Gbits") {
            $value = [double]($throughput.Matches.Value -replace "[^\d.]")
            if ($value -ge 10) {
                Write-ColorOutput "[EXCELENTE] Throughput >= 10 Gbps - RDMA funcionando otimamente!" "Green"
            } elseif ($value -ge 1) {
                Write-ColorOutput "[BOM] Throughput >= 1 Gbps - RDMA funcionando" "Green"
            } else {
                Write-ColorOutput "[AVISO] Throughput < 1 Gbps - verifique configuracao" "Yellow"
            }
        } else {
            Write-ColorOutput "[AVISO] Throughput em Mbits/Kbits - pode nao estar usando RDMA" "Yellow"
        }
    } else {
        Write-ColorOutput "[AVISO] Nao foi possivel extrair throughput do resultado" "Yellow"
    }
    
} catch {
    Write-ColorOutput "[ERRO] Falha ao executar teste: $_" "Red"
    Write-ColorOutput "" "White"
    Write-ColorOutput "Verifique:" "Yellow"
    Write-ColorOutput "  1. Servidor iperf3 esta rodando no maria" "Gray"
    Write-ColorOutput "  2. Firewall permite conexao na porta $Port" "Gray"
    Write-ColorOutput "  3. IP $ServerIP esta correto" "Gray"
    exit 1
}

Write-ColorOutput "" "White"
Write-ColorOutput "Teste concluido!" "Green"

