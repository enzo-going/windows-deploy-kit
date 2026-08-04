# ============================================================================
#  Etapa 09 - Limpeza profunda do Office e diagnostico de licenca
# ----------------------------------------------------------------------------
#  POR QUE ESTE ARQUIVO EXISTE
#
#  O Office 2016 MSI se RECUSA a instalar se sobrar qualquer rastro de
#  Click-to-Run (Microsoft 365) na maquina. O desinstalador padrao
#  (OfficeClickToRun.exe) tira o produto mas costuma deixar para tras:
#      - o servico ClickToRunSvc
#      - a chave HKLM\SOFTWARE\Microsoft\Office\ClickToRun
#      - pacotes Appx "Microsoft.Office.Desktop*"
#      - entradas de desinstalacao orfas
#
#  E por isso que a instalacao falha com UM ERRO DIFERENTE A CADA TENTATIVA:
#  cada rodada remove um pedaco distinto e o setup reclama do que sobrou.
#
#  A solucao nao e forca bruta (apagar pasta do Office na mao quebra o MSI que
#  queremos instalar). A solucao e:
#      1. usar a ferramenta OFICIAL de remocao completa (SaRA ou ODT)
#      2. CONFERIR antes de instalar, e recusar com uma mensagem util
#         em vez de deixar o setup falhar no meio
# ============================================================================

# ---- identificador do Office no licenciamento do Windows -------------------
$script:AppIdOffice = '0ff1ce15-a989-479d-af46-f275c6370663'

function Get-EstadoOffice {
    <#
      Retrato completo do Office nesta maquina. SOMENTE LEITURA.
      Usado pelo diagnostico, pela pre-checagem e pelo relatorio.
    #>
    $prog = Get-ProgramasInstalados

    $c2r = @($prog | Where-Object { $_.UninstallString -like '*OfficeClickToRun.exe*' })
    $msi = @($prog | Where-Object {
        $_.DisplayName -match 'Microsoft Office (Professional|Standard|Home)' -and
        $_.UninstallString -like '*MsiExec*'
    })

    # residuos que bloqueiam a instalacao do 2016
    $residuos = @()

    $svc = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
    if ($svc) { $residuos += "servico ClickToRunSvc ($($svc.Status))" }

    foreach ($ch in @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\ClickToRun'
    )) {
        if (Test-Path $ch) { $residuos += "chave de registro $ch" }
    }

    $appx = @()
    try {
        $appx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^Microsoft\.Office\.Desktop' } |
                  Select-Object -ExpandProperty Name -Unique)
    } catch { }
    foreach ($a in $appx) { $residuos += "pacote da Store $a" }

    [pscustomobject]@{
        ClickToRun    = $c2r
        MSI           = $msi
        TemC2R        = [bool]$c2r
        Tem2016       = [bool](Test-Office2016Instalado)
        Residuos      = $residuos
        TemResiduo    = [bool]$residuos
        PodeInstalar  = (-not $c2r -and -not $residuos)
    }
}

function Test-BloqueioOffice2016 {
    <#
      Responde: da para instalar o Office 2016 AGORA?
      Devolve a lista de motivos que impedem. Lista vazia = caminho livre.
      Chamado ANTES de montar a ISO -- falhar aqui custa segundos;
      falhar no meio do setup custa 15 minutos e deixa sujeira.
    #>
    $est = Get-EstadoOffice
    $motivos = @()

    foreach ($p in $est.ClickToRun) {
        $motivos += "Microsoft 365 / Click-to-Run ainda instalado: $($p.DisplayName)"
    }
    foreach ($r in $est.Residuos) {
        $motivos += "residuo de Click-to-Run: $r"
    }

    if (Test-RebootPendente) {
        $motivos += 'ha uma reinicializacao pendente -- o setup do Office falha nesse estado'
    }

    return $motivos
}

function Invoke-LimpezaProfundaOffice365 {
    <#
      Remocao COMPLETA de Click-to-Run, em camadas, da mais forte para a mais
      fraca, usando so ferramenta oficial da Microsoft:

        1. SaRA  (Support and Recovery Assistant, modo linha de comando)
           -> e a ferramenta que a propria Microsoft manda usar quando o
              Office nao desinstala. Remove ate instalacao quebrada.
        2. ODT   (Office Deployment Tool) com <Remove All="TRUE"/>
        3. OfficeClickToRun.exe (o desinstalador do proprio produto)

      NAO apagamos pasta do Office na mao: as pastas sao compartilhadas com o
      MSI do 2016 que queremos instalar depois, e apagar quebraria justamente
      o alvo. Se sobrar residuo depois das tres camadas, avisamos com
      instrucao clara em vez de improvisar.
    #>
    param([hashtable]$Config, [string]$PastaUSB)

    $antes = Get-EstadoOffice

    if (-not $antes.TemC2R -and -not $antes.TemResiduo) {
        Write-Log 'nenhum Click-to-Run e nenhum residuo -- caminho ja esta livre'
        return
    }

    foreach ($p in $antes.ClickToRun) { Write-Log "encontrado: $($p.DisplayName)" }
    foreach ($r in $antes.Residuos)   { Write-Log "residuo: $r" }

    # ------------------------------------------------------- camada 1: SaRA --
    $sara = Get-FerramentaOffice -PastaUSB $PastaUSB -Config $Config -Tipo 'SaRA'
    if ($sara) {
        Write-Log 'camada 1: SaRA (ferramenta oficial de remocao da Microsoft)'
        Invoke-Processo -Arquivo $sara -Argumentos @(
            '-S', 'OfficeScrubScenario', '-AcceptEula', '-OfficeVersion', 'All'
        ) -CodigosOk @(0, 3010, 1641) -TimeoutSegundos 3600 -SemErro | Out-Null
    }

    # -------------------------------------------------------- camada 2: ODT --
    if ((Get-EstadoOffice).TemC2R -or (Get-EstadoOffice).TemResiduo) {
        $odt = Get-FerramentaOffice -PastaUSB $PastaUSB -Config $Config -Tipo 'ODT'
        if ($odt) {
            Write-Log 'camada 2: Office Deployment Tool (Remove All)'
            $xml = Join-Path $script:PastaTemp 'remover-office.xml'
            $conteudo = @'
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
'@
            Invoke-Mudanca -Descricao "gravar $xml" -Acao {
                Set-Content -Path $xml -Value $conteudo -Encoding UTF8
            }
            if (-not $script:Simulacao) {
                Invoke-Processo -Arquivo $odt -Argumentos @('/configure', "`"$xml`"") `
                                -CodigosOk @(0, 3010, 1641) -TimeoutSegundos 3600 -SemErro | Out-Null
            }
        }
    }

    # --------------------------------------- camada 3: desinstalador proprio --
    foreach ($prod in (Get-EstadoOffice).ClickToRun) {
        Write-Log "camada 3: desinstalador do proprio produto -- $($prod.DisplayName)"
        $cmd = Get-ComandoDesinstalacao -Programa $prod
        if (-not $cmd) {
            Write-Aviso "nao consegui interpretar o desinstalador de $($prod.DisplayName)"
            continue
        }
        $argumentos = @($cmd.Argumentos)
        if (($argumentos -join ' ') -notmatch 'DisplayLevel')     { $argumentos += 'DisplayLevel=False' }
        if (($argumentos -join ' ') -notmatch 'Forceappshutdown') { $argumentos += 'Forceappshutdown=True' }
        Invoke-Processo -Arquivo $cmd.Arquivo -Argumentos $argumentos `
                        -TimeoutSegundos 2400 -SemErro | Out-Null
    }

    # ------------------------------------------------ pacotes Appx do Office --
    foreach ($nome in @(
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.Office.Desktop',
        'Microsoft.Office.OneNote', 'Microsoft.OutlookForWindows', 'Microsoft.Office.Sway'
    )) {
        Remove-AppxSeguro -Nome $nome
    }

    # ------------------------------------------------------------ conferencia -
    $depois = Get-EstadoOffice
    if ($depois.PodeInstalar) {
        Write-Log 'limpeza concluida: caminho livre para o Office 2016' 'OK'
        return
    }

    foreach ($p in $depois.ClickToRun) { Write-Aviso "AINDA presente: $($p.DisplayName)" }
    foreach ($r in $depois.Residuos)   { Write-Aviso "residuo restante: $r" }

    if (-not $sara) {
        Write-Aviso 'o SaRA nao esta no pendrive -- e a ferramenta que resolve os casos teimosos'
        Write-Aviso 'rode o Preparar-Pendrive.ps1 no PC do TI para baixa-lo'
    }
}

function Get-FerramentaOffice {
    <#
      Procura SaRA ou ODT no pendrive. Ausentes = camada pulada (nao e erro).
    #>
    param([string]$PastaUSB, [hashtable]$Config, [ValidateSet('SaRA', 'ODT')][string]$Tipo)

    if (-not $PastaUSB) { return $null }

    $candidatos = switch ($Tipo) {
        'SaRA' { @(
            $Config.CaminhoSaRA,
            'payload\office\SaRA\SaRAcmd.exe',
            'payload\SaRA\SaRAcmd.exe'
        ) }
        'ODT'  { @(
            $Config.CaminhoODT,
            'payload\office\ODT\setup.exe',
            'payload\ODT\setup.exe'
        ) }
    }

    foreach ($c in $candidatos) {
        if (-not $c) { continue }
        $p = if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $PastaUSB $c }
        if (Test-Path -LiteralPath $p) {
            Write-Log "$Tipo encontrado: $p"
            return $p
        }
    }
    return $null
}

function Get-ErroOfficeExplicado {
    <#
      Traduz o codigo de saida do setup do Office para portugues e diz o que
      fazer. Sem isto o tecnico ve "codigo 17002" e nao sabe o proximo passo.
    #>
    param([int]$Codigo)

    switch ($Codigo) {
        0     { return 'instalacao concluida' }
        3010  { return 'instalado -- precisa reiniciar para concluir' }
        1641  { return 'instalado -- reinicializacao iniciada' }
        1603  { return 'ERRO FATAL do Windows Installer. Quase sempre e residuo de Office anterior ou falta de espaco em disco. Rode a limpeza profunda (tarefas avulsas) e tente de novo.' }
        1618  { return 'outra instalacao esta em andamento. Espere o Windows Update terminar e tente de novo.' }
        1638  { return 'ja existe uma versao deste Office instalada. Remova pela lista de programas antes.' }
        17002 { return 'o setup do Office NAO concluiu (normalmente Click-to-Run ainda presente). Rode a limpeza profunda do 365 e tente de novo.' }
        17004 { return 'produto invalido no config.xml -- a ISO pode nao corresponder ao produto esperado.' }
        17007 { return 'o setup precisa que a maquina reinicie antes de continuar.' }
        17025 { return 'o Office ja estava instalado.' }
        30015 { return 'erro do instalador Click-to-Run durante a remocao. Rode a limpeza profunda (SaRA) e tente de novo.' }
        30088 { return 'falha do Click-to-Run. Rode a limpeza profunda (SaRA).' }
        default { return "codigo $Codigo -- consulte o log do setup em $script:PastaLogs" }
    }
}

# ============================================================================
#  Licenca / ativacao
# ============================================================================

function Get-AtivacaoOffice {
    <#
      Estado da licenca do Office. SOMENTE LEITURA.
      Sem isto, a maquina e entregue ao funcionario e so la ele descobre que o
      Office pede ativacao -- o que gera retrabalho e mais uma visita.
    #>
    $r = [pscustomobject]@{
        Encontrado = $false
        Ativado    = $false
        Estado     = 'Office nao encontrado no licenciamento'
        Produtos   = @()
    }

    try {
        $lic = @(Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
                 Where-Object { $_.ApplicationID -eq $script:AppIdOffice -and $_.PartialProductKey })
    }
    catch {
        $r.Estado = "nao consegui consultar o licenciamento: $($_.Exception.Message)"
        return $r
    }

    if (-not $lic) { return $r }

    $r.Encontrado = $true
    $r.Produtos = foreach ($l in $lic) {
        $texto = switch ($l.LicenseStatus) {
            0 { 'sem licenca' }
            1 { 'ATIVADO' }
            2 { 'periodo de carencia' }
            3 { 'carencia estendida (OEM)' }
            4 { 'carencia por falta de tolerancia' }
            5 { 'NAO GENUINO / notificacao' }
            6 { 'carencia adicional' }
            default { "estado $($l.LicenseStatus)" }
        }
        [pscustomobject]@{ Nome = $l.Name; Estado = $texto; Codigo = $l.LicenseStatus }
    }

    $r.Ativado = [bool](@($r.Produtos | Where-Object { $_.Codigo -eq 1 }).Count)
    $r.Estado  = ($r.Produtos | ForEach-Object { "$($_.Nome): $($_.Estado)" }) -join ' | '
    return $r
}

function Invoke-AtivarOffice {
    <#
      Tenta ativar usando o ospp.vbs, que e a ferramenta oficial do Office VL.
      Se a chave nao estiver instalada, instala a chave antes.
      Precisa de rede ate o KMS (ou internet, se a chave for MAK).
    #>
    param([string]$Chave)

    $ospp = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $ospp) {
        Write-Aviso 'ospp.vbs nao encontrado -- o Office 2016 nao parece estar instalado'
        return $false
    }

    if ($Chave) {
        Write-Log 'instalando a chave de licenca'
        Invoke-Processo -Arquivo 'cscript.exe' `
            -Argumentos @('//nologo', "`"$ospp`"", "/inpkey:$($Chave -replace '-','')") `
            -TimeoutSegundos 300 -SemErro | Out-Null
    }

    Write-Log 'solicitando ativacao'
    Invoke-Processo -Arquivo 'cscript.exe' -Argumentos @('//nologo', "`"$ospp`"", '/act') `
                    -TimeoutSegundos 600 -SemErro | Out-Null

    Start-Sleep -Seconds 5
    $est = Get-AtivacaoOffice
    if ($est.Ativado) { Write-Log "Office ativado -- $($est.Estado)" 'OK'; return $true }

    Write-Aviso "Office ainda nao ativado -- $($est.Estado)"
    Write-Aviso 'se a chave for KMS, a maquina precisa enxergar o servidor KMS da rede'
    return $false
}
