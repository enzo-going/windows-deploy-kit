# ============================================================================
#  Etapa 04 - Instalar o Office 2016 Volume License a partir da pasta Publico
# ----------------------------------------------------------------------------
#  A pasta de rede e usada SOMENTE PARA LEITURA. O ISO e copiado para o disco
#  local, montado e instalado de forma silenciosa com um config.xml gerado
#  aqui a partir das opcoes do deploy.psd1.
# ============================================================================

function Invoke-InstalarOffice2016 {
    param([hashtable]$Config, [pscredential]$Credencial, [string]$PastaUSB)

    if (Test-Office2016Instalado) {
        Write-Log 'Office 2016 ja esta instalado, pulando'
        return
    }

    # ------------------------------------------------- pre-checagem de bloqueio
    # Falhar AQUI custa 2 segundos. Falhar no meio do setup custa 15 minutos,
    # deixa residuo e produz um erro diferente a cada tentativa.
    $bloqueios = Test-BloqueioOffice2016
    if ($bloqueios) {
        Write-Log 'a instalacao NAO pode comecar -- ha bloqueios:' 'ERRO'
        foreach ($b in $bloqueios) { Write-Log "  - $b" 'ERRO' }
        throw ('Office 2016 bloqueado por: ' + ($bloqueios -join '; ') +
               '. Rode a limpeza profunda do Microsoft 365 (tarefas avulsas) e tente de novo.')
    }

    $fonte = Get-FonteOffice -Config $Config -Credencial $Credencial -PastaUSB $PastaUSB
    $iso   = $fonte.ISO
    Write-Log "origem: $($fonte.Descricao)"

    # ------------------------------------------------- copia para o disco ----
    $isoLocal = Join-Path $script:PastaTemp $iso.Name
    if ((Test-Path $isoLocal) -and ((Get-Item $isoLocal).Length -eq $iso.Length)) {
        Write-Log 'ISO ja copiado anteriormente, reaproveitando'
    }
    else {
        $mb = [math]::Round($iso.Length / 1MB)
        Write-Log "copiando $($iso.Name) ($mb MB) para o disco local"
        $t = Measure-Command { Copy-Item -LiteralPath $iso.FullName -Destination $isoLocal -Force }
        Write-Log ("copia concluida em {0:N0}s" -f $t.TotalSeconds)
    }

    # ------------------------------------------------------------ licenca ----
    $chave = $Config.ChaveOffice2016
    if (-not $chave) { $chave = Get-ChaveOffice -PastaRede $fonte.Pasta }

    # ISO veio do pendrive, mas o arquivo de licenca so existe na rede
    if (-not $chave -and $Credencial) {
        try {
            $pastaRede = Connect-Compartilhamento -CaminhoUNC $Config.PastaOffice2016 -Credencial $Credencial
            $chave = Get-ChaveOffice -PastaRede $pastaRede
        }
        catch { Write-Aviso "nao consegui ler a licenca da rede: $($_.Exception.Message)" }
    }
    if ($chave) { Write-Log "chave de licenca localizada (final ...$($chave.Substring($chave.Length-5)))" }
    else        { Write-Aviso 'sem chave de licenca -- o Office vai pedir ativacao depois' }

    # -------------------------------------------------------- monta o ISO ----
    $img = $null
    try {
        Write-Log 'montando o ISO'
        $img   = Mount-DiskImage -ImagePath $isoLocal -PassThru -ErrorAction Stop
        $letra = ($img | Get-Volume).DriveLetter
        if (-not $letra) { throw 'nao consegui identificar a letra do ISO montado' }
        $raiz = "${letra}:\"
        Write-Log "ISO montado em $raiz"

        $setup = Join-Path $raiz 'setup.exe'
        if (-not (Test-Path $setup)) { throw "setup.exe nao encontrado em $raiz" }

        # produto: a pasta <produto>.WW define o Product do config.xml
        $pastaProd = Get-ChildItem -LiteralPath $raiz -Directory |
                     Where-Object { $_.Name -like '*.WW' } | Select-Object -First 1
        if (-not $pastaProd) { throw 'nao encontrei a pasta de produto (*.WW) no ISO' }
        $produto = $pastaProd.Name -replace '\.WW$', ''
        Write-Log "produto detectado: $produto"

        $configXml = New-OfficeConfigXml -Produto $produto -Chave $chave `
                                         -Excluir @($Config.ComponentesOfficeExcluir)

        Write-Log 'instalando o Office 2016 em modo silencioso (5 a 15 minutos)'
        # 17002 NAO entra como sucesso: significa que o setup nao concluiu.
        # Trata-lo como OK fazia o kit anunciar "instalado" sem ter instalado.
        $code = Invoke-Processo -Arquivo $setup -Argumentos @('/config', "`"$configXml`"") `
                                -CodigosOk @(0, 3010, 1641) -TimeoutSegundos 5400 -SemErro

        if ($code -ne 0) { Write-Log ("setup: " + (Get-ErroOfficeExplicado -Codigo $code)) }

        if ($script:Simulacao) { Write-Log '[SIMULACAO] pulando a conferencia de instalacao'; return }

        if (-not (Test-Office2016Instalado)) {
            throw ('o Office nao foi instalado. ' + (Get-ErroOfficeExplicado -Codigo $code))
        }
    }
    finally {
        if ($img) {
            Write-Log 'desmontando o ISO'
            Dismount-DiskImage -ImagePath $isoLocal -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Write-Log 'Office 2016 instalado'

    # ---------------------------------------------------------- ativacao -----
    # Sem isto a maquina e entregue e so o funcionario descobre que o Office
    # pede ativacao -- o que gera uma segunda visita do TI.
    if ($script:Simulacao) { return }

    $ativ = Get-AtivacaoOffice
    if ($ativ.Ativado) {
        Write-Log "licenca: $($ativ.Estado)" 'OK'
    }
    elseif ($Config.AtivarOffice -ne $false) {
        Write-Log 'Office nao ativado -- tentando ativar'
        Invoke-AtivarOffice -Chave $chave | Out-Null
    }
    else {
        Write-Aviso "Office instalado mas NAO ativado -- $($ativ.Estado)"
    }
}

function Get-FonteOffice {
    <#
      Procura a ISO do Office nesta ordem:
        1. USB\payload\office        (dentro do kit)
        2. raiz do pendrive          (onde a ISO ja costuma estar)
        3. pasta Publico na rede     (fallback, exige credencial)
      Usar o pendrive evita copiar 800 MB pela rede e funciona sem rede nenhuma.
    #>
    param([hashtable]$Config, [pscredential]$Credencial, [string]$PastaUSB)

    $locais = @()
    if ($PastaUSB) {
        $locais += @{ Pasta = (Join-Path $PastaUSB 'payload\office'); Descricao = 'pendrive (payload do kit)' }
        $raizUSB = Split-Path -Parent $PastaUSB
        if ($raizUSB) { $locais += @{ Pasta = $raizUSB; Descricao = 'pendrive (raiz)' } }
    }

    foreach ($l in $locais) {
        if (-not (Test-Path -LiteralPath $l.Pasta)) { continue }
        $iso = Get-ChildItem -LiteralPath $l.Pasta -Filter '*.iso' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match 'office' } |
               Sort-Object Length -Descending | Select-Object -First 1
        if ($iso) {
            return @{ ISO = $iso; Pasta = $l.Pasta; Descricao = "$($l.Descricao) -- $($iso.Name)" }
        }
    }

    # nao achou no pendrive: cai para a rede
    Write-Log 'ISO do Office nao encontrada no pendrive, buscando na rede'
    $pastaRede = Connect-Compartilhamento -CaminhoUNC $Config.PastaOffice2016 -Credencial $Credencial
    $iso = Get-ChildItem -LiteralPath $pastaRede -Filter '*.iso' -File -ErrorAction Stop |
           Sort-Object Length -Descending | Select-Object -First 1
    if (-not $iso) { throw "Nenhuma ISO do Office encontrada no pendrive nem em $pastaRede" }

    return @{ ISO = $iso; Pasta = $pastaRede; Descricao = "rede -- $($iso.Name)" }
}

function Test-Office2016Instalado {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\16.0\Word\InstallRoot') { return $true }
    [bool](Get-ProgramasInstalados | Where-Object {
        $_.DisplayName -match 'Microsoft Office (Professional|Standard).*2016' -and
        $_.UninstallString -like '*MsiExec*'
    })
}

function Get-ChaveOffice {
    <#
      Le (somente leitura) o arquivo de licenca da pasta de rede e extrai a
      chave no formato XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.
    #>
    param([string]$PastaRede)

    $arqs = Get-ChildItem -LiteralPath $PastaRede -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'licen' -and $_.Extension -match '^\.(txt|csv|log)$' }

    foreach ($a in $arqs) {
        try {
            $texto = Get-Content -LiteralPath $a.FullName -Raw -ErrorAction Stop
            if ($texto -match '([A-Z0-9]{5}(?:-[A-Z0-9]{5}){4})') {
                Write-Log "chave lida de $($a.Name)"
                return $Matches[1]
            }
        }
        catch { Write-Aviso "nao consegui ler $($a.Name)" }
    }
    return $null
}

function New-OfficeConfigXml {
    param([string]$Produto, [string]$Chave, [string[]]$Excluir)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<Configuration Product="' + $Produto + '">')
    [void]$sb.AppendLine('  <Display Level="none" CompletionNotice="no" SuppressModal="yes" AcceptEula="yes" />')
    if ($Chave) { [void]$sb.AppendLine('  <PIDKEY Value="' + ($Chave -replace '-', '') + '" />') }
    [void]$sb.AppendLine('  <Setting Id="SETUP_REBOOT" Value="Never" />')
    [void]$sb.AppendLine('  <Setting Id="AUTO_ACTIVATE" Value="1" />')
    [void]$sb.AppendLine('  <Logging Type="standard" Path="' + $script:PastaLogs + '" Template="office2016_setup.txt" />')
    foreach ($c in $Excluir) {
        if ($c) { [void]$sb.AppendLine('  <OptionState Id="' + $c + '" State="absent" Children="force" />') }
    }
    [void]$sb.AppendLine('</Configuration>')

    $destino = Join-Path $script:PastaTemp 'office2016-config.xml'
    Set-Content -Path $destino -Value $sb.ToString() -Encoding UTF8
    Write-Log "config.xml gerado em $destino"
    return $destino
}
