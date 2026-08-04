# ============================================================================
#  Etapa 05 - Ajustes de sistema (energia, regiao, Explorer, etc.)
# ============================================================================

function Invoke-AplicarAjustes {
    param([hashtable]$Config)

    # ------------------------------------------------------- fuso horario ----
    if ($Config.FusoHorario) {
        try {
            Set-TimeZone -Id $Config.FusoHorario -ErrorAction Stop
            Write-Log "fuso horario: $($Config.FusoHorario)"
        }
        catch { Write-Aviso "nao consegui definir o fuso horario: $($_.Exception.Message)" }
    }

    # ------------------------------------------------------------ energia ----
    Write-Log 'ajustando plano de energia'
    $cfg = @(
        @('monitor-timeout-ac', $Config.TelaTempoAC)
        @('monitor-timeout-dc', $Config.TelaTempoBat)
        @('standby-timeout-ac', $Config.SuspenderAC)
        @('standby-timeout-dc', $Config.SuspenderBat)
    )
    foreach ($c in $cfg) {
        Invoke-Processo -Arquivo 'powercfg.exe' -Argumentos @('/change', $c[0], $c[1]) -SemErro | Out-Null
    }

    if ($Config.DesligarHibernacao) {
        Invoke-Processo -Arquivo 'powercfg.exe' -Argumentos @('/hibernate', 'off') -SemErro | Out-Null
        Write-Log 'hibernacao desligada (libera espaco do hiberfil.sys)'
    }

    # ---------------------------------------------------------- Explorer -----
    if ($Config.MostrarExtensoes) {
        Set-ExplorerPadrao
    }

    # ------------------------------------------------ restauracao do sistema --
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description 'WinDeployKit - antes do dominio' -RestorePointType 'APPLICATION_INSTALL' -ErrorAction Stop
        Write-Log 'ponto de restauracao criado'
    }
    catch { Write-Aviso 'nao criei ponto de restauracao (pode estar desabilitado por politica)' }

    # ------------------------------------------------------ Windows Update ---
    try {
        Write-Log 'disparando busca por atualizacoes em segundo plano'
        Start-Process -FilePath 'UsoClient.exe' -ArgumentList 'StartScan' -WindowStyle Hidden -ErrorAction Stop
    }
    catch { Write-Aviso 'nao consegui disparar o Windows Update' }
}

function Set-ExplorerPadrao {
    <#
      Aplica no usuario atual e no perfil Default (vale para quem logar depois,
      inclusive o usuario de dominio).
    #>
    $ajustes = @{
        'HideFileExt'      = 0   # mostrar extensoes
        'Hidden'           = 1   # mostrar arquivos ocultos
        'LaunchTo'         = 1   # abrir o Explorer em "Este Computador"
        'ShowTaskViewButton' = 0
    }

    $atual = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    foreach ($k in $ajustes.Keys) {
        New-ItemProperty -Path $atual -Name $k -Value $ajustes[$k] -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log 'Explorer ajustado para o usuario atual'

    $hive = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    if (-not (Test-Path $hive)) { return }

    try {
        & reg.exe load 'HKU\KitDefault' $hive | Out-Null
        $caminho = 'HKU\KitDefault\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        foreach ($k in $ajustes.Keys) {
            & reg.exe add $caminho /v $k /t REG_DWORD /d $ajustes[$k] /f | Out-Null
        }
        Write-Log 'Explorer ajustado para novos perfis (Default)'
    }
    catch { Write-Aviso "nao consegui ajustar o perfil Default: $($_.Exception.Message)" }
    finally {
        # o hive precisa ser liberado antes do unload, senao o arquivo fica travado
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        try { & reg.exe unload 'HKU\KitDefault' | Out-Null } catch { }
    }
}
