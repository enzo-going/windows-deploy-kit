# ============================================================================
#  Etapa 03 - Instalar aplicativos padrao (Chrome e companhia)
# ----------------------------------------------------------------------------
#  Ordem de tentativa para cada app:
#    1) instalador offline em USB\payload\apps  (recomendado, funciona sem net)
#    2) winget, se o instalador nao estiver no pendrive
#  Para arquivos .exe, crie um arquivo ao lado com o mesmo nome + ".args"
#  contendo os parametros de instalacao silenciosa. Ex.: AcroRdrDC.exe.args
# ============================================================================

function Invoke-InstalarApps {
    param([hashtable]$Config, [string]$PastaUSB)

    $pastaApps = Join-Path $PastaUSB 'payload\apps'

    foreach ($app in $Config.Apps) {
        if (-not $app.Instalar) { continue }

        Write-Log "--- $($app.Nome)"

        if (Test-AppInstalado -Nome $app.Nome) {
            Write-Log "$($app.Nome) ja esta instalado, pulando"
            continue
        }

        $arquivo = Join-Path $pastaApps $app.Arquivo
        $ok = $false

        if (Test-Path -LiteralPath $arquivo) {
            $ok = Install-Pacote -Caminho $arquivo
        }
        else {
            Write-Log "instalador offline nao encontrado ($($app.Arquivo)), tentando winget"
            $ok = Install-ViaWinget -Id $app.Winget
        }

        if ($ok) { Write-Log "$($app.Nome) instalado" 'OK' }
        else     { Write-Aviso "$($app.Nome) NAO foi instalado -- instale manualmente" }
    }

    Set-ChromePreferencias
}

function Test-AppInstalado {
    param([string]$Nome)
    $chave = switch -Wildcard ($Nome) {
        '*Chrome*'  { 'Google Chrome' }
        '*7-Zip*'   { '7-Zip' }
        '*Reader*'  { 'Adobe Acrobat' }
        '*VLC*'     { 'VLC media player' }
        '*AnyDesk*' { 'AnyDesk' }
        default     { $Nome }
    }
    [bool](Get-ProgramasInstalados | Where-Object { $_.DisplayName -like "*$chave*" })
}

function Install-Pacote {
    param([Parameter(Mandatory)][string]$Caminho)

    $ext = [IO.Path]::GetExtension($Caminho).ToLower()
    try {
        if ($ext -eq '.msi') {
            $log = Join-Path $script:PastaLogs ("msi_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($Caminho))
            Invoke-Processo -Arquivo 'msiexec.exe' -Argumentos @(
                '/i', "`"$Caminho`"", '/qn', '/norestart',
                'REBOOT=ReallySuppress', '/l*v', "`"$log`""
            ) -TimeoutSegundos 1800 | Out-Null
            return $true
        }

        $argsFile = "$Caminho.args"
        if (Test-Path -LiteralPath $argsFile) {
            $parametros = (Get-Content -LiteralPath $argsFile -Raw -Encoding UTF8).Trim()
            Invoke-Processo -Arquivo $Caminho -Argumentos @($parametros) -TimeoutSegundos 1800 | Out-Null
            return $true
        }

        Write-Aviso "sem parametros silenciosos para $([IO.Path]::GetFileName($Caminho)) -- crie o arquivo .args ao lado"
        return $false
    }
    catch {
        Write-Aviso "falha instalando $([IO.Path]::GetFileName($Caminho)): $($_.Exception.Message)"
        return $false
    }
}

function Install-ViaWinget {
    param([string]$Id)
    if (-not $Id) { return $false }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Aviso 'winget nao disponivel nesta maquina'
        return $false
    }

    try {
        Invoke-Processo -Arquivo $winget.Source -Argumentos @(
            'install', '--id', $Id, '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--scope', 'machine', '--disable-interactivity'
        ) -CodigosOk @(0, 3010, 1641, -1978335189) -TimeoutSegundos 1800 | Out-Null
        return $true
    }
    catch {
        Write-Aviso "winget falhou para ${Id}: $($_.Exception.Message)"
        return $false
    }
}

function Set-ChromePreferencias {
    <#
      Evita a tela de boas-vindas e o pedido de "definir como padrao" na
      primeira abertura do Chrome, para o notebook ja sair pronto.
    #>
    $dir = 'C:\Program Files\Google\Chrome\Application'
    if (-not (Test-Path $dir)) { return }

    $json = @'
{
  "distribution": {
    "skip_first_run_ui": true,
    "import_search_engine": false,
    "import_history": false,
    "import_bookmarks": false,
    "make_chrome_default": true,
    "make_chrome_default_for_user": true,
    "suppress_first_run_bubble": true,
    "do_not_create_desktop_shortcut": false,
    "verbose_logging": false
  },
  "browser": { "check_default_browser": false },
  "first_run_tabs": [ "about:blank" ]
}
'@
    Set-Content -Path (Join-Path $dir 'initial_preferences') -Value $json -Encoding UTF8
    Write-Log 'preferencias iniciais do Chrome aplicadas'
}
