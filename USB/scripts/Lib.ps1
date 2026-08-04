# ============================================================================
#  WinDeployKit - Biblioteca de funcoes comuns
#  Este arquivo e carregado (dot-source) pelo Invoke-Deploy.ps1
# ============================================================================

$script:RaizLocal   = Join-Path $env:SystemDrive 'WinDeployKit'
$script:PastaLogs   = Join-Path $script:RaizLocal 'Logs'
$script:PastaTemp   = Join-Path $script:RaizLocal 'temp'
$script:ArqEstado   = Join-Path $script:RaizLocal 'estado.json'
$script:ArqLog      = $null
$script:CredDominio = $null
$script:Falhas      = New-Object System.Collections.ArrayList
$script:Avisos      = New-Object System.Collections.ArrayList

# Modo simulacao: mostra tudo que FARIA, sem executar nada. Serve para testar o
# kit numa maquina de verdade sem risco nenhum.
$script:Simulacao   = $false

# Escopo do estado: separa o que ja foi feito no perfil administrativo do que
# foi feito no perfil de laboratorio. Sem isso, preparar uma maquina como lab
# depois de prepara-la como administrativa pularia etapas que precisam rodar.
$script:EscopoEstado = 'geral'

# ---------------------------------------------------------------- ambiente --

function Initialize-Ambiente {
    foreach ($p in @($script:RaizLocal, $script:PastaLogs, $script:PastaTemp)) {
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    $script:ArqLog = Join-Path $script:PastaLogs ('deploy_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Set-Content -Path $script:ArqLog -Value "WinDeployKit - iniciado em $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -Encoding UTF8
}

function Test-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- simulacao --

function Set-Simulacao {
    param([bool]$Ligada)
    $script:Simulacao = $Ligada
}

function Test-Simulacao { return $script:Simulacao }

function Invoke-Mudanca {
    <#
      Envolve QUALQUER alteracao real na maquina (registro, appx, dominio).
      Em modo simulacao apenas registra o que faria e nao executa.
      Use isto em vez de chamar o cmdlet destrutivo direto.
    #>
    param(
        [Parameter(Mandatory)][string]$Descricao,
        [Parameter(Mandatory)][scriptblock]$Acao
    )
    if ($script:Simulacao) {
        Write-Log "[SIMULACAO] faria: $Descricao"
        return
    }
    & $Acao
}

# ------------------------------------------------------------------- log ----

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Mensagem,
        [ValidateSet('INFO', 'OK', 'AVISO', 'ERRO', 'PASSO')][string]$Nivel = 'INFO'
    )
    $hora  = Get-Date -Format 'HH:mm:ss'
    $linha = '[{0}] [{1,-5}] {2}' -f $hora, $Nivel, $Mensagem

    switch ($Nivel) {
        'PASSO' {
            Write-Host ''
            Write-Host ('  ' + ('-' * 70)) -ForegroundColor DarkCyan
            Write-Host ("  >> $Mensagem") -ForegroundColor Cyan
            Write-Host ('  ' + ('-' * 70)) -ForegroundColor DarkCyan
        }
        'OK'    { Write-Host "     [ok]    $Mensagem" -ForegroundColor Green }
        'AVISO' { Write-Host "     [aviso] $Mensagem" -ForegroundColor Yellow }
        'ERRO'  { Write-Host "     [ERRO]  $Mensagem" -ForegroundColor Red }
        default { Write-Host "     $Mensagem" -ForegroundColor Gray }
    }

    if ($script:ArqLog) {
        try { Add-Content -Path $script:ArqLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}

function Write-Aviso {
    param([string]$Mensagem)
    Write-Log $Mensagem 'AVISO'
    [void]$script:Avisos.Add($Mensagem)
}

# --------------------------------------------------------------- config -----

function Get-KitConfig {
    param([string]$Caminho)
    if (-not (Test-Path $Caminho)) { throw "Arquivo de configuracao nao encontrado: $Caminho" }
    Import-PowerShellDataFile -Path $Caminho
}

# ---------------------------------------------------------------- estado ----
# Permite reexecutar o script sem refazer o que ja deu certo.

function Get-Estado {
    if (Test-Path $script:ArqEstado) {
        try { return (Get-Content $script:ArqEstado -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    [pscustomobject]@{ concluidos = @() }
}

function Set-EscopoEstado {
    <#
      Separa o historico por perfil. Uma maquina preparada como administrativa
      e depois reaproveitada como laboratorio precisa refazer as etapas -- sem
      escopo, o estado antigo faria o kit pular tudo.
    #>
    param([string]$Nome)
    if ($Nome) { $script:EscopoEstado = $Nome }
}

function Get-IdEscopado {
    param([string]$Id)
    return ('{0}::{1}' -f $script:EscopoEstado, $Id)
}

function Test-PassoConcluido {
    param([string]$Id)
    $e = Get-Estado
    return ($e.concluidos -contains (Get-IdEscopado $Id))
}

function Set-PassoConcluido {
    param([string]$Id)
    $e = Get-Estado
    $chave = Get-IdEscopado $Id
    if ($e.concluidos -notcontains $chave) {
        $e.concluidos = @($e.concluidos) + $chave
    }
    if ($script:Simulacao) { return }   # simulacao nao grava progresso
    $e | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ArqEstado -Encoding UTF8
}

function Get-PassosConcluidos {
    <#  Lista legivel do que ja foi feito, para mostrar ao tecnico.  #>
    $e = Get-Estado
    @($e.concluidos) | Where-Object { $_ } | ForEach-Object {
        $p = $_ -split '::', 2
        if ($p.Count -eq 2) { [pscustomobject]@{ Perfil = $p[0]; Passo = $p[1] } }
        else                { [pscustomobject]@{ Perfil = 'geral'; Passo = $p[0] } }
    }
}

function Clear-Estado {
    if (Test-Path $script:ArqEstado) { Remove-Item $script:ArqEstado -Force }
}

# ----------------------------------------------------------------- passos ---

function Invoke-Passo {
    <#
      Executa uma etapa registrando log, sucesso/falha e estado.
      -Obrigatorio faz o erro abortar todo o deploy; sem ele o script segue.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][scriptblock]$Acao,
        [switch]$Obrigatorio
    )

    if (Test-PassoConcluido $Id) {
        Write-Log "$Titulo -- ja concluido em execucao anterior, pulando" 'INFO'
        return $true
    }

    Write-Log $Titulo 'PASSO'
    $inicio = Get-Date
    try {
        & $Acao
        Set-PassoConcluido $Id
        $seg = [int]((Get-Date) - $inicio).TotalSeconds
        Write-Log "$Titulo -- concluido em ${seg}s" 'OK'
        return $true
    }
    catch {
        Write-Log "$Titulo -- FALHOU: $($_.Exception.Message)" 'ERRO'
        [void]$script:Falhas.Add([pscustomobject]@{ Passo = $Titulo; Erro = $_.Exception.Message })
        if ($Obrigatorio) { throw }
        return $false
    }
}

# --------------------------------------------------------------- processos --

function Invoke-Processo {
    <#
      Roda um executavel esperando o termino e devolve o codigo de saida.
      -CodigosOk lista os exit codes considerados sucesso (3010 = precisa reiniciar).
    #>
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [string[]]$Argumentos = @(),
        [int[]]$CodigosOk = @(0, 3010, 1641),
        [int]$TimeoutSegundos = 3600,
        [switch]$SemErro
    )

    if ($script:Simulacao) {
        Write-Log ("[SIMULACAO] executaria: {0} {1}" -f $Arquivo, ($Argumentos -join ' '))
        return 0
    }

    Write-Log ("executando: {0} {1}" -f $Arquivo, ($Argumentos -join ' '))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $Arquivo
    $psi.Arguments       = ($Argumentos -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit($TimeoutSegundos * 1000)) {
        try { $proc.Kill() } catch { }
        throw "Tempo esgotado (${TimeoutSegundos}s) executando $Arquivo"
    }
    $code = $proc.ExitCode

    if ($CodigosOk -contains $code) {
        if ($code -in 3010, 1641) { Write-Log "codigo $code -- reinicializacao pendente" 'INFO' }
        return $code
    }

    if ($SemErro) {
        Write-Aviso "$([IO.Path]::GetFileName($Arquivo)) retornou codigo $code"
        return $code
    }
    throw "$([IO.Path]::GetFileName($Arquivo)) retornou codigo $code"
}

# ------------------------------------------------------------- credenciais --

function Get-CredencialDominio {
    param([string]$Dominio, [string]$Usuario)
    if ($script:CredDominio) { return $script:CredDominio }

    $msg = "Usuario com permissao para entrar no dominio $Dominio e ler a pasta Publico"
    if ($Usuario) { $script:CredDominio = Get-Credential -UserName $Usuario -Message $msg }
    else          { $script:CredDominio = Get-Credential -Message $msg }

    if (-not $script:CredDominio) { throw 'Nenhuma credencial informada.' }
    return $script:CredDominio
}

# ---------------------------------------------------------- compartilhamento -

function Connect-Compartilhamento {
    <#
      Garante acesso a um caminho UNC. Se a maquina ainda nao esta no dominio,
      autentica com a credencial informada. Devolve um caminho utilizavel.
      SOMENTE LEITURA: nada e escrito na rede.
    #>
    param(
        [Parameter(Mandatory)][string]$CaminhoUNC,
        [pscredential]$Credencial
    )

    if (Test-Path -LiteralPath $CaminhoUNC) { return $CaminhoUNC }

    if (-not $Credencial) { throw "Sem acesso a $CaminhoUNC e nenhuma credencial fornecida." }

    # raiz do compartilhamento: \\servidor\share
    if ($CaminhoUNC -notmatch '^\\\\([^\\]+)\\([^\\]+)') {
        throw "Caminho UNC invalido: $CaminhoUNC"
    }
    $raiz = '\\{0}\{1}' -f $Matches[1], $Matches[2]
    $nome = 'KITNET'

    if (Get-PSDrive -Name $nome -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name $nome -Force -ErrorAction SilentlyContinue
    }

    Write-Log "autenticando em $raiz como $($Credencial.UserName)"
    New-PSDrive -Name $nome -PSProvider FileSystem -Root $raiz -Credential $Credencial -Scope Global | Out-Null

    # a sessao SMB fica valida para o caminho UNC completo
    if (Test-Path -LiteralPath $CaminhoUNC) { return $CaminhoUNC }

    $relativo = $CaminhoUNC.Substring($raiz.Length).TrimStart('\')
    $viaDrive = Join-Path "${nome}:" $relativo
    if (Test-Path -LiteralPath $viaDrive) { return $viaDrive }

    throw "Nao foi possivel acessar $CaminhoUNC mesmo autenticado."
}

# ------------------------------------------------------------------ utils ---

function Test-PC-NoDominio {
    (Get-CimInstance Win32_ComputerSystem).PartOfDomain
}

function Get-ProgramasInstalados {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $chaves -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, UninstallString, PSChildName
}

function Save-Relatorio {
    <#
      Grava um resumo do que foi feito NESTA maquina, em duas copias:
        1. C:\WinDeployKit\Logs         (some se a maquina for restaurada)
        2. <pendrive>\Relatorios        (sobrevive -- e o historico do lote)
      Serve para conferir 10 notebooks no fim do dia sem depender da memoria.
      NUNCA grava na rede: \\servidor-arquivos e somente leitura.
    #>
    param(
        [string]$PastaUSB,
        [string]$Perfil = '',
        [string[]]$Linhas = @()
    )

    $maq = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $so  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue

    $txt = New-Object System.Collections.ArrayList
    [void]$txt.Add('=' * 64)
    [void]$txt.Add("  WinDeployKit - relatorio da maquina")
    [void]$txt.Add('=' * 64)
    [void]$txt.Add("  Data       : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$txt.Add("  Maquina    : $env:COMPUTERNAME")
    [void]$txt.Add("  Modelo     : $($maq.Manufacturer) $($maq.Model)")
    [void]$txt.Add("  Serie      : $($bios.SerialNumber)")
    [void]$txt.Add("  Sistema    : $($so.Caption) (build $($so.BuildNumber))")
    [void]$txt.Add("  Dominio    : $(if ($maq.PartOfDomain) { $maq.Domain } else { 'fora do dominio' })")
    [void]$txt.Add("  Perfil     : $Perfil")
    [void]$txt.Add("  Tecnico    : $env:USERNAME")
    if ($script:Simulacao) { [void]$txt.Add('  MODO       : SIMULACAO (nada foi alterado)') }
    [void]$txt.Add('')

    foreach ($l in $Linhas) { [void]$txt.Add("  $l") }

    if ($script:Avisos.Count) {
        [void]$txt.Add('')
        [void]$txt.Add("  AVISOS ($($script:Avisos.Count)):")
        foreach ($a in $script:Avisos) { [void]$txt.Add("    - $a") }
    }
    if ($script:Falhas.Count) {
        [void]$txt.Add('')
        [void]$txt.Add("  FALHAS ($($script:Falhas.Count)):")
        foreach ($f in $script:Falhas) { [void]$txt.Add("    - $($f.Passo): $($f.Erro)") }
    }
    [void]$txt.Add('')
    [void]$txt.Add("  Log completo: $script:ArqLog")

    $conteudo = $txt -join "`r`n"
    $nome = ('{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))

    $destinos = @(Join-Path $script:PastaLogs $nome)
    if ($PastaUSB) {
        $pastaRel = Join-Path $PastaUSB 'Relatorios'
        try {
            if (-not (Test-Path $pastaRel)) { New-Item -ItemType Directory -Path $pastaRel -Force | Out-Null }
            $destinos += (Join-Path $pastaRel $nome)
        }
        catch { Write-Log "nao consegui criar a pasta de relatorios no pendrive: $($_.Exception.Message)" }
    }

    foreach ($d in $destinos) {
        try {
            Set-Content -Path $d -Value $conteudo -Encoding UTF8 -ErrorAction Stop
            Write-Log "relatorio salvo em $d"
        }
        catch { Write-Log "nao consegui salvar o relatorio em ${d}: $($_.Exception.Message)" }
    }
    return $conteudo
}

function Test-RebootPendente {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($c in $chaves) { if (Test-Path $c) { return $true } }
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return [bool]$v.PendingFileRenameOperations
}
