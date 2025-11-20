# monitor_rdma.ps1
# BEAGLE CLUSTER - RDMA Performance Monitor
# Monitora performance e status dos adaptadores RDMA
# Uso: .\monitor_rdma.ps1 [interval_seconds]

param(
    [int]$Interval = 5,
    [int]$Duration = 60
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

function Get-RDMAMetrics {
    $rdmaAdapters = Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }
    $metrics = @()
    
    foreach ($adapter in $rdmaAdapters) {
        $netAdapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
        if ($netAdapter) {
            $metrics += [PSCustomObject]@{
                Name = $adapter.Name
                Status = $netAdapter.Status
                LinkSpeed = $netAdapter.LinkSpeed
                MTU = $netAdapter.NlMtu
                RDMAEnabled = $adapter.Enabled
                BytesReceived = (Get-Counter "\Network Interface($($adapter.Name))\Bytes Received/sec" -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                BytesSent = (Get-Counter "\Network Interface($($adapter.Name))\Bytes Sent/sec" -ErrorAction SilentlyContinue).CounterSamples.CookedValue
            }
        }
    }
    
    return $metrics
}

Write-Header "BEAGLE CLUSTER - RDMA Performance Monitor"

$rdmaAdapters = Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }

if (-not $rdmaAdapters) {
    Write-ColorOutput "[ERRO] Nenhum adaptador RDMA habilitado encontrado!" "Red"
    exit 1
}

Write-ColorOutput "Monitorando adaptadores RDMA..." "Yellow"
Write-ColorOutput "Intervalo: $Interval segundos" "Gray"
Write-ColorOutput "Duracao: $Duration segundos" "Gray"
Write-ColorOutput "Pressione Ctrl+C para parar" "Gray"
Write-ColorOutput "" "White"

$startTime = Get-Date
$iteration = 0

try {
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        
        if ($elapsed.TotalSeconds -ge $Duration) {
            break
        }
        
        Clear-Host
        Write-Header "RDMA Monitor - Iteracao $iteration - Tempo: $([math]::Round($elapsed.TotalSeconds, 1))s"
        
        $metrics = Get-RDMAMetrics
        
        foreach ($metric in $metrics) {
            Write-ColorOutput "=== $($metric.Name) ===" "Cyan"
            Write-ColorOutput "  Status: $($metric.Status)" "Gray"
            Write-ColorOutput "  LinkSpeed: $($metric.LinkSpeed)" "Gray"
            Write-ColorOutput "  MTU: $($metric.MTU) bytes" "Gray"
            Write-ColorOutput "  RDMA: $($metric.RDMAEnabled)" "Gray"
            
            if ($metric.BytesReceived) {
                $rxMbps = [math]::Round(($metric.BytesReceived * 8) / 1MB, 2)
                Write-ColorOutput "  Receive: $rxMbps Mbps" "Green"
            }
            
            if ($metric.BytesSent) {
                $txMbps = [math]::Round(($metric.BytesSent * 8) / 1MB, 2)
                Write-ColorOutput "  Transmit: $txMbps Mbps" "Green"
            }
            
            Write-ColorOutput "" "White"
        }
        
        # Estatisticas de rede gerais
        Write-ColorOutput "=== Estatisticas Gerais ===" "Cyan"
        $netStats = Get-NetAdapterStatistics | Where-Object { $_.Name -in $rdmaAdapters.Name }
        foreach ($stat in $netStats) {
            Write-ColorOutput "  $($stat.Name):" "Gray"
            Write-ColorOutput "    Bytes Received: $([math]::Round($stat.ReceivedBytes / 1GB, 2)) GB" "Gray"
            Write-ColorOutput "    Bytes Sent: $([math]::Round($stat.SentBytes / 1GB, 2)) GB" "Gray"
            Write-ColorOutput "    Packets Received: $($stat.ReceivedUnicastPackets)" "Gray"
            Write-ColorOutput "    Packets Sent: $($stat.SentUnicastPackets)" "Gray"
        }
        
        $iteration++
        Start-Sleep -Seconds $Interval
    }
} catch {
    Write-ColorOutput "" "White"
    Write-ColorOutput "[INFO] Monitoramento interrompido" "Yellow"
}

Write-ColorOutput "" "White"
Write-ColorOutput "Monitoramento concluido" "Green"



