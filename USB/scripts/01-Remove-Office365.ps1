# ============================================================================
#  Etapa 01 - Remover Microsoft 365 / Office Click-to-Run que vem de fabrica
# ----------------------------------------------------------------------------
#  IMPORTANTE: so remove instalacoes Click-to-Run (365). Instalacoes MSI
#  (que e o caso do Office 2016 Volume License) NAO sao tocadas, para nao
#  desinstalar justamente o que vamos instalar depois.
# ============================================================================

function Invoke-RemoverOffice365 {
    param([hashtable]$Config, [string]$PastaUSB)

    # A limpeza profunda (09-Office-Limpeza.ps1) usa as ferramentas oficiais da
    # Microsoft em camadas e confere o resultado. E o caminho recomendado --
    # o desinstalador simples abaixo deixa residuo que bloqueia o Office 2016.
    if ($Config.LimpezaProfundaOffice -ne $false -and (Get-Command Invoke-LimpezaProfundaOffice365 -ErrorAction SilentlyContinue)) {
        Invoke-LimpezaProfundaOffice365 -Config $Config -PastaUSB $PastaUSB
        if ($Config.RemoverOneDrive) { Remove-OneDrive }
        return
    }

    $removeuAlgo = $false

    # ---------------------------------------------------------- Click-to-Run
    $c2r = Get-ProgramasInstalados | Where-Object {
        $_.UninstallString -like '*OfficeClickToRun.exe*'
    }

    if (-not $c2r) {
        Write-Log 'nenhuma instalacao Click-to-Run (Microsoft 365) encontrada'
    }

    foreach ($prod in $c2r) {
        Write-Log "removendo: $($prod.DisplayName)"

        if ($prod.UninstallString -match '^"([^"]+)"\s*(.*)$') {
            $exe = $Matches[1]; $arg = $Matches[2]
        }
        elseif ($prod.UninstallString -match '^(\S+\.exe)\s*(.*)$') {
            $exe = $Matches[1]; $arg = $Matches[2]
        }
        else {
            Write-Aviso "nao consegui interpretar o desinstalador de $($prod.DisplayName)"
            continue
        }

        if ($arg -notmatch 'DisplayLevel') { $arg += ' DisplayLevel=False' }
        if ($arg -notmatch 'Forceappshutdown') { $arg += ' Forceappshutdown=True' }

        Invoke-Processo -Arquivo $exe -Argumentos @($arg) -TimeoutSegundos 2400 -SemErro | Out-Null
        $removeuAlgo = $true
    }

    # ------------------------------- Office Deployment Tool (se estiver no USB)
    $odt = Join-Path $PastaUSB 'payload\ODT\setup.exe'
    if ((Test-Path $odt) -and $removeuAlgo) {
        Write-Log 'passando o Office Deployment Tool para limpar sobras'
        $xml = Join-Path $script:PastaTemp 'remover-office.xml'
        @'
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
'@ | Set-Content -Path $xml -Encoding UTF8
        Invoke-Processo -Arquivo $odt -Argumentos @('/configure', "`"$xml`"") -TimeoutSegundos 2400 -SemErro | Out-Null
    }

    # ------------------------------------------------- versoes da Microsoft Store
    $appxOffice = @(
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.Office.Desktop'
        'Microsoft.Office.OneNote'
        'Microsoft.OutlookForWindows'
        'Microsoft.Office.Sway'
        'Microsoft.MicrosoftStickyNotes'
    )

    foreach ($nome in $appxOffice) {
        if ($nome -eq 'Microsoft.MicrosoftStickyNotes') { continue }  # inofensivo, mantido
        Remove-AppxSeguro -Nome $nome
    }

    # ------------------------------------------------------------ avisos MSI
    $msiOffice = Get-ProgramasInstalados | Where-Object {
        $_.DisplayName -match 'Microsoft Office (Professional|Standard|Home)' -and
        $_.UninstallString -like '*MsiExec*'
    }
    foreach ($m in $msiOffice) {
        Write-Aviso "Office MSI ja presente e mantido: $($m.DisplayName) -- confira se e a versao correta"
    }

    if ($Config.RemoverOneDrive) { Remove-OneDrive }
}

function Remove-AppxSeguro {
    param([Parameter(Mandatory)][string]$Nome)

    $pkgs = Get-AppxPackage -Name $Nome -AllUsers -ErrorAction SilentlyContinue
    foreach ($p in $pkgs) {
        try {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "app removido: $($p.Name)"
        }
        catch {
            # AllUsers falha em alguns pacotes; tenta so o usuario atual
            try {
                Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                Write-Log "app removido (usuario atual): $($p.Name)"
            }
            catch { Write-Aviso "nao removi o app $($p.Name): $($_.Exception.Message)" }
        }
    }

    # remove tambem da imagem, para nao voltar em novos perfis
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $Nome }
    foreach ($pp in $prov) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
            Write-Log "removido da imagem: $($pp.DisplayName)"
        }
        catch { Write-Aviso "nao removi da imagem $($pp.DisplayName)" }
    }
}

function Remove-OneDrive {
    Write-Log 'removendo OneDrive pessoal'
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    foreach ($p in @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe")) {
        if (Test-Path $p) { Invoke-Processo -Arquivo $p -Argumentos @('/uninstall') -SemErro | Out-Null }
    }
}
