# ============================================================================
#  Etapa 07 - Bitdefender (GravityZone)
# ----------------------------------------------------------------------------
#  A REMOCAO DE ANTIVIRUS CONCORRENTE E FEITA PELO PROPRIO INSTALADOR.
#  O installer.xml da organizacao tem:
#      <competitorRemoval><execute mode="always"/><useExternal value="yes"/>
#  ou seja, o Bitdefender roda a ferramenta oficial de remocao de cada
#  concorrente antes de se instalar.
#
#  Nao escrevemos rotina propria de desinstalacao de antivirus de proposito:
#  antivirus tem protecao anti-tamper e "UninstallString" generico costuma
#  falhar pela metade, deixando a maquina COM os dois quebrados e SEM
#  protecao. Aqui apenas detectamos, avisamos e conferimos no final.
# ============================================================================

function Invoke-InstalarBitdefender {
    param([hashtable]$Config, [string]$PastaUSB, [switch]$Forcar)

    # ------------------------------------------------- ja esta instalado? ---
    # -Forcar vem da opcao [5] do menu, quando o tecnico pede reparo/reinstalacao
    # de uma instalacao que existe mas esta quebrada.
    if (Test-BitdefenderInstalado) {
        if (-not $Forcar) {
            Write-Log 'Bitdefender ja esta instalado, pulando'
            return
        }
        Write-Log 'Bitdefender ja instalado, mas foi pedido reparo -- reinstalando por cima'
    }

    # ------------------------------------------ o que existe hoje na maquina -
    $antes = Get-AntivirusRegistrados
    foreach ($a in $antes) {
        if ($a.Nome -match 'Bitdefender') { continue }
        if ($a.Nome -match 'Windows Defender|Microsoft Defender') {
            Write-Log "antivirus atual: $($a.Nome) (sera substituido normalmente)"
        }
        else {
            Write-Log "antivirus de terceiro detectado: $($a.Nome)" 'AVISO'
            Write-Log '   o instalador do Bitdefender vai tentar remove-lo automaticamente'
        }
    }

    # ------------------------------------------------------ escolhe a fonte --
    $fonte = Get-FonteBitdefender -Config $Config -PastaUSB $PastaUSB
    Write-Log "origem: $($fonte.Descricao)"

    if ($fonte.Tipo -eq 'downloader') {
        Write-Log 'este instalador baixa ~600 MB da internet, pode demorar' 'AVISO'
        if (-not (Test-TemInternet)) {
            throw 'O instalador online do Bitdefender precisa de internet e a maquina nao esta conectada. Ponha o kit offline em payload\antivirus\offline.'
        }
    }

    # o executavel le o installer.xml que fica ao lado dele
    $xml = Join-Path (Split-Path -Parent $fonte.Caminho) 'installer.xml'
    if ($fonte.Tipo -eq 'offline' -and -not (Test-Path -LiteralPath $xml)) {
        Write-Aviso 'installer.xml nao encontrado ao lado do instalador -- a maquina pode nao entrar no console GravityZone'
    }

    # ---------------------------------------------------------- instalacao --
    $argumentos = $Config.BitdefenderArgs
    if (-not $argumentos) { $argumentos = '/bdparams /silent' }

    Write-Log 'instalando o Bitdefender em modo silencioso (10 a 30 minutos)'
    Write-Log 'a maquina pode ficar lenta durante a instalacao, e normal'

    $code = Invoke-Processo -Arquivo $fonte.Caminho -Argumentos @($argumentos) `
                            -CodigosOk @(0, 3010, 1641) -TimeoutSegundos 5400 -SemErro

    # ------------------------------------------------------- conferencia ----
    Start-Sleep -Seconds 10
    if (Test-BitdefenderInstalado) {
        Write-Log 'Bitdefender instalado'
    }
    else {
        throw "a instalacao terminou com codigo $code mas o Bitdefender nao foi detectado"
    }

    # sobrou algum concorrente?
    $depois = Get-AntivirusRegistrados | Where-Object {
        $_.Nome -notmatch 'Bitdefender' -and $_.Nome -notmatch 'Windows Defender|Microsoft Defender'
    }
    foreach ($a in $depois) {
        Write-Aviso "ATENCAO: $($a.Nome) ainda esta presente -- remova na mao pelo painel do fabricante"
    }
}

# ============================================================================
#  Remocao de antivirus OEM (McAfee de fabrica e afins)
# ----------------------------------------------------------------------------
#  POR QUE ISTO EXISTE, SE O BITDEFENDER JA REMOVE CONCORRENTE:
#  o McAfee de fabrica nao "sobrevive" a formatacao -- ele e REINSTALADO pelo
#  pacote provisionado que o fabricante deixa na imagem do Windows. O
#  competitorRemoval do Bitdefender roda uma vez, na instalacao; o OEM reinstala
#  depois, em perfil novo. Por isso aqui removemos as TRES pontas:
#     1. o que esta instalado  -> desinstalador OFICIAL do proprio fabricante
#     2. o pacote provisionado -> e o que faz voltar
#     3. a tarefa agendada     -> reinstala/renova em segundo plano
#
#  LIMITE DELIBERADO: usamos apenas o desinstalador que o proprio fabricante
#  registrou. Nao matamos servico, nao apagamos pasta, nao mexemos em driver.
#  Se o desinstalador falhar, avisamos e seguimos -- nunca deixamos a maquina
#  num meio-termo sem protecao. Antivirus corporativo entrincheirado continua
#  sendo assunto do competitorRemoval do Bitdefender, nao daqui.
# ============================================================================

function Invoke-RemoverAntivirusOEM {
    param([hashtable]$Config)

    $marcas = @($Config.AntivirusOEMRemover) | Where-Object { $_ }
    if (-not $marcas) {
        Write-Log 'AntivirusOEMRemover vazio -- nada a remover'
        return
    }

    $padrao = ($marcas | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $extras = $Config.AntivirusOEMArgs
    if (-not $extras) { $extras = @{} }
    Write-Log ("procurando antivirus de fabrica: {0}" -f ($marcas -join ', '))

    # --------------------------------------------- 1. desinstalar o instalado --
    $alvos = @(Get-ProgramasInstalados | Where-Object { $_.DisplayName -match $padrao })

    if (-not $alvos) { Write-Log 'nenhum antivirus de fabrica instalado' }

    foreach ($alvo in $alvos) {
        $cmd = Get-ComandoDesinstalacao -Programa $alvo -ArgsExtra $extras
        if (-not $cmd) {
            Write-Aviso "$($alvo.DisplayName): sem desinstalador registrado -- remova pelo Painel de Controle"
            continue
        }

        Write-Log "desinstalando: $($alvo.DisplayName)"
        try {
            $code = Invoke-Processo -Arquivo $cmd.Arquivo -Argumentos $cmd.Argumentos `
                                    -CodigosOk @(0, 3010, 1641, 1605, 1614) `
                                    -TimeoutSegundos 900 -SemErro
            if ($code -ne 0) { Write-Log "  terminou com codigo $code" }
        }
        catch {
            # timeout: o desinstalador provavelmente abriu janela e ficou esperando
            Write-Aviso "$($alvo.DisplayName): desinstalador nao terminou sozinho -- $($_.Exception.Message)"
        }
    }

    # --------------------------- 2. pacote provisionado (o que faz VOLTAR) -----
    foreach ($p in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match $padrao })) {
        try {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "appx removido: $($p.Name)"
        }
        catch { Write-Aviso "nao removi o appx $($p.Name) -- $($_.Exception.Message)" }
    }

    foreach ($pp in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -match $padrao })) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
            Write-Log "removido da imagem (nao volta em perfil novo): $($pp.DisplayName)"
        }
        catch { Write-Aviso "nao removi da imagem: $($pp.DisplayName)" }
    }

    # ------------------------------------------------- 3. tarefas agendadas ----
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                     Where-Object { $_.TaskName -match $padrao -or $_.TaskPath -match $padrao })) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Log "tarefa agendada removida: $($t.TaskPath)$($t.TaskName)"
        }
        catch { Write-Aviso "nao removi a tarefa $($t.TaskName) -- $($_.Exception.Message)" }
    }

    # ------------------------------------------------------------ conferencia -
    $sobrou = @(Get-ProgramasInstalados | Where-Object { $_.DisplayName -match $padrao })
    if ($sobrou) {
        foreach ($s in $sobrou) {
            Write-Aviso "ATENCAO: $($s.DisplayName) ainda aparece instalado -- pode exigir reinicializacao ou remocao manual"
        }
        Write-Aviso 'o instalador do Bitdefender ainda vai tentar remover o que sobrou (competitorRemoval)'
    }
    else {
        Write-Log 'nenhum antivirus de fabrica restante'
    }
}

function Get-ComandoDesinstalacao {
    <#
      Monta arquivo + argumentos a partir do que o FABRICANTE registrou.
      Prioriza QuietUninstallString (silencioso por definicao).
      Para MSI, converte /I em /X e acrescenta /qn /norestart.
      Para .exe, usa os argumentos da config (AntivirusOEMArgs) quando houver.
    #>
    param([psobject]$Programa, [hashtable]$ArgsExtra = @{})

    $bruto = $Programa.QuietUninstallString
    $silencioso = [bool]$bruto
    if (-not $bruto) { $bruto = $Programa.UninstallString }
    if (-not $bruto) { return $null }
    $bruto = $bruto.Trim()

    # ---- MSI: sempre da para silenciar de verdade
    if ($bruto -match 'msiexec' -and $bruto -match '\{[0-9A-Fa-f\-]{36}\}') {
        $guid = $Matches[0]
        return @{ Arquivo = 'msiexec.exe'; Argumentos = @('/x', $guid, '/qn', '/norestart') }
    }

    # ---- separa executavel de argumentos
    if ($bruto.StartsWith('"')) {
        $fim = $bruto.IndexOf('"', 1)
        if ($fim -lt 0) { return $null }
        $arquivo = $bruto.Substring(1, $fim - 1)
        $resto   = $bruto.Substring($fim + 1).Trim()
    }
    elseif ($bruto -match '^(.+?\.exe)\s*(.*)$') {
        $arquivo = $Matches[1]
        $resto   = $Matches[2].Trim()
    }
    else {
        $arquivo = $bruto
        $resto   = ''
    }

    if (-not (Test-Path -LiteralPath $arquivo)) { return $null }

    $argumentos = @()
    if ($resto) { $argumentos += $resto }

    # argumento de silencio especifico da marca, vindo da config
    if (-not $silencioso) {
        foreach ($chave in $ArgsExtra.Keys) {
            if ($Programa.DisplayName -match [regex]::Escape($chave)) {
                $argumentos += $ArgsExtra[$chave]
                break
            }
        }
    }

    return @{ Arquivo = $arquivo; Argumentos = @($argumentos | Where-Object { $_ }) }
}

function Get-FonteBitdefender {
    <#
      Prioridade:
        1. kit offline (611 MB) em payload\antivirus\offline  -> nao precisa de internet
        2. downloader do GravityZone (4 MB)                   -> baixa ~600 MB
    #>
    param([hashtable]$Config, [string]$PastaUSB)

    $pastaOff = Join-Path $PastaUSB $Config.BitdefenderPastaOffline
    $exeOff   = Join-Path $pastaOff $Config.BitdefenderArquivo
    if (Test-Path -LiteralPath $exeOff) {
        return @{ Tipo = 'offline'; Caminho = $exeOff; Descricao = "kit offline do pendrive -- $($Config.BitdefenderArquivo)" }
    }

    $dl = Join-Path $PastaUSB $Config.BitdefenderDownloader
    if (Test-Path -LiteralPath $dl) {
        return @{ Tipo = 'downloader'; Caminho = $dl; Descricao = 'downloader do GravityZone (baixa da internet)' }
    }

    throw "Nenhum instalador do Bitdefender encontrado no pendrive (procurei em $pastaOff e $dl)"
}

function Test-BitdefenderInstalado {
    # servico do endpoint
    $svc = Get-Service -Name 'EPSecurityService', 'EPIntegrationService', 'EPProtectedService' -ErrorAction SilentlyContinue
    if ($svc) { return $true }

    # pasta de instalacao
    foreach ($p in @(
        "$env:ProgramFiles\Bitdefender\Endpoint Security",
        "${env:ProgramFiles(x86)}\Bitdefender\Endpoint Security",
        "$env:ProgramFiles\Bitdefender"
    )) {
        if (Test-Path -LiteralPath $p) { return $true }
    }

    # lista de programas
    [bool](Get-ProgramasInstalados | Where-Object { $_.DisplayName -match 'Bitdefender' })
}

function Get-AntivirusRegistrados {
    <#
      Le o Windows Security Center. Somente leitura.
      So existe em Windows cliente -- em Server retorna vazio.
    #>
    $lista = @()
    try {
        $avs = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($a in $avs) {
            $lista += [pscustomobject]@{ Nome = $a.displayName; Caminho = $a.pathToSignedProductExe }
        }
    }
    catch {
        # fallback: procura na lista de programas instalados
        $marcas = 'Avast|AVG|Kaspersky|McAfee|Norton|Symantec|ESET|Sophos|Trend Micro|Panda|Avira|Malwarebytes|F-Secure|Comodo'
        foreach ($p in (Get-ProgramasInstalados | Where-Object { $_.DisplayName -match $marcas })) {
            $lista += [pscustomobject]@{ Nome = $p.DisplayName; Caminho = '' }
        }
    }
    return $lista
}

function Test-TemInternet {
    try {
        $r = Invoke-WebRequest -Uri 'https://cloud-ecs.gravityzone.bitdefender.com' -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return $true
    }
    catch {
        # qualquer resposta HTTP ja prova que ha saida para a internet
        if ($_.Exception.Response) { return $true }
        return $false
    }
}
