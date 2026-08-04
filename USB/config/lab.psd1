@{
    # =======================================================================
    #  PERFIL: LABORATORIOS  (Lab 10 / Lab 11)
    #  Dominio lab.local -- maquinas de aluno, com rotatividade de turma.
    #  NAO instala Office. So limpeza + Chrome + Bitdefender.
    # =======================================================================

    # ---------------------------------------------------------- DOMINIO ----
    Dominio        = 'lab.local'
    OU             = ''
    UsuarioDominio = 'EMPRESA\Administrator'

    # ------------------------------------------------------ NOME DO PC -----
    # O script pergunta o numero do lab e o numero da maquina.
    # Ex.: lab 10, maquina 07  ->  LAB10-07
    RenomearPC     = $true
    PrefixoNome    = 'LAB'
    ModoNomeLab    = $true   # ativa o formato LAB<lab>-<maquina>

    # ----------------------------------------------------- PASTAS DE REDE --
    PastaOffice2016 = '\\servidor-arquivos\Publico\TI\Softwares\Office 2016'
    ChaveOffice2016 = ''
    ComponentesOfficeExcluir = @()

    # -------------------------------------------------------- ETAPAS -------
    RemoverOffice365   = $true    # tira o trial de fabrica
    RemoverBloatware   = $true    # maquina de aluno: limpa os apps da Store
    InstalarApps       = $true    # Chrome
    InstalarOffice2016 = $false   # <<< laboratorio NAO leva Office
    InstalarBitdefender = $true
    AplicarAjustes     = $true
    EntrarNoDominio    = $true
    ReiniciarNoFinal   = $true
    OrdemDominio       = 'Ultimo'   # ver comentario no deploy.psd1

    # Mesmo sem instalar Office, o lab precisa da limpeza: os notebooks vem
    # com Microsoft 365 de fabrica e ele nao deve ficar na maquina do aluno.
    LimpezaProfundaOffice = $true
    CaminhoSaRA = 'payload\office\SaRA\SaRAcmd.exe'
    CaminhoODT  = 'payload\office\ODT\setup.exe'
    AtivarOffice = $false

    # -------------------------------------------------------- ANTIVIRUS ----
    # O proprio instalador do Bitdefender remove antivirus concorrente
    # (competitorRemoval no installer.xml). Aqui so detectamos e avisamos.
    BitdefenderPastaOffline = 'payload\antivirus\offline'
    BitdefenderArquivo      = 'Bitdefender Windows.exe'
    BitdefenderDownloader   = 'payload\antivirus\BitdefenderDownloader.exe'
    BitdefenderArgs         = '/bdparams /silent'
    AvisarAntivirusConcorrente = $true

    # Antivirus de fabrica (OEM). Ver comentario completo no deploy.psd1.
    # Tira tambem o pacote provisionado da imagem, que e o que reinstala o
    # McAfee sozinho depois de formatar.
    RemoverAntivirusOEM = $true
    AntivirusOEMRemover = @('McAfee', 'Norton')
    AntivirusOEMArgs = @{
        'WebAdvisor' = '/S'
    }

    # -------------------------------------------------------- AJUSTES -----
    FusoHorario        = 'E. South America Standard Time'
    DesligarHibernacao = $true
    MostrarExtensoes   = $true
    RemoverOneDrive    = $true    # maquina de aluno nao precisa

    # Lab: tela apaga rapido, mas a maquina nunca suspende (aula em andamento)
    TelaTempoAC     = 15
    TelaTempoBat    = 10
    SuspenderAC     = 0
    SuspenderBat    = 30

    # ------------------------------------------------------- BLOATWARE -----
    AppxRemover = @(
        'Microsoft.3DBuilder'
        'Microsoft.549981C3F5F10'
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
        'MicrosoftTeams'
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
    Apps = @(
        @{ Nome = 'Google Chrome'; Arquivo = 'GoogleChromeEnterprise64.msi'; Winget = 'Google.Chrome'; Instalar = $true  }
        @{ Nome = '7-Zip';         Arquivo = '7z-x64.msi';                   Winget = '7zip.7zip';     Instalar = $true  }
        @{ Nome = 'Adobe Reader';  Arquivo = 'AcroRdrDC.exe';                Winget = 'Adobe.Acrobat.Reader.64-bit'; Instalar = $false }
        @{ Nome = 'VLC';           Arquivo = 'vlc-win64.msi';                Winget = 'VideoLAN.VLC';  Instalar = $false }
        @{ Nome = 'AnyDesk';       Arquivo = 'AnyDesk.msi';                  Winget = 'AnyDeskSoftwareGmbH.AnyDesk'; Instalar = $false }
    )
}
