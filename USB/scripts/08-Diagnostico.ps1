# ============================================================================
#  Etapa 08 - Diagnostico da maquina
# ----------------------------------------------------------------------------
#  SOMENTE LEITURA. Nao altera absolutamente nada.
#
#  Serve para o tecnico chegar numa maquina desconhecida (ou numa pilha de 10
#  notebooks) e responder em 20 segundos: o que ja tem aqui, o que falta, e
#  qual opcao do menu eu devo usar. Antes disto a resposta vinha de abrir
#  quatro janelas do Windows e adivinhar.
# ============================================================================

function Get-DiagnosticoMaquina {
    $d = [ordered]@{}

    # ------------------------------------------------------------- sistema ---
    $maq   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $so    = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bios  = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue

    $d.Nome      = $env:COMPUTERNAME
    $d.Modelo    = "$($maq.Manufacturer) $($maq.Model)"
    $d.Serie     = $bios.SerialNumber
    $d.Sistema   = "$($so.Caption) $($so.OSArchitecture) (build $($so.BuildNumber))"
    $d.NoDominio = [bool]$maq.PartOfDomain
    $d.Dominio   = if ($maq.PartOfDomain) { $maq.Domain } else { 'fora do dominio (grupo de trabalho)' }
    $d.DiscoLivreGB = if ($disco) { [math]::Round($disco.FreeSpace / 1GB, 1) } else { 0 }
    $d.DiscoTotalGB = if ($disco) { [math]::Round($disco.Size / 1GB, 1) } else { 0 }
    $d.RebootPendente = Test-RebootPendente

    $lig = (Get-Date) - $so.LastBootUpTime
    $d.LigadaHa = '{0}d {1}h' -f [int]$lig.TotalDays, $lig.Hours

    # -------------------------------------------------------------- Office ---
    $off = Get-EstadoOffice
    $d.Office2016     = $off.Tem2016
    $d.Office365      = $off.TemC2R
    $d.OfficeC2RNomes = @($off.ClickToRun | Select-Object -ExpandProperty DisplayName)
    $d.OfficeMSINomes = @($off.MSI | Select-Object -ExpandProperty DisplayName)
    $d.OfficeResiduos = $off.Residuos
    $d.OfficePodeInstalar = $off.PodeInstalar

    $ativ = Get-AtivacaoOffice
    $d.OfficeAtivado = $ativ.Ativado
    $d.OfficeLicenca = $ativ.Estado

    # ----------------------------------------------------------- antivirus ---
    $d.Bitdefender = Test-BitdefenderInstalado
    $d.Antivirus   = @(Get-AntivirusRegistrados | Select-Object -ExpandProperty Nome)
    $d.AntivirusOEM = @($d.Antivirus | Where-Object { $_ -match 'McAfee|Norton|Avast|AVG' })

    # ---------------------------------------------------------------- apps ---
    $prog = Get-ProgramasInstalados
    $chrome = $prog | Where-Object { $_.DisplayName -like '*Google Chrome*' } | Select-Object -First 1
    $d.Chrome = if ($chrome) { $chrome.DisplayVersion } else { $null }

    # ----------------------------------------------------------- bloatware ---
    $d.Bloatware = @()
    try {
        $sujeira = 'CandyCrush|Spotify|TikTok|Disney|Netflix|PrimeVideo|Facebook|Xbox|Solitaire'
        $d.Bloatware = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match $sujeira } |
                         Select-Object -ExpandProperty Name -Unique)
    } catch { }

    # ---------------------------------------------------------- BitLocker ----
    $d.BitLocker = 'nao verificado'
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $d.BitLocker = "$($bl.VolumeStatus) / protecao $($bl.ProtectionStatus)"
    }
    catch { $d.BitLocker = "nao verificado ($($_.Exception.Message))" }

    # ------------------------------------------------- historico do kit ------
    $d.PassosFeitos = @(Get-PassosConcluidos)

    return [pscustomobject]$d
}

function Show-Diagnostico {
    <#
      Imprime o diagnostico e, no fim, diz qual opcao do menu usar.
    #>
    param([hashtable]$ConfigAdmin, [hashtable]$ConfigLab)

    Write-Host '   Lendo a maquina (nada sera alterado)...' -ForegroundColor DarkGray
    $d = Get-DiagnosticoMaquina

    function L { param($Rot, $Val, $Cor = 'Gray')
        Write-Host ('     {0,-16}: ' -f $Rot) -NoNewline -ForegroundColor DarkGray
        Write-Host $Val -ForegroundColor $Cor
    }

    Write-Host ''
    Write-Host '   MAQUINA' -ForegroundColor Yellow
    L 'Nome'     $d.Nome 'White'
    L 'Modelo'   $d.Modelo
    L 'Serie'    $d.Serie
    L 'Sistema'  $d.Sistema
    L 'Ligada ha' $d.LigadaHa
    L 'Disco livre' ('{0} GB de {1} GB' -f $d.DiscoLivreGB, $d.DiscoTotalGB) `
      $(if ($d.DiscoLivreGB -lt 15) { 'Red' } else { 'Green' })
    L 'Dominio'  $d.Dominio $(if ($d.NoDominio) { 'Green' } else { 'Yellow' })
    if ($d.RebootPendente) { L 'Reboot' 'PENDENTE -- reinicie antes de instalar Office' 'Red' }
    L 'BitLocker' $d.BitLocker

    Write-Host ''
    Write-Host '   OFFICE' -ForegroundColor Yellow
    if ($d.Office365) {
        L 'Microsoft 365' ('PRESENTE -- ' + ($d.OfficeC2RNomes -join ', ')) 'Red'
    } else {
        L 'Microsoft 365' 'nao instalado' 'Green'
    }
    L 'Office 2016' $(if ($d.Office2016) { 'instalado' } else { 'NAO instalado' }) `
      $(if ($d.Office2016) { 'Green' } else { 'Yellow' })
    if ($d.OfficeMSINomes) { L 'Versao MSI' ($d.OfficeMSINomes -join ', ') }
    if ($d.OfficeResiduos) {
        L 'Residuos C2R' ('{0} item(ns) -- BLOQUEIAM a instalacao do 2016' -f $d.OfficeResiduos.Count) 'Red'
        foreach ($r in $d.OfficeResiduos) { Write-Host "                       - $r" -ForegroundColor DarkYellow }
    }
    L 'Licenca' $d.OfficeLicenca $(if ($d.OfficeAtivado) { 'Green' } elseif ($d.Office2016) { 'Red' } else { 'DarkGray' })
    L 'Pode instalar' $(if ($d.OfficePodeInstalar) { 'SIM -- caminho livre' } else { 'NAO -- limpe o 365 antes' }) `
      $(if ($d.OfficePodeInstalar) { 'Green' } else { 'Red' })

    Write-Host ''
    Write-Host '   PROTECAO E APPS' -ForegroundColor Yellow
    L 'Bitdefender' $(if ($d.Bitdefender) { 'instalado' } else { 'NAO instalado' }) `
      $(if ($d.Bitdefender) { 'Green' } else { 'Red' })
    L 'Antivirus' $(if ($d.Antivirus) { $d.Antivirus -join ', ' } else { 'nenhum registrado' })
    if ($d.AntivirusOEM) { L 'AV de fabrica' ($d.AntivirusOEM -join ', ') 'Red' }
    L 'Chrome' $(if ($d.Chrome) { $d.Chrome } else { 'NAO instalado' }) `
      $(if ($d.Chrome) { 'Green' } else { 'Yellow' })
    L 'Bloatware' $(if ($d.Bloatware) { '{0} app(s): {1}' -f $d.Bloatware.Count, (($d.Bloatware | Select-Object -First 4) -join ', ') } else { 'limpo' }) `
      $(if ($d.Bloatware) { 'Yellow' } else { 'Green' })

    if ($d.PassosFeitos) {
        Write-Host ''
        Write-Host '   JA FEITO POR ESTE KIT' -ForegroundColor Yellow
        foreach ($p in $d.PassosFeitos) {
            Write-Host ('     [{0}] {1}' -f $p.Perfil, $p.Passo) -ForegroundColor DarkGray
        }
    }

    # ------------------------------------------------------------ sugestao ---
    Write-Host ''
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   O QUE FAZER' -ForegroundColor Cyan
    foreach ($s in (Get-SugestaoDiagnostico -D $d -ConfigAdmin $ConfigAdmin -ConfigLab $ConfigLab)) {
        Write-Host "     $s" -ForegroundColor White
    }
    Write-Host ''
    return $d
}

function Get-SugestaoDiagnostico {
    <#
      Traduz o diagnostico em proximos passos concretos, na ordem certa.
      A ordem importa: reboot pendente antes de tudo, limpeza antes do Office,
      dominio por ultimo.
    #>
    param([psobject]$D, [hashtable]$ConfigAdmin, [hashtable]$ConfigLab)

    $s = @()

    if ($D.DiscoLivreGB -lt 15) {
        $s += "BLOQUEIO: so ha $($D.DiscoLivreGB) GB livres. O kit exige 15 GB."
    }
    if ($D.RebootPendente) {
        $s += 'PRIMEIRO: reinicie a maquina. Ha reinicializacao pendente e o setup do Office falha assim.'
    }

    $ehLab = $D.NoDominio -and $ConfigLab -and ($D.Dominio -like "*$($ConfigLab.Dominio)*")

    if ($D.Office365 -or $D.OfficeResiduos) {
        $s += 'O Microsoft 365 (ou residuo dele) esta bloqueando o Office 2016.'
        $s += '  -> Tarefas avulsas > "Limpeza profunda do Microsoft 365"'
    }
    if (-not $D.Office2016 -and -not $ehLab -and $D.OfficePodeInstalar) {
        $s += 'Falta o Office 2016. Caminho livre: pode instalar agora.'
    }
    if ($D.Office2016 -and -not $D.OfficeAtivado) {
        $s += 'Office 2016 instalado mas NAO ativado.'
        $s += '  -> Tarefas avulsas > "Verificar / ativar licenca do Office"'
    }
    if ($D.AntivirusOEM) {
        $s += "Antivirus de fabrica presente ($($D.AntivirusOEM -join ', ')). A opcao [5] remove e poe o Bitdefender."
    }
    elseif (-not $D.Bitdefender) {
        $s += 'Sem Bitdefender. Opcao [5] instala so o antivirus.'
    }
    if (-not $D.Chrome) {
        $s += 'Sem Chrome. Tarefas avulsas > "Instalar Chrome e apps".'
    }
    if (-not $D.NoDominio) {
        $s += 'Maquina fora do dominio. Entre no dominio por ultimo (exige reiniciar).'
    }

    # ---- veredito
    $faltaTudo = (-not $D.Bitdefender) -and (-not $D.Chrome) -and (-not $D.Office2016)
    if ($faltaTudo) {
        $s = @('Maquina crua. Rode a opcao [1] (administrativo) ou [4] (laboratorio) e o kit faz tudo.') + $s
    }
    elseif (-not $s) {
        $s += 'Nada pendente: Office instalado e ativado, Bitdefender presente, Chrome instalado, no dominio.'
    }

    return $s
}
