#requires -Version 5.1
<#
.SYNOPSIS
    Confere a maquina e dispara o "Redefinir este computador".

.DESCRIPTION
    Usado em dois casos:
      -Contexto Funcionario : PC devolvido por alguem que saiu da empresa
      -Contexto Laboratorio : PC de lab entre turmas

    Fluxo:
      1. confere arquivos pessoais, BitLocker e dados para limpar no AD
      2. mostra o que sera PERDIDO
      3. TRAVA: exige digitar o nome do PC
      4. segunda confirmacao
      5. abre o Redefinir do Windows (que ainda pede a confirmacao dele)

    Nada e apagado por este script. Quem apaga e o Windows, depois que voce
    confirma nas telas dele.
#>
[CmdletBinding()]
param(
    [ValidateSet('Funcionario', 'Laboratorio')]
    [string]$Contexto = 'Funcionario'
)

$ErrorActionPreference = 'Stop'

$PastaScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
$PastaUSB     = Split-Path -Parent $PastaScripts
. (Join-Path $PastaScripts 'Lib.ps1')

if (-not (Test-Administrador)) {
    Write-Host 'Execute pelo INICIAR.cmd (precisa de administrador).' -ForegroundColor Red
    exit 1
}

Initialize-Ambiente
$relatorio = New-Object System.Collections.ArrayList
function Rel { param($T) [void]$relatorio.Add($T); Write-Host "   $T" }

$titulo = if ($Contexto -eq 'Laboratorio') { 'PC DE LABORATORIO' } else { 'PC DEVOLVIDO POR FUNCIONARIO' }

Clear-Host
Write-Host ''
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host "   RESTAURAR  -  $titulo" -ForegroundColor Cyan
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '   Este caminho vai RESTAURAR a maquina (apagar tudo e deixar' -ForegroundColor Yellow
Write-Host '   so o Windows). Antes disso, vamos conferir o que tem nela.' -ForegroundColor Yellow
Write-Host ''

# ======================================================= dados da maquina ===

$maq  = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$so   = Get-CimInstance Win32_OperatingSystem

Write-Host '  DADOS DA MAQUINA  (anote para limpar no AD)' -ForegroundColor White
Rel "Nome no AD      : $env:COMPUTERNAME"
Rel "Dominio         : $(if ($maq.PartOfDomain) { $maq.Domain } else { 'fora do dominio' })"
Rel "Fabricante      : $($maq.Manufacturer) $($maq.Model)"
Rel "Numero de serie : $($bios.SerialNumber)"
Rel "Windows         : $($so.Caption) (build $($so.BuildNumber))"
Rel "Checagem em     : $(Get-Date -Format 'dd/MM/yyyy HH:mm')"

if ($maq.PartOfDomain) {
    Write-Host ''
    Write-Host '   >> Depois de restaurar, remova o objeto ' -NoNewline -ForegroundColor Yellow
    Write-Host "$env:COMPUTERNAME" -NoNewline -ForegroundColor White
    Write-Host ' do Active Directory.' -ForegroundColor Yellow
}

# ============================================================== BitLocker ===

Write-Host ''
Write-Host '  BITLOCKER' -ForegroundColor White
try {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On') {
        Rel "ATENCAO: BitLocker LIGADO em $env:SystemDrive"
        $chave = ($bl.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).RecoveryPassword
        if ($chave) {
            Write-Host '   Chave de recuperacao (guarde ANTES de restaurar):' -ForegroundColor Yellow
            foreach ($c in $chave) { Rel "  $c" }
        }
    }
    else { Rel "BitLocker desligado em $env:SystemDrive" }
}
catch {
    Rel "BitLocker: NAO VERIFICADO -- $($_.Exception.Message.Split([char]10)[0].Trim())"
    Write-Host '   Confira em: Painel de Controle > Criptografia de Unidade de Disco BitLocker' -ForegroundColor Yellow
}

# ================================================= arquivos dos perfis ======

Write-Host ''
Write-Host '  ARQUIVOS NAS PASTAS PESSOAIS' -ForegroundColor White
Write-Host '  (TUDO isso vai ser APAGADO na restauracao)' -ForegroundColor Yellow
Write-Host ''

$pastasPessoais = 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music'
$achouCoisa   = $false
$semPermissao = @()
$totalGeralMB = 0

$perfis = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' }

foreach ($perfil in $perfis) {
    $itens     = @()
    $totalMB   = 0
    $bloqueado = $false

    foreach ($sub in $pastasPessoais) {
        $caminho = Join-Path $perfil.FullName $sub

        # Test-Path LANCA excecao em perfil de outro usuario sem permissao.
        # Precisamos distinguir "vazio" de "nao consegui ler" -- dizer que
        # esta vazio quando foi acesso negado faria o tecnico restaurar e
        # perder arquivo do funcionario.
        $existe = $false
        try { $existe = Test-Path -LiteralPath $caminho -ErrorAction Stop }
        catch { $bloqueado = $true; continue }
        if (-not $existe) { continue }

        $erros = $null
        $arquivos = Get-ChildItem -LiteralPath $caminho -Recurse -File -Force `
                                  -ErrorAction SilentlyContinue -ErrorVariable erros
        if ($erros) { $bloqueado = $true }
        if (-not $arquivos) { continue }

        $mb = [math]::Round(($arquivos | Measure-Object Length -Sum).Sum / 1MB, 1)
        $totalMB += $mb
        $itens += '{0}: {1} arquivo(s), {2} MB' -f $sub, $arquivos.Count, $mb
    }

    $totalGeralMB += $totalMB

    if ($itens) {
        $achouCoisa = $true
        Write-Host "   [$($perfil.Name)]  total $totalMB MB" -ForegroundColor $(if ($totalMB -gt 50) { 'Yellow' } else { 'Gray' })
        [void]$relatorio.Add("Perfil $($perfil.Name) -- total $totalMB MB")
        foreach ($i in $itens) {
            Write-Host "      $i" -ForegroundColor Gray
            [void]$relatorio.Add("   $i")
        }
    }
    elseif (-not $bloqueado) {
        Write-Host "   [$($perfil.Name)]  pastas pessoais vazias" -ForegroundColor DarkGray
        [void]$relatorio.Add("Perfil $($perfil.Name) -- vazio")
    }

    if ($bloqueado) {
        $semPermissao += $perfil.Name
        Write-Host "   [$($perfil.Name)]  SEM PERMISSAO DE LEITURA -- confira na mao" -ForegroundColor Red
        [void]$relatorio.Add("Perfil $($perfil.Name) -- ACESSO NEGADO, NAO CONFERIDO")
    }
}

if (-not $achouCoisa -and -not $semPermissao) {
    Write-Host '   Nenhum arquivo pessoal encontrado.' -ForegroundColor Green
}

if ($semPermissao) {
    Write-Host ''
    Write-Host "   ATENCAO: nao consegui ler o(s) perfil(is): $($semPermissao -join ', ')" -ForegroundColor Red
    Write-Host '   NAO restaure sem abrir essas pastas manualmente pelo Explorer.' -ForegroundColor Red
}

# ============================================================== relatorio ===

$arqRel = Join-Path $script:PastaLogs ("restaurar_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
$relatorio | Set-Content -Path $arqRel -Encoding UTF8
Write-Host ''
Write-Host "  Relatorio salvo em: $arqRel" -ForegroundColor Cyan

try {
    $pastaRel = Join-Path $PastaUSB 'relatorios'
    if (-not (Test-Path $pastaRel)) { New-Item -ItemType Directory -Path $pastaRel -Force | Out-Null }
    Copy-Item $arqRel (Join-Path $pastaRel (Split-Path $arqRel -Leaf)) -Force
    Write-Host "  Copia no pendrive : $pastaRel" -ForegroundColor Cyan
}
catch { Write-Host '  (nao consegui copiar para o pendrive -- so no disco local)' -ForegroundColor DarkGray }

# ====================================================== TRAVA DE SEGURANCA ==

Write-Host ''
Write-Host '  ##########################################################' -ForegroundColor Red
Write-Host '  #                                                        #' -ForegroundColor Red
Write-Host '  #   A T E N C A O  -  ACAO SEM VOLTA                     #' -ForegroundColor Red
Write-Host '  #                                                        #' -ForegroundColor Red
Write-Host '  ##########################################################' -ForegroundColor Red
Write-Host ''
Write-Host "   Maquina  : $env:COMPUTERNAME" -ForegroundColor White
Write-Host "   Modelo   : $($maq.Manufacturer) $($maq.Model)" -ForegroundColor White
Write-Host "   Serie    : $($bios.SerialNumber)" -ForegroundColor White
Write-Host ("   Sera perdido: {0:N0} MB de arquivos pessoais em {1} perfil(is)" -f $totalGeralMB, $perfis.Count) -ForegroundColor Yellow
Write-Host ''
Write-Host '   Vai ser apagado: todos os arquivos, programas, contas locais' -ForegroundColor Yellow
Write-Host '   e configuracoes. A maquina volta com o Windows zerado.' -ForegroundColor Yellow
Write-Host ''

if ($semPermissao) {
    Write-Host '   >>> Ha perfil que NAO foi conferido. Tem certeza mesmo? <<<' -ForegroundColor Red
    Write-Host ''
}

# ---- trava 1: digitar o nome da maquina ------------------------------------
Write-Host '   TRAVA 1 de 2' -ForegroundColor Cyan
Write-Host "   Para confirmar, digite o nome da maquina exatamente: $env:COMPUTERNAME" -ForegroundColor Gray
$d1 = (Read-Host '   Nome da maquina').Trim()

if ($d1 -ne $env:COMPUTERNAME) {
    Write-Host ''
    Write-Host '   Nome nao confere. RESTAURACAO CANCELADA. Nada foi alterado.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   ENTER para fechar'
    exit 0
}

# ---- trava 2: confirmar a palavra ------------------------------------------
Write-Host ''
Write-Host '   TRAVA 2 de 2' -ForegroundColor Cyan
Write-Host '   Digite RESTAURAR (em maiusculas) para prosseguir.' -ForegroundColor Gray
$d2 = (Read-Host '   Confirmacao').Trim()

if ($d2 -cne 'RESTAURAR') {
    Write-Host ''
    Write-Host '   Confirmacao nao confere. RESTAURACAO CANCELADA. Nada foi alterado.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   ENTER para fechar'
    exit 0
}

Write-Log "restauracao autorizada pelo tecnico em $env:COMPUTERNAME (contexto: $Contexto)"

# ============================================================ instrucoes ====

Clear-Host
Write-Host ''
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host '   ABRINDO O REDEFINIR DO WINDOWS' -ForegroundColor Cyan
Write-Host '  ==========================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '   Nas telas do Windows, escolha exatamente:' -ForegroundColor White
Write-Host ''
Write-Host '      1) Remover tudo' -ForegroundColor Green
Write-Host '      2) Reinstalacao local     (mais rapido que baixar da nuvem)' -ForegroundColor Green
Write-Host '      3) Alterar configuracoes  ->  Dados: Nao' -ForegroundColor Green
Write-Host '                                    Apps pre-instalados: Nao' -ForegroundColor Green
Write-Host ''
Write-Host '   A opcao "apps pre-instalados: Nao" evita o bloatware voltar.' -ForegroundColor Gray
Write-Host ''
Write-Host '  ----------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host '   DEPOIS QUE TERMINAR:' -ForegroundColor White
if ($Contexto -eq 'Laboratorio') {
    Write-Host '      -> rode este pendrive e escolha a opcao [4]' -ForegroundColor Cyan
    Write-Host '         (Preparar PC de laboratorio)' -ForegroundColor Cyan
}
else {
    Write-Host '      -> rode este pendrive e escolha a opcao [1]' -ForegroundColor Cyan
    Write-Host '         (Preparar PC administrativo)' -ForegroundColor Cyan
}
Write-Host "      -> remova $env:COMPUTERNAME do Active Directory" -ForegroundColor Cyan
Write-Host '  ----------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host ''

try {
    Start-Process 'systemreset.exe' -ArgumentList '-factoryreset'
    Write-Host '   Tela de restauracao aberta. Siga as instrucoes acima.' -ForegroundColor Green
}
catch {
    Write-Host "   Nao consegui abrir automaticamente ($($_.Exception.Message))." -ForegroundColor Yellow
    Write-Host '   Abra na mao: Configuracoes > Sistema > Recuperacao > Redefinir o PC' -ForegroundColor Yellow
    try { Start-Process 'ms-settings:recovery' } catch { }
}

Write-Host ''
Read-Host '   ENTER para fechar esta janela'
