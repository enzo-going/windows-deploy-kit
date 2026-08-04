#requires -Version 5.1
<#
.SYNOPSIS
    Prepara o pendrive do WinDeployKit: baixa os instaladores offline e copia
    o kit para o pendrive.

.DESCRIPTION
    Rode ESTE script no seu computador (com internet), nao no notebook novo.
    Ele baixa os instaladores para USB\payload\apps e depois copia toda a
    pasta USB para a raiz do pendrive.

.PARAMETER Pendrive
    Letra do pendrive, ex.: E:  (omita para so baixar o payload)

.PARAMETER SomenteBaixar
    Baixa os instaladores e nao copia nada.

.PARAMETER BaixarFerramentasOffice
    Baixa o SaRA (ferramenta oficial da Microsoft para remover Office que nao
    desinstala). Sem ela, o Office 2016 pode nao instalar por residuo do 365.

.PARAMETER PastaDestino
    Nome da pasta no pendrive. Padrao: Teste_Programa (a que ja esta em uso).

.EXAMPLE
    .\Preparar-Pendrive.ps1 -Pendrive E:
.EXAMPLE
    .\Preparar-Pendrive.ps1 -BaixarFerramentasOffice -Pendrive D:
#>
[CmdletBinding()]
param(
    [string]$Pendrive,
    [switch]$SomenteBaixar,
    [switch]$BaixarFerramentasOffice,
    [string]$PastaDestino = 'Teste_Programa'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Raiz       = Split-Path -Parent $MyInvocation.MyCommand.Path
$PastaUSB   = Join-Path $Raiz 'USB'
$PastaApps  = Join-Path $PastaUSB 'payload\apps'

New-Item -ItemType Directory -Path $PastaApps -Force | Out-Null

# ---------------------------------------------------------------- downloads -

$downloads = @(
    @{
        Nome    = 'Google Chrome Enterprise (MSI 64 bits)'
        Url     = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
        Destino = 'GoogleChromeEnterprise64.msi'
    }
    @{
        Nome    = '7-Zip 64 bits'
        Url     = 'https://www.7-zip.org/a/7z2408-x64.msi'
        Destino = '7z-x64.msi'
    }
)

Write-Host ''
Write-Host '  Baixando instaladores offline...' -ForegroundColor Cyan
Write-Host ''

foreach ($d in $downloads) {
    $destino = Join-Path $PastaApps $d.Destino

    if (Test-Path $destino) {
        Write-Host "  [ja existe] $($d.Nome)" -ForegroundColor DarkGray
        continue
    }

    try {
        Write-Host "  [baixando] $($d.Nome)" -ForegroundColor Gray
        Invoke-WebRequest -Uri $d.Url -OutFile $destino -UseBasicParsing
        $mb = [math]::Round((Get-Item $destino).Length / 1MB, 1)
        Write-Host "  [ok]       $($d.Destino)  ($mb MB)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FALHOU]   $($d.Nome): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "             Baixe manualmente e salve como $destino" -ForegroundColor Yellow
        if (Test-Path $destino) { Remove-Item $destino -Force }
    }
}

# ------------------------------------------- ferramentas de remocao do Office -
# O Office 2016 MSI nao instala se sobrar residuo de Click-to-Run. Estas sao as
# ferramentas OFICIAIS da Microsoft para remover Office que nao sai pelo
# caminho normal. Sem elas o kit ainda funciona, mas os casos teimosos falham.

$pastaOffice = Join-Path $PastaUSB 'payload\office'

if ($BaixarFerramentasOffice) {
    Write-Host ''
    Write-Host '  Baixando ferramentas de remocao do Office...' -ForegroundColor Cyan
    Write-Host ''

    # ---- SaRA (Support and Recovery Assistant, versao de linha de comando)
    $destSaRA = Join-Path $pastaOffice 'SaRA'
    if (Test-Path (Join-Path $destSaRA 'SaRAcmd.exe')) {
        Write-Host '  [ja existe] SaRA' -ForegroundColor DarkGray
    }
    else {
        try {
            Write-Host '  [baixando] SaRA (ferramenta oficial de remocao do Office)' -ForegroundColor Gray
            $zip = Join-Path $env:TEMP 'SaRA_Enterprise.zip'
            Invoke-WebRequest -Uri 'https://aka.ms/SaRA_EnterpriseVersionFiles' -OutFile $zip -UseBasicParsing
            New-Item -ItemType Directory -Path $destSaRA -Force | Out-Null
            Expand-Archive -LiteralPath $zip -DestinationPath $destSaRA -Force
            Remove-Item $zip -Force -ErrorAction SilentlyContinue

            # o zip as vezes traz uma subpasta; sobe o SaRAcmd.exe para a raiz
            if (-not (Test-Path (Join-Path $destSaRA 'SaRAcmd.exe'))) {
                $achado = Get-ChildItem -LiteralPath $destSaRA -Filter 'SaRAcmd.exe' -Recurse -File |
                          Select-Object -First 1
                if ($achado) { Copy-Item $achado.FullName -Destination $destSaRA -Force }
            }

            if (Test-Path (Join-Path $destSaRA 'SaRAcmd.exe')) {
                Write-Host '  [ok]       SaRAcmd.exe' -ForegroundColor Green
            } else {
                Write-Host '  [FALHOU]   SaRAcmd.exe nao encontrado dentro do pacote' -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  [FALHOU]   SaRA: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '             Baixe manualmente: https://aka.ms/SaRA_EnterpriseVersionFiles' -ForegroundColor Yellow
            Write-Host "             e extraia em $destSaRA" -ForegroundColor Yellow
        }
    }

    # ---- ODT (Office Deployment Tool)
    $destODT = Join-Path $pastaOffice 'ODT'
    if (Test-Path (Join-Path $destODT 'setup.exe')) {
        Write-Host '  [ja existe] ODT' -ForegroundColor DarkGray
    }
    else {
        Write-Host ''
        Write-Host '  O Office Deployment Tool e um executavel auto-extraivel da Microsoft.' -ForegroundColor Gray
        Write-Host '  Baixe em: https://www.microsoft.com/download/details.aspx?id=49117' -ForegroundColor Gray
        Write-Host "  Rode: officedeploymenttool_*.exe /quiet /extract:`"$destODT`"" -ForegroundColor Gray
        Write-Host '  (o SaRA acima ja cobre a maioria dos casos; o ODT e a segunda camada)' -ForegroundColor DarkGray
    }
}
else {
    Write-Host ''
    Write-Host '  DICA: rode com -BaixarFerramentasOffice para baixar o SaRA, a' -ForegroundColor Yellow
    Write-Host '  ferramenta oficial que remove Microsoft 365 teimoso. Sem ela, a' -ForegroundColor Yellow
    Write-Host '  instalacao do Office 2016 pode falhar por residuo de Click-to-Run.' -ForegroundColor Yellow
}

# ------------------------------------------------------------------- copia --

if ($SomenteBaixar -or -not $Pendrive) {
    Write-Host ''
    Write-Host "  Payload pronto em: $PastaApps" -ForegroundColor Green
    Write-Host '  Rode de novo com -Pendrive E: para copiar o kit.' -ForegroundColor Gray
    Write-Host ''
    return
}

$letra = $Pendrive.TrimEnd(':\') + ':'
$vol   = Get-Volume -DriveLetter $letra[0] -ErrorAction SilentlyContinue
if (-not $vol) { throw "Unidade $letra nao encontrada." }

Write-Host ''
Write-Host "  Destino: $letra  ($($vol.FileSystemLabel)) - $([math]::Round($vol.SizeRemaining/1GB,1)) GB livres" -ForegroundColor Cyan
$ok = Read-Host '  Copiar o kit para essa unidade? (S/N)'
if ($ok -notmatch '^[SsYy]') { Write-Host '  Cancelado.' -ForegroundColor Yellow; return }

$destino = Join-Path "$letra\" $PastaDestino
Write-Host "  Copiando para $destino ..." -ForegroundColor Gray

# /E e nao /MIR: os arquivos pesados (ISO do Office, kit do Bitdefender) ficam
# SO no pendrive para nao duplicar 1,4 GB no disco. /MIR apagaria todos eles.
& robocopy.exe $PastaUSB $destino /E /NFL /NDL /NJH /NJS /R:2 /W:2 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy retornou $LASTEXITCODE" }

# atalho na raiz para nao precisar entrar na pasta
$atalho = Join-Path "$letra\" 'PREPARAR NOTEBOOK.cmd'
@"
@echo off
start "" "%~dp0$PastaDestino\INICIAR.cmd"
"@ | Set-Content -Path $atalho -Encoding ASCII

Write-Host ''
Write-Host '  Pendrive pronto.' -ForegroundColor Green
Write-Host "  No notebook novo: abra $letra\ e execute 'PREPARAR NOTEBOOK.cmd'." -ForegroundColor Gray
Write-Host ''
