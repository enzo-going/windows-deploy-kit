# ============================================================================
#  Etapa 02 - Remover bloatware da Microsoft Store
#  A lista fica em config\deploy.psd1 (AppxRemover / AppxManter).
# ============================================================================

function Invoke-RemoverBloatware {
    param([hashtable]$Config)

    $manter   = @($Config.AppxManter)
    $remover  = @($Config.AppxRemover)
    $contador = 0

    $instalados = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $naImagem   = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    foreach ($alvo in $remover) {

        if ($manter | Where-Object { $alvo -like "$_*" }) {
            Write-Log "protegido pela lista AppxManter, ignorando: $alvo"
            continue
        }

        foreach ($p in ($instalados | Where-Object { $_.Name -eq $alvo })) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log "removido: $alvo"
                $contador++
            }
            catch {
                try {
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                    Write-Log "removido (usuario atual): $alvo"
                    $contador++
                }
                catch { Write-Aviso "nao removi $alvo -- $($_.Exception.Message)" }
            }
        }

        foreach ($pp in ($naImagem | Where-Object { $_.DisplayName -eq $alvo })) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Write-Log "removido da imagem: $alvo"
            }
            catch { Write-Aviso "nao removi da imagem: $alvo" }
        }
    }

    Write-Log "$contador aplicativos removidos"

    # ------------------------------------------- sugestoes e propaganda do menu
    Write-Log 'desligando sugestoes de aplicativos e conteudo promocional'
    $cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $valores = @{
        'SilentInstalledAppsEnabled'      = 0
        'SystemPaneSuggestionsEnabled'    = 0
        'SoftLandingEnabled'              = 0
        'PreInstalledAppsEnabled'         = 0
        'OemPreInstalledAppsEnabled'      = 0
        'ContentDeliveryAllowed'          = 0
        'SubscribedContent-338388Enabled' = 0
        'SubscribedContent-338389Enabled' = 0
        'SubscribedContent-353698Enabled' = 0
    }
    foreach ($k in $valores.Keys) {
        New-ItemProperty -Path $cdm -Name $k -Value $valores[$k] -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # bloqueia a reinstalacao automatica de apps promovidos (politica de maquina)
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    if (-not (Test-Path $pol)) { New-Item -Path $pol -Force | Out-Null }
    New-ItemProperty -Path $pol -Name 'DisableWindowsConsumerFeatures' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $pol -Name 'DisableConsumerAccountStateContent' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}
