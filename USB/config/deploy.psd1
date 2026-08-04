@{
    # =======================================================================
    #  WinDeployKit - configuracao central
    #  Edite ESTE arquivo. Os scripts nao precisam ser alterados.
    # =======================================================================

    # ---------------------------------------------------------- DOMINIO ----
    Dominio        = 'empresa.local'

    # OU onde a maquina sera criada. Vazio = OU padrao "Computers".
    # Exemplo: 'OU=Notebooks,OU=TI,DC=empresa,DC=local'
    OU             = ''

    # Usuario ja preenchido na janela de credencial: o tecnico so digita a senha.
    # A SENHA nunca fica salva aqui, nem em log, nem em linha de comando.
    UsuarioDominio = 'EMPRESA\Administrator'

    # ------------------------------------------------------ NOME DO PC -----
    RenomearPC     = $true
    PrefixoNome    = 'NB-'   # o script pergunta o sufixo (ex.: 014)
    ModoNomeLab    = $false        # $true so no perfil de laboratorio

    # ----------------------------------------------------- PASTAS DE REDE --
    # SOMENTE LEITURA. Nada e escrito na rede.
    PastaOffice2016 = '\\servidor-arquivos\Publico\TI\Softwares\Office 2016'

    # Chave de licenca do Office 2016.
    # Vazio = o script tenta ler o arquivo "Licenca.txt" da pasta acima.
    ChaveOffice2016 = ''

    # Limpeza profunda do Microsoft 365 antes de instalar o Office 2016.
    # $true (padrao) usa as ferramentas oficiais da Microsoft em camadas
    # (SaRA -> ODT -> desinstalador do produto) e CONFERE o resultado.
    # Sem isso sobra residuo de Click-to-Run e o Office 2016 se recusa a
    # instalar, com um erro diferente a cada tentativa.
    LimpezaProfundaOffice = $true

    # Ferramentas de remocao, se estiverem no pendrive. Caminho relativo a
    # pasta do kit. Ausentes = a camada e pulada (nao e erro).
    # Baixe com: Preparar-Pendrive.ps1 -BaixarFerramentasOffice
    CaminhoSaRA = 'payload\office\SaRA\SaRAcmd.exe'
    CaminhoODT  = 'payload\office\ODT\setup.exe'

    # Tentar ativar o Office automaticamente apos instalar.
    # Chave KMS precisa enxergar o servidor KMS; MAK precisa de internet.
    AtivarOffice = $true

    # Componentes do Office 2016 que NAO serao instalados.
    # Ids validos: GrooveFiles (OneDrive p/ Empresas), LyncCoreFiles (Skype for
    # Business), AccessFiles, PubPrimary (Publisher), OneNoteFiles, XDOCSFiles
    # (InfoPath), OUTLOOKFiles, VisioPreviewerFiles
    ComponentesOfficeExcluir = @('GrooveFiles', 'LyncCoreFiles', 'XDOCSFiles')

    # -------------------------------------------------------- ETAPAS -------
    RemoverOffice365   = $true
    RemoverBloatware   = $true
    InstalarApps       = $true
    InstalarOffice2016 = $true
    InstalarBitdefender = $true
    AplicarAjustes     = $true
    EntrarNoDominio    = $true
    ReiniciarNoFinal   = $true

    # Quando entrar no dominio.
    #   'Ultimo'   (padrao) - o ingresso exige reiniciar, entao vem no fim.
    #   'Primeiro'          - para o fluxo antigo, em que a maquina precisava
    #                         estar no dominio para ler a pasta de rede. Com a
    #                         ISO do Office no pendrive isso deixou de ser
    #                         necessario, mas a opcao continua disponivel.
    OrdemDominio       = 'Ultimo'

    # -------------------------------------------------------- ANTIVIRUS ----
    # A remocao de antivirus concorrente e feita pelo PROPRIO instalador do
    # Bitdefender (competitorRemoval no installer.xml). Nao escrevemos rotina
    # propria: antivirus tem protecao anti-tamper e desinstalacao generica
    # costuma falhar pela metade, deixando a maquina sem protecao nenhuma.
    BitdefenderPastaOffline = 'payload\antivirus\offline'
    BitdefenderArquivo      = 'Bitdefender Windows.exe'
    BitdefenderDownloader   = 'payload\antivirus\BitdefenderDownloader.exe'
    BitdefenderArgs         = '/bdparams /silent'
    AvisarAntivirusConcorrente = $true

    # Antivirus que vem de FABRICA (OEM) e que a organizacao nao usa -- o McAfee dos
    # notebooks novos. Removido ANTES de instalar o Bitdefender.
    # O ponto principal nao e desinstalar: e tirar o pacote PROVISIONADO da
    # imagem, que e o que reinstala o McAfee sozinho depois de formatar.
    # Usa somente o desinstalador que o proprio fabricante registrou.
    RemoverAntivirusOEM = $true
    AntivirusOEMRemover = @('McAfee', 'Norton')

    # Argumento de silencio para desinstaladores .exe que nao registram um
    # QuietUninstallString. A chave casa com parte do nome do programa.
    AntivirusOEMArgs = @{
        'WebAdvisor' = '/S'
    }

    # -------------------------------------------------------- AJUSTES -----
    FusoHorario        = 'E. South America Standard Time'
    DesligarHibernacao = $true
    MostrarExtensoes   = $true
    RemoverOneDrive    = $false   # OneDrive pessoal do consumidor

    # Minutos para desligar a tela / suspender. 0 = nunca.
    TelaTempoAC     = 20
    TelaTempoBat    = 10
    SuspenderAC     = 0
    SuspenderBat    = 45

    # ------------------------------------------------------- BLOATWARE -----
    # Apps da Microsoft Store removidos do usuario atual e da imagem
    # (nao voltam para novos usuarios). Comente a linha para manter o app.
    AppxRemover = @(
        'Microsoft.3DBuilder'
        'Microsoft.549981C3F5F10'          # Cortana
        'Microsoft.BingFinance'
        'Microsoft.BingNews'
        'Microsoft.BingSearch'
        'Microsoft.BingSports'
        'Microsoft.BingWeather'
        'Microsoft.GamingApp'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'
        'Microsoft.Messaging'
        'Microsoft.Microsoft3DViewer'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.MixedReality.Portal'
        'Microsoft.NetworkSpeedTest'
        'Microsoft.News'
        'Microsoft.Office.OneNote'
        'Microsoft.Office.Sway'
        'Microsoft.OneConnect'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Print3D'
        'Microsoft.SkypeApp'
        'Microsoft.Todos'
        'Microsoft.Wallet'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.Xbox.TCUI'
        'Microsoft.XboxApp'
        'Microsoft.XboxGameOverlay'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxIdentityProvider'
        'Microsoft.XboxSpeechToTextOverlay'
        'Microsoft.YourPhone'
        'Microsoft.ZuneMusic'
        'Microsoft.ZuneVideo'
        'MicrosoftTeams'                   # Teams pessoal / Chat
        'MSTeams'
        'Clipchamp.Clipchamp'
        'MicrosoftCorporationII.QuickAssist'
        'SpotifyAB.SpotifyMusic'
        'Disney.37853FC22B2CE'
        'AmazonVideo.PrimeVideo'
        'BytedancePte.Ltd.TikTok'
        'king.com.CandyCrushSagaWin10'
        'king.com.CandyCrushSodaSaga'
        'Facebook.Facebook'
        'Netflix.Netflix'
    )

    # Nunca remover, mesmo se casar com a lista acima.
    AppxManter = @(
        'Microsoft.WindowsStore'
        'Microsoft.WindowsCalculator'
        'Microsoft.WindowsNotepad'
        'Microsoft.Paint'
        'Microsoft.WindowsTerminal'
        'Microsoft.ScreenSketch'
        'Microsoft.DesktopAppInstaller'
        'Microsoft.VCLibs'
        'Microsoft.UI.Xaml'
        'Microsoft.SecHealthUI'
        'Microsoft.WindowsCamera'
    )

    # ------------------------------------------------------------ APPS -----
    # Instalados a partir de USB\payload\apps (offline) ou, se ausentes,
    # pelo winget. Marque $false no que nao usar.
    Apps = @(
        @{ Nome = 'Google Chrome'; Arquivo = 'GoogleChromeEnterprise64.msi'; Winget = 'Google.Chrome';        Instalar = $true  }
        @{ Nome = '7-Zip';         Arquivo = '7z-x64.msi';                   Winget = '7zip.7zip';            Instalar = $true  }
        @{ Nome = 'Adobe Reader';  Arquivo = 'AcroRdrDC.exe';                Winget = 'Adobe.Acrobat.Reader.64-bit'; Instalar = $false }
        @{ Nome = 'VLC';           Arquivo = 'vlc-win64.msi';                Winget = 'VideoLAN.VLC';         Instalar = $false }
        @{ Nome = 'AnyDesk';       Arquivo = 'AnyDesk.msi';                  Winget = 'AnyDeskSoftwareGmbH.AnyDesk'; Instalar = $false }
    )
}
