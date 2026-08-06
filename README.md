# WinDeployKit

[![lint](https://github.com/enzo-going/windows-deploy-kit/actions/workflows/lint.yml/badge.svg)](https://github.com/enzo-going/windows-deploy-kit/actions/workflows/lint.yml)

Pendrive que prepara e restaura máquinas Windows sem acompanhamento. Substitui um
processo manual de mais de uma hora por máquina: tirar o Microsoft 365 de fábrica,
instalar Office 2016 VL, Chrome e antivírus, remover bloatware, aplicar ajustes e
entrar no domínio — tudo a partir de um `INICIAR.cmd`.

PowerShell 5.1 puro (é o que existe numa máquina recém-formatada), sem
dependências, funciona offline exceto pelo ingresso no domínio e a ativação do
Office.

> **Manual da equipe técnica:** [`USB/MANUAL.txt`](USB/MANUAL.txt)

---

## O que ele cobre

Dois perfis de configuração, dois momentos:

| Perfil | Momento | Ação |
|---|---|---|
| Administrativo | Máquina nova ou recém-restaurada | Remove 365, instala Office 2016, Chrome, antivírus, entra no domínio |
| Administrativo | PC devolvido por funcionário | Confere, relata o que será perdido e restaura |
| Laboratório | Troca de turma | Confere e restaura |
| Laboratório | PC já restaurado | Prepara **sem Office**: remove 365, Chrome, antivírus, domínio |

Em toda preparação: remove o antivírus OEM de fábrica (McAfee/Norton) e instala o
antivírus corporativo.

## Menu

```
  ADMINISTRATIVO
   [1] PREPARAR PC                              verde    = prepara
   [2] RESTAURAR PC devolvido por funcionario   vermelho = apaga
  LABORATORIOS
   [3] RESTAURAR PC de laboratorio              vermelho = apaga
   [4] PREPARAR PC de laboratorio               verde    = prepara
  OUTROS
   [5] Instalar / reparar so o antivirus
   [6] Abrir o manual
  FERRAMENTAS
   [7] DIAGNOSTICO desta maquina        so le, nao muda nada
   [8] Tarefas avulsas                  fazer uma coisa so
   [9] Modo LOTE                        varios notebooks seguidos
   [S] Modo SIMULACAO                   mostra o que faria, sem fazer
   [0] Sair
```

Regra ensinada à equipe: **verde prepara, vermelho apaga. Depois de apagar,
roda uma verde.**

### Tarefas avulsas `[8]`

| | | | |
|---|---|---|---|
| `[1]` | Limpeza profunda do Microsoft 365 | `[6]` | Aplicar ajustes (energia, fuso, Explorer) |
| `[2]` | Instalar o Office 2016 | `[7]` | Remover antivírus de fábrica |
| `[3]` | Verificar / ativar a licença do Office | `[8]` | Entrar no domínio / renomear |
| `[4]` | Instalar Chrome e apps padrão | `[9]` | Sair do domínio |
| `[5]` | Remover bloatware da Store | | |

## Uso

No notebook a preparar, com o pendrive espetado:

```
<pendrive>\Teste_Programa\INICIAR.cmd
```

Aceite a elevação e escolha a opção.

Deu erro no meio? **Rode de novo.** As etapas que deram certo são puladas
(controle em `C:\WinDeployKit\estado.json`, separado por perfil).

## Configuração

Tudo em `USB/config/*.psd1` — os valores que vêm no repositório são de exemplo
(`empresa.local`, `\\servidor-arquivos\...`). Os scripts não precisam ser
editados para trocar domínio, nome de máquina, lista de apps ou etapas.

| Arquivo | Para quê |
|---|---|
| `deploy.psd1` | Perfil administrativo |
| `lab.psd1` | Perfil laboratório (rotatividade de turma) |

| Chave | Para quê |
|---|---|
| `Dominio`, `OU`, `UsuarioDominio` | Ingresso no AD (a **senha** nunca fica em arquivo) |
| `PrefixoNome` | Padrão de nome da máquina; o script pergunta só o sufixo |
| `PastaOffice2016` | Origem da ISO do Office na rede, se não estiver no pendrive |
| `LimpezaProfundaOffice` | Usa SaRA/ODT antes de instalar o Office (padrão `$true`) |
| `OrdemDominio` | `'Ultimo'` (padrão) ou `'Primeiro'` |
| `AppxRemover` / `AppxManter` | Bloatware da Store |
| `Apps` | Instaladores offline, com fallback para `winget` |
| `EntrarNoDominio` | `$false` para testar sem tocar no AD |

## Preparar o pendrive

Num PC com internet:

```powershell
.\Preparar-Pendrive.ps1 -BaixarFerramentasOffice -Pendrive D:
```

`-BaixarFerramentasOffice` baixa o SaRA, ferramenta oficial da Microsoft que
remove Microsoft 365 teimoso. **Sem ela, os casos difíceis de Office falham.**

A sincronização usa `robocopy /E`, nunca `/MIR` — `/MIR` apagaria o payload
(ISO do Office, kit do antivírus), que só existe no pendrive e nunca entra no
repositório.

## Verificação

```powershell
.\tools\Verificar-Kit.ps1 -Pendrive D:
```

148 checagens sobre o pendrive: estrutura, sintaxe, carga dos módulos, perfis,
pré-checagem do Office, travas da restauração, modo simulação, ausência de
escrita na rede e de senha gravada, encoding e sincronia com a fonte.

## Quando o Office 2016 não instala

É o problema que mais custa tempo, e tem uma causa só: o Office 2016 MSI se
recusa a instalar se sobrar **qualquer** rastro de Click-to-Run. O desinstalador
comum do 365 deixa serviço, chaves e pacotes da Store para trás — e o setup
reclama de um resíduo diferente a cada tentativa.

O caminho é `[7]` (diagnóstico, que lista os bloqueios) e depois `[8] > [1]`
(limpeza profunda, que usa as ferramentas oficiais da Microsoft em camadas:
SaRA → ODT → desinstalador do produto, conferindo o resultado).

O kit **nunca** apaga a pasta do Office na marra: isso quebraria justamente o
MSI que se quer instalar. Se as ferramentas oficiais não resolverem, ele avisa
em vez de improvisar.

Licença KMS: a máquina precisa enxergar o servidor KMS da rede para ativar. Um
notebook preparado fora da rede instala o Office mas fica em "período de
carência"; depois de pô-lo na rede, use `[8] > [3]`.

## Estrutura

```
WinDeployKit/
├─ Preparar-Pendrive.ps1        baixa instaladores e copia o kit
├─ tools/Verificar-Kit.ps1      suite de verificacao
├─ ISO/                         instalacao desatendida do Windows (opcional)
└─ USB/                         <- isto e o que vai no pendrive
   ├─ INICIAR.cmd               ponto de entrada
   ├─ MANUAL.txt                manual da equipe
   ├─ config/
   │  ├─ deploy.psd1            perfil administrativo
   │  └─ lab.psd1               perfil laboratorio
   ├─ payload/                  binarios (so no pendrive, nunca no repo)
   └─ scripts/
      ├─ Menu.ps1               menu, submenus, lote, simulacao
      ├─ Lib.ps1                log, estado, simulacao, relatorio, credencial
      ├─ Invoke-Deploy.ps1      orquestrador
      ├─ Invoke-Restaurar.ps1   checagem, travas e reset
      ├─ 01..07                 etapas do processo
      ├─ 08-Diagnostico.ps1     leitura do estado da maquina
      └─ 09-Office-Limpeza.ps1  limpeza profunda do 365 e licenca
```

## Regras que o projeto não quebra

- **Senha de domínio nunca vai para arquivo, log ou linha de comando.** A
  credencial vem de `Get-Credential`, vive só em memória e é anulada no
  `finally`. Só o *nome de usuário* fica pré-preenchido no `.psd1`.
- **Pastas de rede são somente leitura.** Para usar um arquivo da rede, copia-se
  para o disco local e trabalha-se na cópia.
- **Nenhum script apaga dados por conta própria.** Restaurar significa conferir,
  relatar o que será perdido, exigir duas travas (digitar o nome da máquina e a
  palavra `RESTAURAR`) e só então abrir o `systemreset`, onde o Windows ainda
  pede a confirmação dele. `Remove-Item`, `Format-Volume` e `Clear-Disk` sobre
  dados do usuário são proibidos em qualquer caminho de restauração.
- **Ao varrer perfis, vazio ≠ acesso negado.** Reportar pasta ilegível como
  vazia leva alguém a apagar arquivo alheio.
- **A remoção do Microsoft 365 toca somente Click-to-Run.** Instalações MSI
  ficam intactas — o Office 2016 VL é MSI e seria destruído.
- **Não se escreve rotina própria de desinstalação de antivírus.** Antivírus têm
  proteção anti-tamper e `UninstallString` genérico falha pela metade, deixando
  a máquina sem proteção. A remoção do concorrente é feita pelo instalador do
  antivírus corporativo (`competitorRemoval`); o papel do kit é detectar, avisar
  e conferir no final. A exceção é o antivírus OEM de fábrica, que é bloatware e
  usa só o desinstalador que o próprio fabricante registrou.
- **Toda etapa é idempotente e retomável** (`Invoke-Passo`). Etapa que exige
  reboot (domínio) é sempre a última.
- **PowerShell 5.1**, arquivos `.ps1`/`.psd1` em UTF-8 com BOM, console output
  sem acentos (para não depender de code page).

**Antes de usar em produção, teste em máquina descartável** — ou use o modo
simulação `[S]`, que mostra tudo que seria feito sem alterar nada.

## Licença

MIT — veja [LICENSE](LICENSE).
