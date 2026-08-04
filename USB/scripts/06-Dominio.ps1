# ============================================================================
#  Etapa 06 - Renomear a maquina e entrar no dominio
#  Deve ser a ULTIMA etapa: exige reinicializacao.
# ============================================================================

function Invoke-EntrarNoDominio {
    param(
        [hashtable]$Config,
        [pscredential]$Credencial,
        [string]$NovoNome
    )

    if (Test-PC-NoDominio) {
        $atual = (Get-CimInstance Win32_ComputerSystem).Domain
        Write-Log "a maquina ja esta no dominio $atual, pulando"
        return
    }

    # ------------------------------------------------- checagens de rede -----
    Write-Log "testando resolucao DNS de $($Config.Dominio)"
    try {
        $dns = Resolve-DnsName -Name $Config.Dominio -Type A -ErrorAction Stop
        Write-Log ("controlador(es) encontrado(s): " + (($dns | Where-Object IPAddress | Select-Object -Expand IPAddress) -join ', '))
    }
    catch {
        throw "O dominio $($Config.Dominio) nao resolve por DNS. Confira se o notebook esta no cabo/Wi-Fi da empresa e se pegou DNS interno por DHCP."
    }

    # ------------------------------------------------------------- entrada ---
    $parametros = @{
        DomainName  = $Config.Dominio
        Credential  = $Credencial
        Force       = $true
        ErrorAction = 'Stop'
    }
    if ($Config.OU)                          { $parametros.OUPath  = $Config.OU }
    if ($NovoNome -and $Config.RenomearPC)   { $parametros.NewName = $NovoNome }

    if ($parametros.NewName) {
        Write-Log "entrando no dominio $($Config.Dominio) e renomeando para $($parametros.NewName)"
    } else {
        Write-Log "entrando no dominio $($Config.Dominio)"
    }

    # o relogio fora de hora e a causa nº1 de falha de Kerberos no ingresso;
    # sincronizar ANTES evita o erro em vez de so remediar depois
    Invoke-Processo -Arquivo 'w32tm.exe' -Argumentos @('/resync', '/force') -SemErro | Out-Null

    Invoke-Mudanca -Descricao "entrar no dominio $($Config.Dominio) como $($parametros.NewName)" -Acao {
        try {
            Add-Computer @parametros
        }
        catch {
            throw (Get-ErroDominioExplicado -Mensagem $_.Exception.Message -Dominio $Config.Dominio -Nome $parametros.NewName)
        }
    }
    Write-Log 'ingresso no dominio concluido -- vale apos reiniciar'
}

function Get-ErroDominioExplicado {
    <#
      Traduz as falhas classicas de ingresso. Sem isto o tecnico ve uma
      mensagem generica do Windows e perde a tarde tentando adivinhar.
    #>
    param([string]$Mensagem, [string]$Dominio, [string]$Nome)

    $dicas = switch -Regex ($Mensagem) {
        'already exists|ja existe' {
            "Ja existe um objeto '$Nome' no Active Directory. Apague o objeto antigo no AD (Usuarios e Computadores) ou use outro nome."
        }
        'user name or password|senha|credential|logon failure' {
            'Usuario ou senha do dominio incorretos, ou a conta nao tem permissao para ingressar maquinas.'
        }
        'could not be contacted|nao pode ser contatado|no such domain' {
            "Nao achou o controlador de $Dominio. Confira cabo/Wi-Fi da empresa e se o DNS do adaptador aponta para o servidor do dominio (nao para 8.8.8.8)."
        }
        'time|clock|skew' {
            'Relogio da maquina fora de hora em relacao ao dominio (Kerberos). Acerte data/hora/fuso e tente de novo.'
        }
        'access is denied|acesso negado' {
            'A conta usada nao tem permissao para criar objetos de computador nessa OU.'
        }
        default { $null }
    }

    if ($dicas) { return "$Mensagem`n  >> $dicas" }
    return $Mensagem
}

function Invoke-SairDoDominio {
    <#
      Tira a maquina do dominio e a devolve a um grupo de trabalho.
      Usado quando o notebook muda de ambiente (administrativo -> laboratorio)
      ou vai ser reaproveitado. Exige reinicializacao.

      NAO remove o objeto do Active Directory: isso e tarefa do administrador
      do AD, e apagar objeto alheio por engano custa caro.
    #>
    param([pscredential]$Credencial, [string]$GrupoTrabalho = 'WORKGROUP')

    if (-not (Test-PC-NoDominio)) {
        Write-Log 'a maquina ja esta fora de dominio'
        return
    }

    $atual = (Get-CimInstance Win32_ComputerSystem).Domain
    Write-Log "saindo do dominio $atual"

    Invoke-Mudanca -Descricao "sair do dominio $atual para o grupo $GrupoTrabalho" -Acao {
        $p = @{ WorkgroupName = $GrupoTrabalho; Force = $true; ErrorAction = 'Stop' }
        if ($Credencial) { $p.Credential = $Credencial }
        Remove-Computer @p
    }

    Write-Log 'saida concluida -- vale apos reiniciar' 'OK'
    Write-Aviso "o objeto '$env:COMPUTERNAME' continua no Active Directory de $atual -- peca ao administrador para remover"
}

function Invoke-RenomearMaquina {
    <#
      Renomeia sem mexer no dominio. Se a maquina estiver no dominio, a
      credencial e obrigatoria (o AD precisa aprovar a mudanca de nome).
    #>
    param([string]$NovoNome, [pscredential]$Credencial)

    if (-not $NovoNome) { Write-Log 'nenhum nome informado'; return }
    if ($NovoNome -eq $env:COMPUTERNAME) { Write-Log 'a maquina ja tem esse nome'; return }

    Invoke-Mudanca -Descricao "renomear $env:COMPUTERNAME para $NovoNome" -Acao {
        $p = @{ NewName = $NovoNome; Force = $true; ErrorAction = 'Stop' }
        if ($Credencial -and (Test-PC-NoDominio)) { $p.DomainCredential = $Credencial }
        Rename-Computer @p
    }
    Write-Log "renomeada para $NovoNome -- vale apos reiniciar" 'OK'
}

function Get-NomeSugerido {
    <#
      Monta o nome da maquina.
      Modo normal : PrefixoNome + sufixo digitado     -> NB-014
      Modo lab    : PrefixoNome + lab + '-' + numero  -> LAB10-07
      Nome NetBIOS: maximo 15 caracteres, sem acento e sem espacos.
    #>
    param([hashtable]$Config)

    if (-not $Config.RenomearPC) { return $null }

    Write-Host ''

    if ($Config.ModoNomeLab) {
        Write-Host '  Nome do computador de laboratorio.' -ForegroundColor Cyan
        Write-Host '  ENTER em branco em qualquer campo = manter o nome atual.' -ForegroundColor Gray

        $lab = (Read-Host '  Numero do laboratorio (ex.: 10 ou 11)').Trim()
        if (-not $lab) { return $null }

        $maquina = (Read-Host '  Numero da maquina (ex.: 07)').Trim()
        if (-not $maquina) { return $null }

        # normaliza para dois digitos quando for so numero
        if ($maquina -match '^\d$') { $maquina = '0' + $maquina }

        $nome = '{0}{1}-{2}' -f $Config.PrefixoNome, $lab, $maquina
    }
    else {
        Write-Host "  Nome do computador. Prefixo configurado: $($Config.PrefixoNome)" -ForegroundColor Cyan
        Write-Host '  Digite so o sufixo (ex.: 014 ou RH01). ENTER em branco = manter o nome atual.' -ForegroundColor Gray
        $sufixo = (Read-Host '  Sufixo').Trim()

        if (-not $sufixo) { return $null }
        $nome = ($Config.PrefixoNome + $sufixo)
    }

    $nome = $nome -replace '[^A-Za-z0-9\-]', ''
    if ($nome.Length -gt 15) {
        $nome = $nome.Substring(0, 15)
        Write-Host "  Nome truncado para 15 caracteres: $nome" -ForegroundColor Yellow
    }

    Write-Host "  Nome final: $nome" -ForegroundColor Green
    return $nome
}
