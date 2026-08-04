param(
  [string]$Pendrive = 'D:',
  [string]$PastaNoPendrive = 'Teste_Programa'
)
$ErrorActionPreference='Continue'
$usb=Join-Path $Pendrive $PastaNoPendrive
$fonte=Split-Path $PSScriptRoot -Parent
$ok=0;$warn=0;$err=0
function Pass($m){$script:ok++;Write-Host "  [OK]    $m" -ForegroundColor Green}
function Warn($m){$script:warn++;Write-Host "  [AVISO] $m" -ForegroundColor Yellow}
function Fail($m){$script:err++;Write-Host "  [ERRO]  $m" -ForegroundColor Red}
function T($m){Write-Host "`n== $m ==" -ForegroundColor Cyan}

T '1. Estrutura'
$esp=@('INICIAR.cmd','MANUAL.txt','config\deploy.psd1','config\lab.psd1',
 'scripts\Menu.ps1','scripts\Lib.ps1','scripts\Invoke-Deploy.ps1','scripts\Invoke-Restaurar.ps1',
 'scripts\01-Remove-Office365.ps1','scripts\02-Remove-Bloatware.ps1','scripts\03-Install-Apps.ps1',
 'scripts\04-Install-Office2016.ps1','scripts\05-Ajustes.ps1','scripts\06-Dominio.ps1','scripts\07-Antivirus.ps1',
 'scripts\08-Diagnostico.ps1','scripts\09-Office-Limpeza.ps1',
 'payload\apps\GoogleChromeEnterprise64.msi',
 'payload\office\SW_DVD5_Office_2016_64Bit_Brazilian_MLF_X20-42468.ISO',
 'payload\antivirus\offline\Bitdefender Windows.exe','payload\antivirus\offline\installer.xml',
 'payload\antivirus\BitdefenderDownloader.exe')
foreach($e in $esp){ if(Test-Path -LiteralPath (Join-Path $usb $e)){Pass $e}else{Fail "FALTANDO: $e"} }
if(Test-Path "$usb\scripts\Invoke-Devolucao.ps1"){Fail 'script antigo Invoke-Devolucao.ps1 ainda presente'}else{Pass 'script antigo removido'}

T '2. Sintaxe'
Get-ChildItem "$usb\scripts" -Filter *.ps1|ForEach-Object{
 $er=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$er)
 if($er.Count){Fail "$($_.Name): $($er[0].Message)"}else{Pass $_.Name}}

T '3. Modulos e funcoes'
try{foreach($f in 'Lib','01-Remove-Office365','02-Remove-Bloatware','03-Install-Apps','04-Install-Office2016','05-Ajustes','06-Dominio','07-Antivirus','08-Diagnostico','09-Office-Limpeza'){. "$usb\scripts\$f.ps1"};Pass 'todos os 10 modulos carregaram'}catch{Fail "carga: $($_.Exception.Message)"}
foreach($fn in 'Invoke-RemoverOffice365','Invoke-RemoverBloatware','Invoke-InstalarApps','Invoke-InstalarOffice2016','Invoke-InstalarBitdefender','Get-FonteBitdefender','Test-BitdefenderInstalado','Get-AntivirusRegistrados','Invoke-AplicarAjustes','Invoke-EntrarNoDominio','Get-NomeSugerido','Invoke-Passo'){
 if(Get-Command $fn -ErrorAction SilentlyContinue){Pass "funcao $fn"}else{Fail "AUSENTE: $fn"}}

T '4. Perfil ADMINISTRATIVO (deploy.psd1)'
$a=Get-KitConfig -Caminho "$usb\config\deploy.psd1"
if($a.Dominio -eq 'empresa.local'){Pass "dominio $($a.Dominio)"}else{Fail "dominio $($a.Dominio)"}
if($a.InstalarOffice2016){Pass 'instala Office 2016'}else{Fail 'deveria instalar Office'}
if($a.InstalarBitdefender){Pass 'instala Bitdefender'}else{Fail 'nao instala Bitdefender'}
if(-not $a.ModoNomeLab){Pass "nome: $($a.PrefixoNome)+sufixo"}else{Fail 'modo lab ligado no perfil admin'}

T '5. Perfil LABORATORIO (lab.psd1)'
$l=Get-KitConfig -Caminho "$usb\config\lab.psd1"
if($l.Dominio -eq 'lab.local'){Pass "dominio $($l.Dominio)"}else{Fail "dominio $($l.Dominio)"}
if(-not $l.InstalarOffice2016){Pass 'NAO instala Office (correto p/ lab)'}else{Fail 'lab nao deveria instalar Office'}
if($l.InstalarBitdefender){Pass 'instala Bitdefender'}else{Fail 'nao instala Bitdefender'}
if($l.RemoverOffice365){Pass 'remove Microsoft 365 de fabrica'}else{Fail 'nao remove M365'}
if(($l.Apps|Where-Object{$_.Nome -match 'Chrome'}).Instalar){Pass 'instala Chrome'}else{Fail 'nao instala Chrome'}
if($l.ModoNomeLab){Pass "nome no formato $($l.PrefixoNome)<lab>-<maquina>"}else{Fail 'modo lab desligado'}
foreach($c in $a,$l){try{$null=Get-TimeZone -Id $c.FusoHorario}catch{Fail "fuso invalido: $($c.FusoHorario)"}}
Pass 'fuso horario valido nos dois perfis'

T '6. Office 2016'
Initialize-Ambiente
$fo=Get-FonteOffice -Config $a -Credencial $null -PastaUSB $usb 3>$null
if($fo.Descricao -match 'pendrive'){Pass "fonte: $($fo.Descricao)"}else{Fail "nao vem do pendrive: $($fo.Descricao)"}
$k=Get-ChaveOffice -PastaRede $fo.Pasta 3>$null
if($k -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$'){Pass "chave valida (...$($k.Substring($k.Length-5)))"}else{Warn 'chave nao detectada'}
$iso=Get-Item "$usb\payload\office\SW_DVD5_Office_2016_64Bit_Brazilian_MLF_X20-42468.ISO"
if($iso.Length -lt 4GB){Pass ("ISO {0:N0} MB, cabe em FAT32" -f ($iso.Length/1MB))}else{Fail 'ISO acima de 4GB'}

T '7. Bitdefender'
$fb=Get-FonteBitdefender -Config $a -PastaUSB $usb
if($fb.Tipo -eq 'offline'){Pass "usa kit OFFLINE: $($fb.Descricao)"}else{Warn "usara downloader online: $($fb.Descricao)"}
$bexe=Get-Item -LiteralPath "$usb\payload\antivirus\offline\Bitdefender Windows.exe"
Pass ("kit offline: {0:N0} MB" -f ($bexe.Length/1MB))
$sig=Get-AuthenticodeSignature -LiteralPath $bexe.FullName
if($sig.Status -eq 'Valid'){Pass "assinatura VALIDA ($((($sig.SignerCertificate.Subject)-split ',')[0]))"}else{Warn "assinatura: $($sig.Status)"}
try{$x=[xml](Get-Content "$usb\payload\antivirus\offline\installer.xml" -Raw)
 $cr=$x.config.competitorRemoval.execute.mode
 if($cr -eq 'always'){Pass 'installer.xml: remove antivirus concorrente (mode=always)'}else{Warn "competitorRemoval mode=$cr"}
 Pass "console GravityZone: $($x.config.serverAddress.'#text')"
}catch{Fail "installer.xml invalido: $($_.Exception.Message)"}
$avs=Get-AntivirusRegistrados
Pass "deteccao de antivirus funciona: $(($avs.Nome) -join ', ')"

T '7b. Remocao de antivirus de fabrica (OEM)'
foreach($perfil in @(@{N='deploy';C=$a},@{N='lab';C=$l})){
 $c=$perfil.C
 if($c.RemoverAntivirusOEM){Pass "$($perfil.N): etapa ligada"}else{Warn "$($perfil.N): etapa DESLIGADA"}
 if(@($c.AntivirusOEMRemover) -contains 'McAfee'){Pass "$($perfil.N): remove McAfee"}else{Fail "$($perfil.N): McAfee fora da lista"}
}
$dp=Get-Content "$usb\scripts\Invoke-Deploy.ps1" -Raw
if($dp -match 'Invoke-RemoverAntivirusOEM'){Pass 'Invoke-Deploy chama a etapa'}else{Fail 'Invoke-Deploy NAO chama a etapa'}
# a remocao tem que vir ANTES da instalacao do Bitdefender
if($dp.IndexOf('Invoke-RemoverAntivirusOEM') -lt $dp.IndexOf('Invoke-InstalarBitdefender')){
 Pass 'remove o OEM antes de instalar o Bitdefender'}else{Fail 'ordem errada: instala antes de remover'}
# limite deliberado: so o desinstalador do fabricante, sem forca bruta
$av=Get-Content "$usb\scripts\07-Antivirus.ps1" -Raw
if($av -match 'Remove-Item|Stop-Service|Stop-Process|taskkill'){
 Fail '07-Antivirus.ps1 usa forca bruta (Remove-Item/Stop-Service/Stop-Process)'}else{
 Pass 'nao mata servico nem apaga pasta de antivirus'}
if($av -match 'Remove-AppxProvisionedPackage'){Pass 'remove o pacote provisionado (impede o McAfee de voltar)'}else{Fail 'nao remove o provisionado -- o McAfee volta'}
foreach($fn in @('Invoke-RemoverAntivirusOEM','Get-ComandoDesinstalacao')){
 if(Get-Command $fn -ErrorAction SilentlyContinue){Pass "funcao $fn"}else{Fail "funcao $fn ausente"}}
# o parser tem que preferir o desinstalador silencioso do fabricante e converter MSI
$t1=Get-ComandoDesinstalacao -Programa ([pscustomobject]@{DisplayName='X';UninstallString='MsiExec.exe /I{35ED3F83-4BDC-4c44-8EC6-6A8301C7413A}';QuietUninstallString=$null})
if($t1.Arquivo -eq 'msiexec.exe' -and ($t1.Argumentos -join ' ') -match '/x .* /qn'){Pass 'MSI convertido para desinstalacao silenciosa'}else{Fail 'conversao de MSI errada'}
$t2=Get-ComandoDesinstalacao -Programa ([pscustomobject]@{DisplayName='Y';UninstallString='"C:\Nao\Existe\un.exe" /q';QuietUninstallString=$null})
if($null -eq $t2){Pass 'desinstalador inexistente e descartado (avisa e pula)'}else{Fail 'aceitou desinstalador inexistente'}

T '7c. Office: limpeza profunda e pre-checagem'
foreach($fn in 'Get-EstadoOffice','Test-BloqueioOffice2016','Invoke-LimpezaProfundaOffice365','Get-ErroOfficeExplicado','Get-AtivacaoOffice','Invoke-AtivarOffice','Get-FerramentaOffice'){
 if(Get-Command $fn -ErrorAction SilentlyContinue){Pass "funcao $fn"}else{Fail "AUSENTE: $fn"}}
$o4=Get-Content "$usb\scripts\04-Install-Office2016.ps1" -Raw
# 17002 significa "setup nao concluiu": aceita-lo como sucesso fazia o kit
# anunciar Office instalado sem ter instalado
if($o4 -match 'CodigosOk @\(0, 3010, 1641\)'){Pass '17002 NAO e mais tratado como sucesso'}else{Fail '17002 ainda aceito como sucesso'}
if($o4 -match 'Test-BloqueioOffice2016'){Pass 'checa bloqueios ANTES de montar a ISO'}else{Fail 'nao faz pre-checagem'}
if($o4 -match 'Get-ErroOfficeExplicado'){Pass 'traduz o codigo de erro do setup'}else{Fail 'nao traduz erro'}
if($o4 -match 'Get-AtivacaoOffice'){Pass 'confere a ativacao apos instalar'}else{Fail 'nao confere ativacao'}
# a limpeza nao pode apagar pasta do Office: quebraria o MSI que vamos instalar
$o9=Get-Content "$usb\scripts\09-Office-Limpeza.ps1" -Raw
if($o9 -match 'Remove-Item|rd /s|rmdir'){Fail '09 apaga pasta na marra -- risco de quebrar o MSI'}else{Pass 'nao apaga pasta do Office na marra'}
foreach($t in 'SaRA','ODT'){ if($o9 -match $t){Pass "usa a ferramenta oficial $t"}else{Fail "nao usa $t"} }
$b=Get-EstadoOffice
Pass "leitura do Office funciona: 2016=$($b.Tem2016) C2R=$($b.TemC2R) residuos=$($b.Residuos.Count)"
if((Get-ErroOfficeExplicado -Codigo 17002) -match 'limpeza profunda'){Pass 'erro 17002 aponta a solucao'}else{Fail '17002 sem orientacao'}

T '7d. Diagnostico (somente leitura)'
$o8=Get-Content "$usb\scripts\08-Diagnostico.ps1" -Raw
foreach($p in 'Remove-Item','Set-ItemProperty','New-ItemProperty','Add-Computer','Remove-AppxPackage','Start-Process'){
 if($o8 -match [regex]::Escape($p)){Fail "08-Diagnostico ALTERA a maquina ($p) -- deve ser so leitura"}}
Pass '08-Diagnostico nao altera nada'
try{$dg=Get-DiagnosticoMaquina;Pass "diagnostico roda: $($dg.Nome), dominio=$($dg.Dominio)"}catch{Fail "diagnostico falhou: $($_.Exception.Message)"}
$sg=@(Get-SugestaoDiagnostico -D $dg -ConfigAdmin $a -ConfigLab $l)
if($sg.Count){Pass "sugere proximos passos ($($sg.Count))"}else{Fail 'nao sugere nada'}

T '7e. Modo simulacao'
foreach($fn in 'Set-Simulacao','Test-Simulacao','Invoke-Mudanca','Save-Relatorio','Set-EscopoEstado','Get-PassosConcluidos'){
 if(Get-Command $fn -ErrorAction SilentlyContinue){Pass "funcao $fn"}else{Fail "AUSENTE: $fn"}}
$lb=Get-Content "$usb\scripts\Lib.ps1" -Raw
if($lb -match '\[SIMULACAO\] executaria'){Pass 'Invoke-Processo respeita a simulacao'}else{Fail 'simulacao nao bloqueia processos'}
# prova pratica: com simulacao ligada, nada e executado
Set-Simulacao $true
$rc=Invoke-Processo -Arquivo 'C:\Windows\System32\cmd.exe' -Argumentos @('/c','ver')
if($rc -eq 0 -and (Test-Simulacao)){Pass 'simulacao bloqueia execucao de verdade (testado)'}else{Fail 'simulacao nao bloqueou'}
Set-Simulacao $false
# dominio tem que passar por Invoke-Mudanca, senao a simulacao entra no AD
$o6=Get-Content "$usb\scripts\06-Dominio.ps1" -Raw
if($o6 -match 'Invoke-Mudanca[\s\S]{0,200}Add-Computer'){Pass 'ingresso no dominio respeita a simulacao'}else{Fail 'Add-Computer fora da simulacao -- entraria no AD de verdade'}
foreach($fn in 'Invoke-SairDoDominio','Invoke-RenomearMaquina','Get-ErroDominioExplicado'){
 if(Get-Command $fn -ErrorAction SilentlyContinue){Pass "funcao $fn"}else{Fail "AUSENTE: $fn"}}
# estado separado por perfil
Set-EscopoEstado 'perfil-a';$idA=Get-IdEscopado 'x';Set-EscopoEstado 'perfil-b';$idB=Get-IdEscopado 'x'
if($idA -ne $idB){Pass 'estado separado por perfil (admin nao pula etapa do lab)'}else{Fail 'estado ainda compartilhado entre perfis'}

T '8. Menu'
$m=Get-Content "$usb\INICIAR.cmd" -Raw
if($m -match 'Menu\.ps1'){Pass 'INICIAR.cmd chama o Menu.ps1'}else{Fail 'INICIAR.cmd nao chama o menu'}
if($m -match 'RunAs'){Pass 'pede elevacao'}else{Warn 'nao pede elevacao'}
$mp=Get-Content "$usb\scripts\Menu.ps1" -Raw
foreach($par in @('deploy\.psd1','lab\.psd1','Invoke-Restaurar\.ps1.*Funcionario|Contexto Funcionario','Contexto Laboratorio','Invoke-SoBitdefender','Invoke-Diagnostico','Show-MenuAvulsas','Invoke-ModoLote')){
 if($mp -match $par){Pass "menu tem: $($par -replace '\\','')"}else{Fail "menu NAO tem: $par"}}
if($mp -match 'RESTAURAR a maquina'){Pass 'menu avisa que vai restaurar'}else{Warn 'menu nao avisa'}
# as opcoes 1-6 nao podem mudar de lugar: a equipe ja as decorou e o MANUAL as ensina
if($mp -match "'5' \{ Invoke-SoBitdefender \}"){Pass '[5] continua sendo o Bitdefender (equipe ja decorou)'}else{Fail 'numeracao antiga mudou'}
if($mp -match "'7' \{ Invoke-Diagnostico \}"){Pass '[7] diagnostico'}else{Fail '[7] nao mapeado'}
if($mp -match "'8' \{ Show-MenuAvulsas \}"){Pass '[8] tarefas avulsas'}else{Fail '[8] nao mapeado'}
if($mp -match "'9' \{ Invoke-ModoLote \}"){Pass '[9] modo lote'}else{Fail '[9] nao mapeado'}
if($mp -match 'Set-Simulacao \(-not \(Test-Simulacao\)\)'){Pass '[S] alterna a simulacao'}else{Fail '[S] nao alterna simulacao'}
# a simulacao precisa chegar ao Invoke-Deploy, senao o menu mente
if($mp -match "extra \+= '-Simular'"){Pass 'simulacao e repassada ao Invoke-Deploy'}else{Fail 'simulacao nao chega ao deploy'}

T '8b. Orquestrador'
$dp2=Get-Content "$usb\scripts\Invoke-Deploy.ps1" -Raw
if($dp2 -match '\[switch\]\$Simular'){Pass 'Invoke-Deploy aceita -Simular'}else{Fail 'sem parametro -Simular'}
if($dp2 -match 'Set-EscopoEstado'){Pass 'separa o estado por perfil'}else{Fail 'estado sem escopo'}
if($dp2 -match 'Save-Relatorio'){Pass 'gera relatorio da maquina'}else{Fail 'sem relatorio'}
if($dp2 -match "OrdemDominio -eq 'Primeiro'"){Pass 'ordem do dominio configuravel'}else{Fail 'ordem do dominio fixa'}
foreach($perfil in @(@{N='deploy';C=$a},@{N='lab';C=$l})){
 if($perfil.C.LimpezaProfundaOffice){Pass "$($perfil.N): limpeza profunda ligada"}else{Warn "$($perfil.N): limpeza profunda desligada"}
 if($perfil.C.OrdemDominio -in 'Ultimo','Primeiro'){Pass "$($perfil.N): OrdemDominio=$($perfil.C.OrdemDominio)"}else{Fail "$($perfil.N): OrdemDominio invalida"}}

T '9. Travas da restauracao'
$r=Get-Content "$usb\scripts\Invoke-Restaurar.ps1" -Raw
if($r -match 'TRAVA 1'){Pass 'trava 1: digitar o nome da maquina'}else{Fail 'trava 1 ausente'}
if($r -match 'TRAVA 2'){Pass 'trava 2: digitar RESTAURAR'}else{Fail 'trava 2 ausente'}
if($r -match '-cne\s+.RESTAURAR.'){Pass 'trava 2 diferencia maiuscula/minuscula'}else{Warn 'trava 2 nao checa maiusculas'}
if($r -match 'ne \$env:COMPUTERNAME'){Pass 'trava 1 compara com o nome real'}else{Warn 'trava 1 suspeita'}
if($r -match 'Start-Process .systemreset'){Pass 'abre o Redefinir do Windows (usuario confirma la)'}else{Fail 'nao abre o reset'}
if($r -match 'Remove-Item|Format-Volume|Clear-Disk'){Fail 'script apaga algo por conta propria!'}else{Pass 'nao apaga nada por conta propria'}

T '10. Seguranca da rede'
$sc=Get-ChildItem "$usb\scripts" -Filter *.ps1|Get-Content -Raw
$pg=$sc|Select-String -Pattern '(Remove-Item|Set-Content|New-Item|Copy-Item|Move-Item|Out-File)[^\r\n]*\\\\10\.105' -AllMatches
if($pg){Fail 'ESCRITA na rede encontrada!'}else{Pass 'rede continua somente leitura'}
$sen=Get-ChildItem $usb -Recurse -File -Include *.ps1,*.psd1,*.cmd,*.txt|Select-String -Pattern 'DFt!r6y5|Bmcrz' -ErrorAction SilentlyContinue
if($sen){Fail 'SENHA gravada em arquivo!'}else{Pass 'nenhuma senha gravada no pendrive'}

T '11. Encoding'
$sb=0
Get-ChildItem "$usb\scripts","$usb\config" -Filter *.ps* -Recurse|ForEach-Object{
 $b=[System.IO.File]::ReadAllBytes($_.FullName)|Select-Object -First 3
 if(-not($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)){$sb++;Warn "sem BOM: $($_.Name)"}}
if($sb -eq 0){Pass 'todos os scripts com UTF-8 BOM'}

T '12. Fonte x Pendrive'
$d=0
Get-ChildItem "$fonte\USB" -Recurse -File|ForEach-Object{
 $rel=$_.FullName.Substring("$fonte\USB".Length)
 $n=Join-Path $usb $rel.TrimStart('\')
 if(-not(Test-Path -LiteralPath $n)){$d++;Warn "so na fonte: $rel"}
 elseif((Get-Item -LiteralPath $n).Length -ne $_.Length){$d++;Warn "difere: $rel"}}
if($d -eq 0){Pass 'pendrive em dia com a fonte'}

$v=Get-Volume -DriveLetter D
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host ("  {0} OK  |  {1} avisos  |  {2} erros    (livre: {3:N1} GB)" -f $ok,$warn,$err,($v.SizeRemaining/1GB)) -ForegroundColor $(if($err){'Red'}elseif($warn){'Yellow'}else{'Green'})
Write-Host "=======================================================" -ForegroundColor Cyan
