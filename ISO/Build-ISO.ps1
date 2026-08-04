#requires -Version 5.1
<#
.SYNOPSIS
    Gera uma ISO do Windows desatendida com o WinDeployKit embutido.

.DESCRIPTION
    Pega uma ISO original do Windows (baixada do site da Microsoft), injeta o
    autounattend.xml e a pasta WinDeployKit, e grava uma ISO nova e bootavel.

    Pre-requisitos:
      - ISO original do Windows 10/11 (Media Creation Tool ou site da MS)
      - Windows ADK -> "Deployment Tools" instalado (fornece o oscdimg.exe)
        https://learn.microsoft.com/windows-hardware/get-started/adk-install
      - ~20 GB livres para a area de trabalho temporaria
      - Executar como Administrador

    Depois de gerar, grave no pendrive com o Rufus (modo GPT/UEFI) ou com o
    Ventoy. A ISO passa de 4 GB, entao o pendrive precisa ser NTFS ou exFAT
    (o Rufus resolve isso sozinho).

.PARAMETER ISOBase
    Caminho da ISO original do Windows.

.PARAMETER Saida
    Caminho da ISO que sera gerada.

.PARAMETER PastaTrabalho
    Pasta temporaria. Padrao: %TEMP%\Kit-ISO

.EXAMPLE
    .\Build-ISO.ps1 -ISOBase "D:\Win11_24H2_BrazilianPortuguese_x64.iso" -Saida "D:\Win11-Kit.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ISOBase,
    [Parameter(Mandatory)][string]$Saida,
    [string]$PastaTrabalho = (Join-Path $env:TEMP 'Kit-ISO')
)

$ErrorActionPreference = 'Stop'

$RaizISO      = Split-Path -Parent $MyInvocation.MyCommand.Path
$RaizKit      = Split-Path -Parent $RaizISO
$PastaUSB     = Join-Path $RaizKit 'USB'
$Autounattend = Join-Path $RaizISO 'autounattend.xml'

function Escrever { param($T, $C = 'Gray') Write-Host "  $T" -ForegroundColor $C }

# --------------------------------------------------------------- validacoes -

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole('Administrators')) {
    throw 'Execute este script como Administrador.'
}

if (-not (Test-Path $ISOBase))      { throw "ISO base nao encontrada: $ISOBase" }
if (-not (Test-Path $Autounattend)) { throw "autounattend.xml nao encontrado: $Autounattend" }
if (-not (Test-Path $PastaUSB))     { throw "Pasta USB do kit nao encontrada: $PastaUSB" }

# o XML precisa estar bem formado, senao o Windows Setup ignora o arquivo
# silenciosamente e a instalacao vira manual depois de 20 minutos de build.
try { [void][xml](Get-Content $Autounattend -Raw) }
catch { throw "autounattend.xml invalido: $($_.Exception.Message)" }

# senha placeholder ainda no arquivo? nao gera a ISO.
if ((Get-Content $Autounattend -Raw) -match 'TROQUE-ESTA-SENHA') {
    throw @"
O autounattend.xml ainda esta com a senha de exemplo.
Abra $Autounattend, troque as duas ocorrencias de TROQUE-ESTA-SENHA pela senha
do administrador local, e rode este script de novo.
"@
}

# oscdimg
$oscdimg = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools' `
           -Filter 'oscdimg.exe' -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -like '*amd64*' } | Select-Object -First 1
if (-not $oscdimg) {
    $oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if (-not $oscdimg) {
        throw 'oscdimg.exe nao encontrado. Instale o Windows ADK -> Deployment Tools.'
    }
}
$oscdimgPath = if ($oscdimg.FullName) { $oscdimg.FullName } else { $oscdimg.Source }
Escrever "oscdimg: $oscdimgPath" 'DarkGray'

# ------------------------------------------------------------ area de trabalho

if (Test-Path $PastaTrabalho) {
    Escrever "limpando area de trabalho anterior: $PastaTrabalho"
    Remove-Item $PastaTrabalho -Recurse -Force
}
New-Item -ItemType Directory -Path $PastaTrabalho -Force | Out-Null

$img = $null
try {
    Escrever "montando $([IO.Path]::GetFileName($ISOBase))" 'Cyan'
    $img   = Mount-DiskImage -ImagePath (Resolve-Path $ISOBase).Path -PassThru
    $letra = ($img | Get-Volume).DriveLetter
    if (-not $letra) { throw 'nao consegui montar a ISO base' }
    $origem = "${letra}:\"

    Escrever "copiando o conteudo da ISO (alguns minutos)" 'Cyan'
    & robocopy.exe $origem $PastaTrabalho /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy retornou $LASTEXITCODE" }
}
finally {
    if ($img) { Dismount-DiskImage -ImagePath (Resolve-Path $ISOBase).Path | Out-Null }
}

# arquivos vindos de ISO chegam somente-leitura
& attrib.exe -R "$PastaTrabalho\*.*" /S /D | Out-Null

# ----------------------------------------------------------------- injecao --

Escrever 'injetando autounattend.xml na raiz' 'Cyan'
Copy-Item $Autounattend (Join-Path $PastaTrabalho 'autounattend.xml') -Force
# alguns instaladores procuram tambem em sources\
Copy-Item $Autounattend (Join-Path $PastaTrabalho 'sources\autounattend.xml') -Force

Escrever 'injetando o kit WinDeployKit (sources\$OEM$\$1\WinDeployKit)' 'Cyan'
$oem = Join-Path $PastaTrabalho 'sources\$OEM$\$1\WinDeployKit'
New-Item -ItemType Directory -Path $oem -Force | Out-Null
& robocopy.exe $PastaUSB $oem /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy do kit retornou $LASTEXITCODE" }

# ----------------------------------------------------------------- gera ISO -

$etfs = Join-Path $PastaTrabalho 'boot\etfsboot.com'
$efi  = Join-Path $PastaTrabalho 'efi\microsoft\boot\efisys.bin'
if (-not (Test-Path $efi)) { throw "efisys.bin nao encontrado -- a ISO base parece invalida." }

$bootdata = if (Test-Path $etfs) {
    "2#p0,e,b`"$etfs`"#pEF,e,b`"$efi`""     # BIOS + UEFI
} else {
    "1#pEF,e,b`"$efi`""                       # so UEFI
}

Escrever "gerando $Saida (isso demora)" 'Cyan'
$argumentos = @(
    '-m'                     # sem limite de tamanho
    '-o'                     # otimiza arquivos duplicados
    '-u2'                    # UDF
    '-udfver102'
    '-lWIN_KIT'            # rotulo
    "-bootdata:$bootdata"
    "`"$PastaTrabalho`""
    "`"$Saida`""
)

$p = Start-Process -FilePath $oscdimgPath -ArgumentList $argumentos -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "oscdimg retornou $($p.ExitCode)" }

$tam = [math]::Round((Get-Item $Saida).Length / 1GB, 2)

Write-Host ''
Escrever "ISO gerada: $Saida ($tam GB)" 'Green'
Write-Host ''
Escrever 'Proximo passo: grave no pendrive com o Rufus.' 'White'
Escrever '  - Esquema de particao: GPT   |   Sistema de destino: UEFI' 'Gray'
Escrever '  - Deixe o Rufus escolher NTFS (a imagem passa de 4 GB)' 'Gray'
Escrever '  - Nao marque "Windows To Go"' 'Gray'
Write-Host ''
Escrever "Limpe a area temporaria quando quiser: Remove-Item '$PastaTrabalho' -Recurse -Force" 'DarkGray'
Write-Host ''
