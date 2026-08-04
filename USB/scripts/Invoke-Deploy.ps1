#requires -Version 5.1
<#
.SYNOPSIS
    WinDeployKit - preparacao automatica de notebook novo.

.DESCRIPTION
    Executa, em sequencia: remocao do Microsoft 365 de fabrica, limpeza de
    bloatware, instalacao dos aplicativos padrao, instalacao do Office 2016
    a partir da pasta Publico, ajustes de sistema e ingresso no dominio.

    Pode ser executado varias vezes: etapas ja concluidas sao puladas.

.PARAMETER Config
    Caminho de um deploy.psd1 alternativo.

.PARAMETER Recomecar
    Ignora o estado anterior e refaz todas as etapas.

.PARAMETER SemReiniciar
    Nao reinicia ao final, mesmo com ReiniciarNoFinal = $true.

.PARAMETER Simular
    Mostra tudo que seria feito SEM alterar nada na maquina. Serve para
    validar o kit numa maquina de verdade sem risco.

.EXAMPLE
    .\Invoke-Deploy.ps1
.EXAMPLE
    .\Invoke-Deploy.ps1 -Recomecar -SemReiniciar
.EXAMPLE
    .\Invoke-Deploy.ps1 -Simular
#>
[CmdletBinding()]
param(
    [string]$Config,
    [switch]$Recomecar,
    [switch]$SemReiniciar,
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- carga -----

$PastaScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
$PastaUSB     = Split-Path -Parent $PastaScripts

. (Join-Path $PastaScripts 'Lib.ps1')
. (Join-Path $PastaScripts '01-Remove-Office365.ps1')
. (Join-Path $PastaScripts '02-Remove-Bloatware.ps1')
. (Join-Path $PastaScripts '03-Install-Apps.ps1')
. (Join-Path $PastaScripts '04-Install-Office2016.ps1')
. (Join-Path $PastaScripts '05-Ajustes.ps1')
. (Join-Path $PastaScripts '06-Dominio.ps1')
. (Join-Path $PastaScripts '07-Antivirus.ps1')
. (Join-Path $PastaScripts '08-Diagnostico.ps1')
. (Join-Path $PastaScripts '09-Office-Limpeza.ps1')

if (-not (Test-Administrador)) {
    Write-Host 'Este script precisa ser executado como Administrador. Use o INICIAR.cmd.' -ForegroundColor Red
    exit 1
}

Initialize-Ambiente
Set-Simulacao ([bool]$Simular)
if ($Recomecar) { Clear-Estado }

if (-not $Config) { $Config = Join-Path $PastaUSB 'config\deploy.psd1' }
$cfg = Get-KitConfig -Caminho $Config

# separa o historico deste perfil do historico do outro
Set-EscopoEstado ([IO.Path]::GetFileNameWithoutExtension($Config))

# ---------------------------------------------------------------- banner ----

Clear-Host
$so   = Get-CimInstance Win32_OperatingSystem
$maq  = Get-CimInstance Win32_ComputerSystem
$disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"

$perfil = if ($cfg.ModoNomeLab) { 'LABORATORIO' } else { 'ADMINISTRATIVO' }

Write-Host ''
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host "   WinDeployKit  -  Preparacao de maquina  [$perfil]" -ForegroundColor Cyan
Write-Host '  ==========================================================' -ForegroundColor Cyan
if ($Simular) {
    Write-Host '   *** MODO SIMULACAO -- nada sera alterado nesta maquina ***' -ForegroundColor Magenta
}
Write-Host ''
Write-Host "   Perfil      : $(Split-Path $Config -Leaf)"
Write-Host "   Equipamento : $($maq.Manufacturer) $($maq.Model)"
Write-Host "   Nome atual  : $env:COMPUTERNAME"
Write-Host "   Sistema     : $($so.Caption) $($so.OSArchitecture) (build $($so.BuildNumber))"
Write-Host ("   Disco livre : {0:N1} GB de {1:N1} GB" -f ($disco.FreeSpace/1GB), ($disco.Size/1GB))
Write-Host "   Dominio     : $($cfg.Dominio)"
Write-Host "   Log         : $script:ArqLog"
Write-Host ''

# ------------------------------------------------------------ pre-checagens -

$problemas = @()

if (($disco.FreeSpace / 1GB) -lt 15) {
    $problemas += ('Espaco livre insuficiente: {0:N1} GB (minimo 15 GB)' -f ($disco.FreeSpace/1GB))
}

$bateria = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bateria -and $bateria.BatteryStatus -eq 1) {
    Write-Host '   AVISO: notebook na bateria. Conecte o carregador antes de continuar.' -ForegroundColor Yellow
}

if ($cfg.PastaOffice2016 -match '^\\\\([^\\]+)\\') {
    $servidor = $Matches[1]
    if (-not (Test-Connection -ComputerName $servidor -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Host "   AVISO: o servidor de arquivos $servidor nao respondeu ao ping." -ForegroundColor Yellow
        Write-Host '          Confirme que o notebook esta na rede da empresa.' -ForegroundColor Yellow
    }
}

if (Test-RebootPendente) {
    Write-Host '   AVISO: ha uma reinicializacao pendente no Windows.' -ForegroundColor Yellow
}

if ($problemas) {
    Write-Host ''
    foreach ($p in $problemas) { Write-Host "   BLOQUEIO: $p" -ForegroundColor Red }
    Write-Host ''
    exit 1
}

# ------------------------------------------------------- etapas escolhidas --

$etapas = @()
if ($cfg.RemoverOffice365)   { $etapas += 'Remover Microsoft 365 de fabrica' }
if ($cfg.RemoverBloatware)   { $etapas += 'Remover bloatware da Store' }
if ($cfg.InstalarApps)       { $etapas += 'Instalar aplicativos padrao (Chrome etc.)' }
if ($cfg.InstalarOffice2016)  { $etapas += 'Instalar Office 2016' }
if ($cfg.RemoverAntivirusOEM)  { $etapas += 'Remover antivirus de fabrica (McAfee etc.)' }
if ($cfg.InstalarBitdefender) { $etapas += 'Instalar Bitdefender (remove antivirus concorrente)' }
if ($cfg.AplicarAjustes)      { $etapas += 'Ajustes de energia, regiao e Explorer' }
if ($cfg.EntrarNoDominio)     { $etapas += "Entrar no dominio $($cfg.Dominio)" }

Write-Host '   Sera executado:' -ForegroundColor White
foreach ($e in $etapas) { Write-Host "     - $e" -ForegroundColor Gray }
Write-Host ''

$resp = Read-Host '   Continuar? (S/N)'
if ($resp -notmatch '^[SsYy]') { Write-Host '   Cancelado.' -ForegroundColor Yellow; exit 0 }

# ------------------------------------------------------------ coleta dados --

$novoNome   = $null
$credencial = $null

if ($cfg.EntrarNoDominio) { $novoNome = Get-NomeSugerido -Config $cfg }

# A credencial so e necessaria para o dominio ou para buscar o Office na rede.
# Se a ISO do Office ja esta no pendrive, nao precisamos dela por causa disso.
$precisaCred = $cfg.EntrarNoDominio
if ($cfg.InstalarOffice2016 -and -not $precisaCred) {
    $isoNoUSB = @($PastaUSB, (Join-Path $PastaUSB 'payload\office'), (Split-Path -Parent $PastaUSB)) |
                Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
                ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.iso' -File -ErrorAction SilentlyContinue } |
                Where-Object { $_.Name -match 'office' } | Select-Object -First 1
    if (-not $isoNoUSB) { $precisaCred = $true }
}

if ($precisaCred) {
    Write-Host ''
    Write-Host '   Vai abrir a janela de credencial do Windows.' -ForegroundColor Cyan
    Write-Host '   Use um usuario de dominio com permissao para ingressar maquinas.' -ForegroundColor Gray
    Write-Host '   A senha nao e gravada em lugar nenhum.' -ForegroundColor Gray
    $credencial = Get-CredencialDominio -Dominio $cfg.Dominio -Usuario $cfg.UsuarioDominio
}

$inicioGeral = Get-Date

# ------------------------------------------------------------------ etapas --

$acaoDominio = {
    Invoke-Passo -Id 'dominio' -Titulo 'Entrando no dominio' -Acao {
        Invoke-EntrarNoDominio -Config $cfg -Credencial $credencial -NovoNome $novoNome
    } | Out-Null
}

try {
    # Ordem do dominio.
    #  'Ultimo'   (padrao) - o ingresso exige reiniciar; deixar por ultimo evita
    #                        instalar Office numa maquina que vai reiniciar.
    #  'Primeiro'          - para quem depende da pasta de rede autenticada. Com
    #                        a ISO no pendrive isso deixou de ser necessario,
    #                        mas fica disponivel para o fluxo antigo.
    if ($cfg.EntrarNoDominio -and $cfg.OrdemDominio -eq 'Primeiro') {
        & $acaoDominio
    }

    if ($cfg.RemoverOffice365) {
        Invoke-Passo -Id 'office365' -Titulo 'Removendo Microsoft 365 de fabrica' -Acao {
            Invoke-RemoverOffice365 -Config $cfg -PastaUSB $PastaUSB
        } | Out-Null
    }

    if ($cfg.RemoverBloatware) {
        Invoke-Passo -Id 'bloatware' -Titulo 'Removendo bloatware' -Acao {
            Invoke-RemoverBloatware -Config $cfg
        } | Out-Null
    }

    if ($cfg.InstalarApps) {
        Invoke-Passo -Id 'apps' -Titulo 'Instalando aplicativos padrao' -Acao {
            Invoke-InstalarApps -Config $cfg -PastaUSB $PastaUSB
        } | Out-Null
    }

    if ($cfg.InstalarOffice2016) {
        Invoke-Passo -Id 'office2016' -Titulo 'Instalando Office 2016' -Acao {
            Invoke-InstalarOffice2016 -Config $cfg -Credencial $credencial -PastaUSB $PastaUSB
        } | Out-Null
    }

    # antes do Bitdefender: tira o McAfee de fabrica e o pacote provisionado
    # que o reinstala sozinho depois de formatar
    if ($cfg.RemoverAntivirusOEM) {
        Invoke-Passo -Id 'av-oem' -Titulo 'Removendo antivirus de fabrica' -Acao {
            Invoke-RemoverAntivirusOEM -Config $cfg
        } | Out-Null
    }

    if ($cfg.InstalarBitdefender) {
        Invoke-Passo -Id 'bitdefender' -Titulo 'Instalando o Bitdefender' -Acao {
            Invoke-InstalarBitdefender -Config $cfg -PastaUSB $PastaUSB
        } | Out-Null
    }

    if ($cfg.AplicarAjustes) {
        Invoke-Passo -Id 'ajustes' -Titulo 'Aplicando ajustes de sistema' -Acao {
            Invoke-AplicarAjustes -Config $cfg
        } | Out-Null
    }

    # por ultimo: exige reinicializacao
    if ($cfg.EntrarNoDominio -and $cfg.OrdemDominio -ne 'Primeiro') {
        & $acaoDominio
    }
}
catch {
    Write-Log "execucao interrompida: $($_.Exception.Message)" 'ERRO'
}
finally {
    $credencial = $null
    $script:CredDominio = $null
    [gc]::Collect()
}

# ----------------------------------------------------------------- resumo ---

$duracao = (Get-Date) - $inicioGeral

Write-Host ''
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host '   RESUMO' -ForegroundColor Cyan
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host ("   Tempo total : {0:hh\:mm\:ss}" -f $duracao)
Write-Host "   Log completo: $script:ArqLog"
Write-Host ''

if ($script:Avisos.Count) {
    Write-Host "   Avisos ($($script:Avisos.Count)):" -ForegroundColor Yellow
    foreach ($a in $script:Avisos) { Write-Host "     - $a" -ForegroundColor Yellow }
    Write-Host ''
}

if ($script:Falhas.Count) {
    Write-Host "   FALHAS ($($script:Falhas.Count)):" -ForegroundColor Red
    foreach ($f in $script:Falhas) { Write-Host "     - $($f.Passo): $($f.Erro)" -ForegroundColor Red }
    Write-Host ''
    Write-Host '   Corrija o problema e rode o INICIAR.cmd de novo: as etapas que' -ForegroundColor Gray
    Write-Host '   deram certo nao serao refeitas.' -ForegroundColor Gray
}
else {
    Write-Host '   Todas as etapas foram concluidas.' -ForegroundColor Green
}
Write-Host ''

# ------------------------------------------------------------ conferencia ---

Write-Host '   Conferencia final:' -ForegroundColor White
$chrome  = Get-ProgramasInstalados | Where-Object { $_.DisplayName -like '*Google Chrome*' } | Select-Object -First 1
$office  = Get-ProgramasInstalados | Where-Object { $_.DisplayName -match 'Office.*2016' } | Select-Object -First 1
$c2rSobra = Get-ProgramasInstalados | Where-Object { $_.UninstallString -like '*OfficeClickToRun.exe*' }

Write-Host ("     Chrome        : {0}" -f $(if ($chrome) { "OK - $($chrome.DisplayVersion)" } else { 'NAO INSTALADO' })) -ForegroundColor $(if ($chrome) { 'Green' } else { 'Red' })

if ($cfg.InstalarOffice2016) {
    Write-Host ("     Office 2016   : {0}" -f $(if ($office) { "OK - $($office.DisplayName)" } else { 'NAO INSTALADO' })) -ForegroundColor $(if ($office) { 'Green' } else { 'Red' })

    $lic = Get-AtivacaoOffice
    Write-Host ("     Licenca Office: {0}" -f $(if ($lic.Ativado) { 'ATIVADO' } else { $lic.Estado })) `
               -ForegroundColor $(if ($lic.Ativado) { 'Green' } else { 'Red' })
} else {
    Write-Host '     Office 2016   : nao faz parte deste perfil' -ForegroundColor DarkGray
}

Write-Host ("     Microsoft 365 : {0}" -f $(if ($c2rSobra) { 'AINDA PRESENTE' } else { 'removido' })) -ForegroundColor $(if ($c2rSobra) { 'Red' } else { 'Green' })

if ($cfg.InstalarBitdefender) {
    $bd = Test-BitdefenderInstalado
    Write-Host ("     Bitdefender   : {0}" -f $(if ($bd) { 'OK' } else { 'NAO INSTALADO' })) -ForegroundColor $(if ($bd) { 'Green' } else { 'Red' })

    $outros = Get-AntivirusRegistrados | Where-Object {
        $_.Nome -notmatch 'Bitdefender' -and $_.Nome -notmatch 'Windows Defender|Microsoft Defender'
    }
    if ($outros) {
        Write-Host ("     Outro antivirus: AINDA PRESENTE - {0}" -f (($outros.Nome) -join ', ')) -ForegroundColor Red
    }
}

Write-Host ("     Dominio       : {0}" -f $(if ($cfg.EntrarNoDominio -and -not $script:Falhas.Count) { "$($cfg.Dominio) (efetiva apos reiniciar)" } else { 'verificar' })) -ForegroundColor Gray
Write-Host ''

# -------------------------------------------------------------- relatorio ---
# Copia no pendrive: sobrevive a restauracao da maquina e serve de conferencia
# no fim do dia quando foram 10 notebooks.
$linhas = @(
    "Chrome        : $(if ($chrome) { "OK $($chrome.DisplayVersion)" } else { 'NAO INSTALADO' })"
    "Office 2016   : $(if ($cfg.InstalarOffice2016) { if ($office) { 'OK' } else { 'NAO INSTALADO' } } else { 'fora do perfil' })"
    "Licenca Office: $(if ($cfg.InstalarOffice2016) { (Get-AtivacaoOffice).Estado } else { '-' })"
    "Microsoft 365 : $(if ($c2rSobra) { 'AINDA PRESENTE' } else { 'removido' })"
    "Bitdefender   : $(if ($cfg.InstalarBitdefender) { if (Test-BitdefenderInstalado) { 'OK' } else { 'NAO INSTALADO' } } else { 'fora do perfil' })"
    "Dominio       : $(if ($cfg.EntrarNoDominio) { $cfg.Dominio } else { 'nao configurado' })"
    "Tempo total   : $('{0:hh\:mm\:ss}' -f $duracao)"
)
Save-Relatorio -PastaUSB $PastaUSB -Perfil (Split-Path $Config -Leaf) -Linhas $linhas | Out-Null
Write-Host "   Relatorio salvo em $PastaUSB\Relatorios" -ForegroundColor DarkGray
Write-Host ''

# --------------------------------------------------------------- reiniciar --

if ($Simular) {
    Write-Host '   MODO SIMULACAO: nada foi alterado e a maquina nao vai reiniciar.' -ForegroundColor Magenta
    Write-Host ''
    Read-Host '   ENTER para fechar'
}
elseif ($cfg.ReiniciarNoFinal -and -not $SemReiniciar -and -not $script:Falhas.Count) {
    Write-Host '   O computador vai reiniciar em 60 segundos para concluir o ingresso' -ForegroundColor Yellow
    Write-Host '   no dominio. Pressione qualquer tecla para CANCELAR.' -ForegroundColor Yellow

    $fim = (Get-Date).AddSeconds(60)
    $cancelou = $false
    while ((Get-Date) -lt $fim) {
        try {
            if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); $cancelou = $true; break }
        }
        catch { }   # console sem teclado (execucao remota): so aguarda
        Write-Host ("`r   Reiniciando em {0,3} s...  " -f [int]($fim - (Get-Date)).TotalSeconds) -NoNewline
        Start-Sleep -Milliseconds 500
    }
    Write-Host ''

    if ($cancelou) { Write-Host '   Reinicializacao cancelada. Reinicie manualmente depois.' -ForegroundColor Yellow }
    else           { Restart-Computer -Force }
}
else {
    Write-Host '   Reinicie o computador para concluir.' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '   ENTER para fechar'
}
