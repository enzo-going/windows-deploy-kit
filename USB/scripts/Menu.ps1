#requires -Version 5.1
<#
.SYNOPSIS
    Menu principal do WinDeployKit.

.DESCRIPTION
    As opcoes [1] a [6] sao as mesmas de sempre -- a equipe ja as conhece e o
    MANUAL.txt as ensina. As FERRAMENTAS ([7] em diante) foram acrescentadas
    depois, sem renumerar nada, justamente para nao quebrar esse habito.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PastaScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
$PastaUSB     = Split-Path -Parent $PastaScripts

. (Join-Path $PastaScripts 'Lib.ps1')

if (-not (Test-Administrador)) {
    Write-Host 'Execute pelo INICIAR.cmd (precisa de administrador).' -ForegroundColor Red
    exit 1
}

# modulos usados pelas ferramentas do menu (as opcoes 1-4 rodam em processo
# separado e carregam os seus por conta propria)
. (Join-Path $PastaScripts '01-Remove-Office365.ps1')
. (Join-Path $PastaScripts '02-Remove-Bloatware.ps1')
. (Join-Path $PastaScripts '03-Install-Apps.ps1')
. (Join-Path $PastaScripts '04-Install-Office2016.ps1')
. (Join-Path $PastaScripts '05-Ajustes.ps1')
. (Join-Path $PastaScripts '06-Dominio.ps1')
. (Join-Path $PastaScripts '07-Antivirus.ps1')
. (Join-Path $PastaScripts '08-Diagnostico.ps1')
. (Join-Path $PastaScripts '09-Office-Limpeza.ps1')

$script:CfgAdmin = Get-KitConfig -Caminho (Join-Path $PastaUSB 'config\deploy.psd1')
$script:CfgLab   = Get-KitConfig -Caminho (Join-Path $PastaUSB 'config\lab.psd1')

# ============================================================================
#  Apresentacao
# ============================================================================

function Show-Cabecalho {
    Clear-Host
    $maq = Get-CimInstance Win32_ComputerSystem
    $dom = if ($maq.PartOfDomain) { $maq.Domain } else { 'fora do dominio' }

    Write-Host ''
    Write-Host '  ================================================================' -ForegroundColor Cyan
    Write-Host '    C A M P S   -   P R E P A R A C A O   D E   M A Q U I N A S' -ForegroundColor Cyan
    Write-Host '  ================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "    Maquina: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$env:COMPUTERNAME" -NoNewline -ForegroundColor White
    Write-Host "   |   Dominio: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$dom" -ForegroundColor White
    if (Test-Simulacao) {
        Write-Host ''
        Write-Host '    *** MODO SIMULACAO LIGADO -- nada sera alterado ***' -ForegroundColor Magenta
    }
    Write-Host ''
}

function Show-Menu {
    Show-Cabecalho

    Write-Host '   ADMINISTRATIVO' -NoNewline -ForegroundColor Yellow
    Write-Host '  (dominio empresa.local)' -ForegroundColor DarkGray
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '    [1] ' -NoNewline -ForegroundColor White
    Write-Host 'PREPARAR PC' -ForegroundColor Green
    Write-Host '        PC novo, ou que acabou de ser restaurado.' -ForegroundColor Gray
    Write-Host '        Office 365 fora, Office 2016, Chrome, Bitdefender, dominio.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    [2] ' -NoNewline -ForegroundColor White
    Write-Host 'RESTAURAR PC devolvido por funcionario' -ForegroundColor Red
    Write-Host '        Confere os arquivos, avisa o que sera perdido e' -ForegroundColor Gray
    Write-Host '        RESTAURA a maquina (apaga tudo). Pede confirmacao dupla.' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '   LABORATORIOS' -NoNewline -ForegroundColor Yellow
    Write-Host '  (dominio lab.local -- Lab 10, Lab 11)' -ForegroundColor DarkGray
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '    [3] ' -NoNewline -ForegroundColor White
    Write-Host 'RESTAURAR PC de laboratorio' -ForegroundColor Red
    Write-Host '        Troca de turma. RESTAURA a maquina (apaga tudo).' -ForegroundColor Gray
    Write-Host ''
    Write-Host '    [4] ' -NoNewline -ForegroundColor White
    Write-Host 'PREPARAR PC de laboratorio' -ForegroundColor Green
    Write-Host '        PC de lab JA restaurado. SEM Office.' -ForegroundColor Gray
    Write-Host ''

    Write-Host '   OUTROS' -ForegroundColor Yellow
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '    [5] ' -NoNewline -ForegroundColor White
    Write-Host 'Instalar / reparar SO o Bitdefender' -ForegroundColor Cyan
    Write-Host '    [6] ' -NoNewline -ForegroundColor White
    Write-Host 'Abrir o manual' -ForegroundColor Cyan
    Write-Host ''

    Write-Host '   FERRAMENTAS' -ForegroundColor Yellow
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '    [7] ' -NoNewline -ForegroundColor White
    Write-Host 'DIAGNOSTICO desta maquina' -NoNewline -ForegroundColor Cyan
    Write-Host '   (so le, nao muda nada)' -ForegroundColor DarkGray
    Write-Host '        Diz o que ja tem, o que falta e qual opcao usar.' -ForegroundColor DarkGray
    Write-Host '    [8] ' -NoNewline -ForegroundColor White
    Write-Host 'Tarefas avulsas' -NoNewline -ForegroundColor Cyan
    Write-Host '   (so o Office, so o Chrome, so o dominio...)' -ForegroundColor DarkGray
    Write-Host '    [9] ' -NoNewline -ForegroundColor White
    Write-Host 'Modo LOTE' -NoNewline -ForegroundColor Cyan
    Write-Host '   (fila de varios notebooks seguidos)' -ForegroundColor DarkGray
    Write-Host '    [S] ' -NoNewline -ForegroundColor White
    if (Test-Simulacao) {
        Write-Host 'Simulacao: LIGADA' -NoNewline -ForegroundColor Magenta
        Write-Host '  (ENTER aqui para desligar)' -ForegroundColor DarkGray
    } else {
        Write-Host 'Simulacao: desligada' -NoNewline -ForegroundColor Cyan
        Write-Host '  (liga o modo de teste sem risco)' -ForegroundColor DarkGray
    }
    Write-Host '    [0] ' -NoNewline -ForegroundColor White
    Write-Host 'Sair' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  ================================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Wait-Enter {
    param([string]$Texto = '   ENTER para voltar ao menu')
    Write-Host ''
    Read-Host $Texto | Out-Null
}

function Confirm-Sim {
    param([string]$Pergunta)
    $r = Read-Host "   $Pergunta (S/N)"
    return ($r -match '^[SsYy]')
}

# ============================================================================
#  Despacho principal
# ============================================================================

function Invoke-Opcao {
    param([string]$Op)

    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }

    # as opcoes longas rodam em processo separado para nao poluir o menu
    $extra = @()
    if (Test-Simulacao) { $extra += '-Simular' }

    switch ($Op) {
        '1' {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PastaScripts 'Invoke-Deploy.ps1') `
                     -Config (Join-Path $PastaUSB 'config\deploy.psd1') @extra
        }
        '2' {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PastaScripts 'Invoke-Restaurar.ps1') `
                     -Contexto Funcionario
        }
        '3' {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PastaScripts 'Invoke-Restaurar.ps1') `
                     -Contexto Laboratorio
        }
        '4' {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PastaScripts 'Invoke-Deploy.ps1') `
                     -Config (Join-Path $PastaUSB 'config\lab.psd1') @extra
        }
        '5' { Invoke-SoBitdefender }
        '6' {
            $man = Join-Path $PastaUSB 'MANUAL.txt'
            if (Test-Path $man) { Start-Process notepad.exe $man }
            else { Write-Host '   MANUAL.txt nao encontrado.' -ForegroundColor Red; Start-Sleep 2 }
        }
        '7' { Invoke-Diagnostico }
        '8' { Show-MenuAvulsas }
        '9' { Invoke-ModoLote }
    }
}

# ============================================================================
#  [7] Diagnostico
# ============================================================================

function Invoke-Diagnostico {
    Show-Cabecalho
    Write-Host '   DIAGNOSTICO DESTA MAQUINA' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   Somente leitura: nada e alterado.' -ForegroundColor DarkGray

    Initialize-Ambiente
    $d = Show-Diagnostico -ConfigAdmin $script:CfgAdmin -ConfigLab $script:CfgLab

    if (Confirm-Sim 'Salvar este diagnostico no pendrive?') {
        $linhas = @(
            "Office 2016   : $(if ($d.Office2016) { 'instalado' } else { 'NAO instalado' })"
            "Licenca Office: $($d.OfficeLicenca)"
            "Microsoft 365 : $(if ($d.Office365) { 'PRESENTE' } else { 'ausente' })"
            "Residuos C2R  : $(if ($d.OfficeResiduos) { $d.OfficeResiduos -join ' | ' } else { 'nenhum' })"
            "Bitdefender   : $(if ($d.Bitdefender) { 'instalado' } else { 'NAO instalado' })"
            "Antivirus     : $($d.Antivirus -join ', ')"
            "Chrome        : $(if ($d.Chrome) { $d.Chrome } else { 'NAO instalado' })"
            "Dominio       : $($d.Dominio)"
            "Disco livre   : $($d.DiscoLivreGB) GB"
        )
        Save-Relatorio -PastaUSB $PastaUSB -Perfil 'diagnostico' -Linhas $linhas | Out-Null
    }
    Wait-Enter
}

# ============================================================================
#  [8] Tarefas avulsas
# ============================================================================

function Show-MenuAvulsas {
    while ($true) {
        Show-Cabecalho
        Write-Host '   TAREFAS AVULSAS' -ForegroundColor Cyan
        Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host '   Cada opcao faz UMA coisa so, sem tocar no resto da maquina.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '   OFFICE' -ForegroundColor Yellow
        Write-Host '    [1] Limpeza profunda do Microsoft 365' -NoNewline -ForegroundColor White
        Write-Host '  <- resolve o "nao instala"' -ForegroundColor DarkGray
        Write-Host '    [2] Instalar o Office 2016' -ForegroundColor White
        Write-Host '    [3] Verificar / ativar a licenca do Office' -ForegroundColor White
        Write-Host ''
        Write-Host '   SISTEMA' -ForegroundColor Yellow
        Write-Host '    [4] Instalar Chrome e apps padrao' -ForegroundColor White
        Write-Host '    [5] Remover bloatware da Store' -ForegroundColor White
        Write-Host '    [6] Aplicar ajustes (energia, fuso, Explorer)' -ForegroundColor White
        Write-Host '    [7] Remover antivirus de fabrica (McAfee etc.)' -ForegroundColor White
        Write-Host ''
        Write-Host '   DOMINIO' -ForegroundColor Yellow
        Write-Host '    [8] Entrar no dominio / renomear' -ForegroundColor White
        Write-Host '    [9] SAIR do dominio' -ForegroundColor White
        Write-Host ''
        Write-Host '    [L] Abrir a pasta de logs e relatorios' -ForegroundColor Cyan
        Write-Host '    [0] Voltar' -ForegroundColor Cyan
        Write-Host ''

        $op = (Read-Host '   Escolha').Trim().ToUpper()
        if ($op -eq '0') { return }

        Initialize-Ambiente
        try { Invoke-Avulsa -Op $op }
        catch {
            Write-Host ''
            Write-Host "   FALHOU: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Log: $script:ArqLog" -ForegroundColor DarkGray
            Wait-Enter
        }
    }
}

function Invoke-Avulsa {
    param([string]$Op)

    switch ($Op) {

        '1' {   # ---------------------------------------- limpeza profunda 365
            Show-Cabecalho
            Write-Host '   LIMPEZA PROFUNDA DO MICROSOFT 365' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
            Write-Host '   Remove o 365 e os residuos que impedem o Office 2016 de' -ForegroundColor Gray
            Write-Host '   instalar. Usa as ferramentas oficiais da Microsoft.' -ForegroundColor Gray
            Write-Host ''

            $est = Get-EstadoOffice
            if ($est.TemC2R) {
                Write-Host '   Click-to-Run encontrado:' -ForegroundColor Yellow
                foreach ($p in $est.ClickToRun) { Write-Host "     - $($p.DisplayName)" -ForegroundColor Gray }
            }
            if ($est.Residuos) {
                Write-Host '   Residuos encontrados:' -ForegroundColor Yellow
                foreach ($r in $est.Residuos) { Write-Host "     - $r" -ForegroundColor Gray }
            }
            if (-not $est.TemC2R -and -not $est.Residuos) {
                Write-Host '   Nada a limpar: o caminho para o Office 2016 ja esta livre.' -ForegroundColor Green
                Wait-Enter; return
            }
            if ($est.MSI) {
                Write-Host ''
                Write-Host '   Office MSI presente (sera PRESERVADO):' -ForegroundColor Cyan
                foreach ($m in $est.MSI) { Write-Host "     - $($m.DisplayName)" -ForegroundColor Gray }
            }
            Write-Host ''
            Write-Host '   Pode demorar de 5 a 30 minutos.' -ForegroundColor DarkGray
            if (-not (Confirm-Sim 'Limpar agora?')) { return }

            Invoke-LimpezaProfundaOffice365 -Config $script:CfgAdmin -PastaUSB $PastaUSB

            $depois = Get-EstadoOffice
            Write-Host ''
            if ($depois.PodeInstalar) {
                Write-Host '   PRONTO: caminho livre para instalar o Office 2016.' -ForegroundColor Green
            } else {
                Write-Host '   Ainda ha bloqueios. Reinicie a maquina e rode esta limpeza de novo.' -ForegroundColor Red
            }
            Wait-Enter
        }

        '2' {   # ------------------------------------------ instalar o Office
            Show-Cabecalho
            Write-Host '   INSTALAR O OFFICE 2016' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray

            if (Test-Office2016Instalado) {
                Write-Host '   O Office 2016 ja esta instalado nesta maquina.' -ForegroundColor Green
                Wait-Enter; return
            }

            $bloqueios = Test-BloqueioOffice2016
            if ($bloqueios) {
                Write-Host '   NAO da para instalar agora:' -ForegroundColor Red
                foreach ($b in $bloqueios) { Write-Host "     - $b" -ForegroundColor Yellow }
                Write-Host ''
                Write-Host '   Use a opcao [1] (limpeza profunda) primeiro.' -ForegroundColor Cyan
                Wait-Enter; return
            }

            Write-Host '   Caminho livre. A instalacao leva de 5 a 15 minutos.' -ForegroundColor Green
            if (-not (Confirm-Sim 'Instalar agora?')) { return }

            $cred = $null
            if (-not (Test-Path (Join-Path $PastaUSB 'payload\office'))) {
                $cred = Get-CredencialDominio -Dominio $script:CfgAdmin.Dominio -Usuario $script:CfgAdmin.UsuarioDominio
            }
            Invoke-InstalarOffice2016 -Config $script:CfgAdmin -Credencial $cred -PastaUSB $PastaUSB
            Write-Host ''
            Write-Host '   Office 2016 instalado.' -ForegroundColor Green
            Wait-Enter
        }

        '3' {   # ------------------------------------------------- ativacao ---
            Show-Cabecalho
            Write-Host '   LICENCA DO OFFICE' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray

            $a = Get-AtivacaoOffice
            if (-not $a.Encontrado) {
                Write-Host '   Nenhum Office encontrado no licenciamento desta maquina.' -ForegroundColor Yellow
                Wait-Enter; return
            }
            foreach ($p in $a.Produtos) {
                $cor = if ($p.Codigo -eq 1) { 'Green' } else { 'Red' }
                Write-Host "     $($p.Nome)" -ForegroundColor Gray
                Write-Host "       -> $($p.Estado)" -ForegroundColor $cor
            }
            Write-Host ''
            if ($a.Ativado) { Write-Host '   Office ativado.' -ForegroundColor Green; Wait-Enter; return }

            if (-not (Confirm-Sim 'Tentar ativar agora?')) { return }
            $chave = $script:CfgAdmin.ChaveOffice2016
            Invoke-AtivarOffice -Chave $chave | Out-Null
            Wait-Enter
        }

        '4' {   # ----------------------------------------------------- apps ---
            Show-Cabecalho
            Write-Host '   INSTALAR CHROME E APPS PADRAO' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
            foreach ($app in $script:CfgAdmin.Apps) {
                if ($app.Instalar) { Write-Host "     - $($app.Nome)" -ForegroundColor Gray }
            }
            Write-Host ''
            if (-not (Confirm-Sim 'Instalar agora?')) { return }
            Invoke-InstalarApps -Config $script:CfgAdmin -PastaUSB $PastaUSB
            Wait-Enter
        }

        '5' {   # ------------------------------------------------ bloatware ---
            Show-Cabecalho
            Write-Host '   REMOVER BLOATWARE DA STORE' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
            Write-Host "   Remove ate $($script:CfgAdmin.AppxRemover.Count) apps do usuario e da imagem." -ForegroundColor Gray
            Write-Host ''
            if (-not (Confirm-Sim 'Remover agora?')) { return }
            Invoke-RemoverBloatware -Config $script:CfgAdmin
            Wait-Enter
        }

        '6' {   # -------------------------------------------------- ajustes ---
            Show-Cabecalho
            Write-Host '   AJUSTES DE SISTEMA' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
            Write-Host "   Fuso $($script:CfgAdmin.FusoHorario), energia, hibernacao, extensoes." -ForegroundColor Gray
            Write-Host ''
            if (-not (Confirm-Sim 'Aplicar agora?')) { return }
            Invoke-AplicarAjustes -Config $script:CfgAdmin
            Wait-Enter
        }

        '7' {   # ------------------------------------------------- AV de fabrica
            Show-Cabecalho
            Write-Host '   REMOVER ANTIVIRUS DE FABRICA' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
            $avs = Get-AntivirusRegistrados
            if ($avs) {
                Write-Host '   Antivirus detectados:' -ForegroundColor Gray
                foreach ($a in $avs) { Write-Host "     - $($a.Nome)" -ForegroundColor Gray }
            }
            Write-Host ''
            Write-Host '   NAO instala o Bitdefender -- so remove o de fabrica.' -ForegroundColor DarkGray
            Write-Host '   A maquina fica sem antivirus ate voce rodar a opcao [5].' -ForegroundColor Yellow
            Write-Host ''
            if (-not (Confirm-Sim 'Remover agora?')) { return }
            Invoke-RemoverAntivirusOEM -Config $script:CfgAdmin
            Wait-Enter
        }

        '8' {   # --------------------------------------- entrar / renomear ----
            Show-Cabecalho
            Write-Host '   DOMINIO / NOME DA MAQUINA' -ForegroundColor Cyan
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray

            if (Test-PC-NoDominio) {
                Write-Host "   Ja esta no dominio $((Get-CimInstance Win32_ComputerSystem).Domain)." -ForegroundColor Green
                Write-Host ''
                if (-not (Confirm-Sim 'Quer apenas RENOMEAR a maquina?')) { return }
                $cfg = $script:CfgAdmin
                $novo = Get-NomeSugerido -Config $cfg
                if (-not $novo) { return }
                $cred = Get-CredencialDominio -Dominio $cfg.Dominio -Usuario $cfg.UsuarioDominio
                Invoke-RenomearMaquina -NovoNome $novo -Credencial $cred
                Wait-Enter; return
            }

            Write-Host '   Qual ambiente?' -ForegroundColor White
            Write-Host "     [1] Administrativo  ($($script:CfgAdmin.Dominio))" -ForegroundColor Gray
            Write-Host "     [2] Laboratorio     ($($script:CfgLab.Dominio))" -ForegroundColor Gray
            Write-Host ''
            $amb = (Read-Host '   Escolha').Trim()
            $cfg = switch ($amb) { '1' { $script:CfgAdmin } '2' { $script:CfgLab } default { $null } }
            if (-not $cfg) { return }

            $novo = Get-NomeSugerido -Config $cfg
            $cred = Get-CredencialDominio -Dominio $cfg.Dominio -Usuario $cfg.UsuarioDominio
            Invoke-EntrarNoDominio -Config $cfg -Credencial $cred -NovoNome $novo
            Write-Host ''
            Write-Host '   Reinicie a maquina para concluir.' -ForegroundColor Yellow
            Wait-Enter
        }

        '9' {   # ------------------------------------------ sair do dominio ---
            Show-Cabecalho
            Write-Host '   SAIR DO DOMINIO' -ForegroundColor Yellow
            Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray

            if (-not (Test-PC-NoDominio)) {
                Write-Host '   Esta maquina ja esta fora de dominio.' -ForegroundColor Green
                Wait-Enter; return
            }
            $atual = (Get-CimInstance Win32_ComputerSystem).Domain
            Write-Host "   Dominio atual: $atual" -ForegroundColor Gray
            Write-Host ''
            Write-Host '   Depois de sair, o login so funciona com conta LOCAL.' -ForegroundColor Yellow
            Write-Host '   Confirme que existe uma conta local de administrador' -ForegroundColor Yellow
            Write-Host '   com senha conhecida ANTES de continuar.' -ForegroundColor Yellow
            Write-Host ''
            if (-not (Confirm-Sim 'Existe conta local e voce quer sair do dominio?')) { return }

            $cred = Get-CredencialDominio -Dominio $atual -Usuario $script:CfgAdmin.UsuarioDominio
            Invoke-SairDoDominio -Credencial $cred
            Write-Host ''
            Write-Host '   Reinicie a maquina para concluir.' -ForegroundColor Yellow
            Wait-Enter
        }

        'L' {   # ------------------------------------------------------ logs ---
            if (Test-Path $script:PastaLogs) { Start-Process explorer.exe $script:PastaLogs }
            $rel = Join-Path $PastaUSB 'Relatorios'
            if (Test-Path $rel) { Start-Process explorer.exe $rel }
        }

        default {
            Write-Host '   Opcao invalida.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

# ============================================================================
#  [9] Modo lote -- varios notebooks seguidos
# ============================================================================

function Invoke-ModoLote {
    <#
      Feito para o cenario real: uma pilha de 10 notebooks de laboratorio
      no fim do ano letivo. Em vez de reabrir o menu e reconfigurar tudo a
      cada maquina, o tecnico escolhe o perfil UMA vez e o kit repete o
      ciclo: prepara -> mostra o resultado -> pede a proxima maquina.
    #>
    Show-Cabecalho
    Write-Host '   MODO LOTE' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   Para preparar varios notebooks seguidos com o mesmo perfil.' -ForegroundColor Gray
    Write-Host '   Cada maquina gera um relatorio em <pendrive>\Relatorios,' -ForegroundColor Gray
    Write-Host '   para voce conferir o lote inteiro no fim.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   Perfil do lote:' -ForegroundColor White
    Write-Host "     [1] Administrativo  ($($script:CfgAdmin.Dominio), com Office 2016)" -ForegroundColor Gray
    Write-Host "     [2] Laboratorio     ($($script:CfgLab.Dominio), sem Office)" -ForegroundColor Gray
    Write-Host '     [0] Voltar' -ForegroundColor Gray
    Write-Host ''

    $esc = (Read-Host '   Escolha').Trim()
    $arquivo = switch ($esc) {
        '1' { 'config\deploy.psd1' }
        '2' { 'config\lab.psd1' }
        default { $null }
    }
    if (-not $arquivo) { return }

    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }
    $extra = @()
    if (Test-Simulacao) { $extra += '-Simular' }

    $n = 0
    while ($true) {
        $n++
        Show-Cabecalho
        Write-Host "   LOTE -- maquina numero $n" -ForegroundColor Cyan
        Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "   Perfil: $arquivo" -ForegroundColor Gray
        Write-Host "   Maquina atual: $env:COMPUTERNAME" -ForegroundColor Gray
        Write-Host ''
        Write-Host '   Confirme que o pendrive esta no notebook certo.' -ForegroundColor Yellow
        Write-Host ''
        if (-not (Confirm-Sim "Preparar esta maquina (numero $n do lote)?")) { break }

        # -Recomecar: cada notebook do lote e uma maquina nova; o estado
        # gravado em C:\ pertence a maquina, entao nao ha o que reaproveitar,
        # mas se o pendrive voltar para uma maquina ja feita, o estado protege.
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PastaScripts 'Invoke-Deploy.ps1') `
                 -Config (Join-Path $PastaUSB $arquivo) -SemReiniciar @extra

        Write-Host ''
        Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "   Maquina $n concluida." -ForegroundColor Green
        Write-Host '   Reinicie ESTA maquina, tire o pendrive e va para a proxima.' -ForegroundColor Yellow
        Write-Host ''
        if (-not (Confirm-Sim 'Tem mais um notebook para preparar?')) { break }
    }

    Show-Cabecalho
    Write-Host "   LOTE ENCERRADO -- $($n - 1) maquina(s) processada(s)." -ForegroundColor Cyan
    $rel = Join-Path $PastaUSB 'Relatorios'
    if (Test-Path $rel) {
        $hoje = @(Get-ChildItem $rel -Filter '*.txt' | Where-Object { $_.LastWriteTime.Date -eq (Get-Date).Date })
        Write-Host "   Relatorios de hoje: $($hoje.Count)" -ForegroundColor Gray
        foreach ($h in $hoje) { Write-Host "     - $($h.Name)" -ForegroundColor DarkGray }
    }
    Wait-Enter
}

# ============================================================================
#  [5] So o Bitdefender
# ============================================================================

function Invoke-SoBitdefender {
    Show-Cabecalho
    Write-Host '   INSTALAR / REPARAR O BITDEFENDER' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Nao mexe em mais nada na maquina: so o antivirus.' -ForegroundColor Gray
    Write-Host ''

    Initialize-Ambiente
    $cfg = $script:CfgAdmin

    $forcar = $false
    if (Test-BitdefenderInstalado) {
        Write-Host '   O Bitdefender JA esta instalado nesta maquina.' -ForegroundColor Green
        Write-Host ''
        if (-not (Confirm-Sim 'Reinstalar mesmo assim?')) { return }
        $forcar = $true
        Write-Host '   Prosseguindo com a reinstalacao...' -ForegroundColor Yellow
    }

    $avs = Get-AntivirusRegistrados
    if ($avs) {
        Write-Host '   Antivirus detectados agora:' -ForegroundColor White
        foreach ($a in $avs) { Write-Host "     - $($a.Nome)" -ForegroundColor Gray }
        Write-Host ''
    }

    Write-Host '   A instalacao leva de 10 a 30 minutos e deixa a maquina lenta.' -ForegroundColor DarkGray
    Write-Host ''
    if (-not (Confirm-Sim 'Instalar o Bitdefender agora?')) { return }

    try {
        if ($cfg.RemoverAntivirusOEM) {
            Write-Host ''
            Write-Host '   Removendo antivirus de fabrica antes de instalar...' -ForegroundColor Gray
            Invoke-RemoverAntivirusOEM -Config $cfg
        }
        Invoke-InstalarBitdefender -Config $cfg -PastaUSB $PastaUSB -Forcar:$forcar
        Write-Host ''
        Write-Host '   Bitdefender instalado com sucesso.' -ForegroundColor Green
    }
    catch {
        Write-Host ''
        Write-Host "   FALHOU: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Log: $script:ArqLog" -ForegroundColor Gray
    }

    Wait-Enter
}

# ============================================================================
#  Loop
# ============================================================================

$validas = @('1', '2', '3', '4', '5', '6', '7', '8', '9', 'S')

while ($true) {
    Show-Menu
    $op = (Read-Host '   Escolha uma opcao').Trim().ToUpper()

    if ($op -eq '0') { break }

    if ($op -eq 'S') {
        Set-Simulacao (-not (Test-Simulacao))
        continue
    }

    if ($op -notin $validas) {
        Write-Host '   Opcao invalida.' -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    # confirmacao extra nas opcoes destrutivas, antes mesmo de abrir o script
    if ($op -in '2', '3') {
        Write-Host ''
        Write-Host '   Essa opcao vai RESTAURAR a maquina (apagar tudo).' -ForegroundColor Red
        if (-not (Confirm-Sim 'Continuar?')) { continue }
    }

    try { Invoke-Opcao -Op $op }
    catch {
        Write-Host ''
        Write-Host "   ERRO: $($_.Exception.Message)" -ForegroundColor Red
        Wait-Enter
    }
}
