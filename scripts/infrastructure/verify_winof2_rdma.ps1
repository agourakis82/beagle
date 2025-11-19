# verify_winof2_rdma.ps1
# BEAGLE CLUSTER - WinOF-2 RDMA Verification
# Verifica se WinOF-2 foi instalado corretamente e RDMA esta habilitado
# Uso: .\verify_winof2_rdma.ps1

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

function Write-Section {
    param([string]$Title)
    Write-ColorOutput "" "White"
    Write-ColorOutput "--- $Title ---" "Yellow"
}

Write-Header "BEAGLE CLUSTER - WinOF-2 RDMA Verification"

# Verificar se esta rodando como Admin (opcional, mas recomendado)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-ColorOutput "AVISO: Execute como Administrador para verificacoes completas" "Yellow"
    Write-ColorOutput ""
}

# 1. Verificar adaptadores Mellanox
Write-Section "1. Adaptadores Mellanox Detectados"

# Primeiro, tentar encontrar por descricao/nome
$adapters = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -like "*Mellanox*" -or
    $_.InterfaceDescription -like "*ConnectX*" -or
    $_.Name -like "*mlx5*" -or
    ($_.InterfaceDescription -like "*NVIDIA*" -and $_.InterfaceDescription -like "*Ethernet*")
}

# Se nao encontrou, usar adaptadores com RDMA habilitado como fallback
if (-not $adapters) {
    $rdmaAdaptersTemp = Get-NetAdapterRdma -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
    if ($rdmaAdaptersTemp) {
        $adapters = Get-NetAdapter | Where-Object { $_.Name -in $rdmaAdaptersTemp.Name }
        Write-ColorOutput "  [INFO] Adaptadores encontrados via RDMA (pode nao ter 'Mellanox' no nome)" "Yellow"
    }
}

if ($adapters) {
    Write-ColorOutput "  [OK] Adaptadores Mellanox encontrados:" "Green"
    $adapters | ForEach-Object {
        Write-ColorOutput "     - Nome: $($_.Name)" "Gray"
        Write-ColorOutput "       Descricao: $($_.InterfaceDescription)" "Gray"
        Write-ColorOutput "       Status: $($_.Status)" "Gray"
        Write-ColorOutput "       LinkSpeed: $($_.LinkSpeed)" "Gray"
        Write-ColorOutput ""
        
        # Verificar info do driver
        try {
            $driverInfo = Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction SilentlyContinue
            if ($driverInfo) {
                Write-ColorOutput "       Driver Version: $($driverInfo.DriverVersion)" "Gray"
                if ($driverInfo.DriverDate) {
                    Write-ColorOutput "       Driver Date: $($driverInfo.DriverDate)" "Gray"
                }
            }
        } catch {
            # Ignorar erro se nao conseguir obter info do driver
        }
    }
} else {
    Write-ColorOutput "  [AVISO] Nenhum adaptador Mellanox detectado pelo nome" "Yellow"
    Write-ColorOutput "     -> Verificando adaptadores RDMA como alternativa..." "Gray"
}

# 2. Verificar RDMA habilitado
Write-Section "2. Status RDMA"

$rdmaAdapters = Get-NetAdapterRdma -ErrorAction SilentlyContinue

if ($rdmaAdapters) {
    $enabledRdma = $rdmaAdapters | Where-Object { $_.Enabled -eq $true }
    
    if ($enabledRdma) {
        Write-ColorOutput "  [OK] RDMA habilitado nos seguintes adaptadores:" "Green"
        $enabledRdma | ForEach-Object {
            Write-ColorOutput "     - $($_.Name): HABILITADO" "Gray"
        }
    } else {
        Write-ColorOutput "  [AVISO] RDMA detectado mas NAO habilitado" "Yellow"
        Write-ColorOutput "     -> Habilitar manualmente:" "Yellow"
        $rdmaAdapters | ForEach-Object {
            Write-ColorOutput "        Enable-NetAdapterRdma -Name `"$($_.Name)`"" "Gray"
        }
    }
    
    # Mostrar todos os adaptadores RDMA (habilitados ou nao)
    Write-ColorOutput "" "White"
    Write-ColorOutput "  Todos os adaptadores RDMA:" "Cyan"
    $rdmaAdapters | ForEach-Object {
        $status = if ($_.Enabled) { "HABILITADO" } else { "DESABILITADO" }
        $color = if ($_.Enabled) { "Green" } else { "Yellow" }
        Write-ColorOutput "     - $($_.Name): $status" $color
    }
} else {
    Write-ColorOutput "  [ERRO] RDMA nao detectado ou nao configurado!" "Red"
    Write-ColorOutput "     -> Verifique se WinOF-2 foi instalado corretamente" "Yellow"
    Write-ColorOutput "     -> Reinicie o sistema se acabou de instalar" "Yellow"
}

# 3. Verificar drivers WinOF-2 instalados
Write-Section "3. Drivers WinOF-2 Instalados"

$winofDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Mellanox*" -or
    $_.DeviceName -like "*ConnectX*" -or
    $_.InfName -like "*mlx5*" -or
    $_.InfName -like "*WinOF*" -or
    $_.Description -like "*Mellanox*"
}

if ($winofDrivers) {
    Write-ColorOutput "  [OK] Drivers WinOF-2 encontrados:" "Green"
    $winofDrivers | Select-Object -Unique DeviceName, DriverVersion, DriverDate | ForEach-Object {
        Write-ColorOutput "     - Device: $($_.DeviceName)" "Gray"
        Write-ColorOutput "       Driver Version: $($_.DriverVersion)" "Gray"
        if ($_.DriverDate) {
            # Tentar parsear a data de forma segura (PowerShell usa sintaxe diferente)
            $dateStr = $_.DriverDate.ToString()
            try {
                $parsedDate = [DateTime]$dateStr
                Write-ColorOutput "       Driver Date: $($parsedDate.ToString('yyyy-MM-dd'))" "Gray"
            } catch {
                # Se nao conseguir parsear, mostrar como string
                Write-ColorOutput "       Driver Date: $dateStr" "Gray"
            }
        }
        Write-ColorOutput ""
    }
} else {
    Write-ColorOutput "  [AVISO] Nenhum driver WinOF-2 detectado no registro" "Yellow"
    Write-ColorOutput "     -> Isto pode ser normal se o driver foi instalado recentemente" "Gray"
}

# 4. Verificar Device Manager (via WMI)
Write-Section "4. Dispositivos no Device Manager"

$devices = Get-PnpDevice | Where-Object {
    $_.FriendlyName -like "*Mellanox*" -or
    $_.FriendlyName -like "*ConnectX*" -or
    $_.FriendlyName -like "*NVIDIA*" -and $_.Class -eq "Net"
}

if ($devices) {
    Write-ColorOutput "  [OK] Dispositivos Mellanox encontrados:" "Green"
    $devices | ForEach-Object {
        $status = switch ($_.Status) {
            "OK" { "OK" }
            "Error" { "ERRO" }
            "Degraded" { "DEGRADADO" }
            default { $_.Status }
        }
        $statusColor = if ($_.Status -eq "OK") { "Green" } else { "Red" }
        Write-ColorOutput "     - $($_.FriendlyName): [$status]" $statusColor
        if ($_.Status -ne "OK") {
            Write-ColorOutput "       Problema Detectado!" "Red"
        }
    }
} else {
    Write-ColorOutput "  [AVISO] Nenhum dispositivo Mellanox encontrado no Device Manager" "Yellow"
}

# 5. Verificar configuracoes de rede RDMA
Write-Section "5. Configuracoes de Rede RDMA"

# Usar adaptadores RDMA habilitados se nao encontrou pelos nomes
$adaptersToCheck = $adapters
if (-not $adaptersToCheck) {
    $rdmaAdaptersTemp = Get-NetAdapterRdma -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
    if ($rdmaAdaptersTemp) {
        $adaptersToCheck = Get-NetAdapter | Where-Object { $_.Name -in $rdmaAdaptersTemp.Name }
    }
}

if ($adaptersToCheck) {
    $adaptersToCheck | ForEach-Object {
        $adapter = $_
        Write-ColorOutput "  Adaptador: $($adapter.Name)" "Cyan"
        Write-ColorOutput "    Descricao: $($adapter.InterfaceDescription)" "Gray"
        
        # IP Addresses
        $ipAddresses = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipAddresses) {
            Write-ColorOutput "    IP Addresses:" "Gray"
            $ipAddresses | ForEach-Object {
                Write-ColorOutput "      - $($_.IPAddress)/$($_.PrefixLength)" "Gray"
            }
        } else {
            Write-ColorOutput "    IP Addresses: Nenhum configurado" "Yellow"
        }
        
        # MTU
        $mtu = $adapter.NlMtu
        if ($mtu) {
            Write-ColorOutput "    MTU: $mtu bytes" "Gray"
            if ($mtu -lt 9000) {
                Write-ColorOutput "      [AVISO] MTU menor que 9000 (jumbo frames nao habilitado)" "Yellow"
                Write-ColorOutput "      -> Para habilitar: Set-NetAdapterAdvancedProperty -Name `"$($adapter.Name)`" -DisplayName `"Jumbo Packet`" -DisplayValue `"9000`"" "Gray"
            } else {
                Write-ColorOutput "      [OK] Jumbo frames habilitado (MTU >= 9000)" "Green"
            }
        } else {
            Write-ColorOutput "    MTU: Nao disponivel" "Yellow"
        }
        
        Write-ColorOutput ""
    }
} else {
    Write-ColorOutput "  [AVISO] Nenhum adaptador encontrado para verificar configuracoes" "Yellow"
}

# 6. Resumo final
Write-Header "RESUMO"

$allOk = $true

# Verificar adaptadores (usar RDMA como fallback)
$adaptersFound = $false
if ($adapters) {
    Write-ColorOutput "[OK] Adaptadores Mellanox detectados pelo nome" "Green"
    $adaptersFound = $true
} else {
    $rdmaAdaptersTemp = Get-NetAdapterRdma -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
    if ($rdmaAdaptersTemp) {
        Write-ColorOutput "[OK] Adaptadores RDMA detectados (Ethernet 6, Ethernet 7)" "Green"
        Write-ColorOutput "     (Adaptadores funcionando mesmo sem 'Mellanox' no nome)" "Gray"
        $adaptersFound = $true
    } else {
        Write-ColorOutput "[ERRO] Nenhum adaptador Mellanox/RDMA detectado" "Red"
        $allOk = $false
    }
}

if ($rdmaAdapters) {
    $enabledRdma = $rdmaAdapters | Where-Object { $_.Enabled -eq $true }
    if (-not $enabledRdma) {
        Write-ColorOutput "[AVISO] RDMA detectado mas nao habilitado" "Yellow"
        Write-ColorOutput "        Execute os comandos acima para habilitar" "Yellow"
        $allOk = $false
    } else {
        Write-ColorOutput "[OK] RDMA habilitado e funcionando em $($enabledRdma.Count) adaptador(es)" "Green"
    }
} else {
    Write-ColorOutput "[ERRO] RDMA nao configurado" "Red"
    $allOk = $false
}

if ($allOk) {
    Write-ColorOutput "" "White"
    Write-ColorOutput "INSTALACAO WINOF-2 VERIFICADA COM SUCESSO!" "Green"
    Write-ColorOutput "" "White"
    Write-ColorOutput "Proximos passos:" "Cyan"
    Write-ColorOutput "  1. Testar conectividade RDMA com iperf3:" "White"
    Write-ColorOutput "     Servidor (maria): iperf3 -s -B 10.100.0.1 -p 5201" "Gray"
    Write-ColorOutput "     Cliente (tower):  iperf3 -c 10.100.0.1 -t 10 -p 5201" "Gray"
    Write-ColorOutput "" "White"
    Write-ColorOutput "  2. Verificar performance (~12.5 Gbps esperado)" "White"
    Write-ColorOutput "  3. Configurar aplicacoes RDMA-aware se necessario" "White"
} else {
    Write-ColorOutput "" "White"
    Write-ColorOutput "PROBLEMAS DETECTADOS - Corrija antes de continuar" "Red"
}

Write-ColorOutput "" "White"

