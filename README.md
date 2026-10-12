# Me x1000 (v2)

Jogo de Roblox: você aperta **GRAVAR**, tem **20 segundos** para correr, pular e pegar moedas, e ao parar nasce um **clone com o seu avatar** que repete exatamente aquele caminho em loop, para sempre. Cada clone vira uma **Fita** na estante da sua base. Monte um exército de cópias, evolua sua base de tycoon, proteja o Cofre, roube fitas dos outros e derrube clones alheios com **cascas de banana**.

O projeto vive 100% em código (Luau + [Rojo](https://rojo.space)). O mapa, os modelos, a UI e os efeitos são todos criados por scripts: não existe nenhum `.rbxm`.

> O resumo do MVP v1 (antes destas melhorias) está em [`docs/ESTADO_ATUAL.md`](docs/ESTADO_ATUAL.md).

---

## O que mudou na v2

| Área | v1 | v2 |
|---|---|---|
| Mapa | 8 bases juntas numa praça, baseplate vazio | **8 plots de tycoon (70×70) em anel nas bordas** + **Cidade de Blocos** no centro com 4 bairros, ruas, calçadas, montanhas e árvores no horizonte |
| Base | piso colorido + pedestal | **base com níveis 1–6** (blocos caem do céu e encaixam), porta laser, estante de fitas, **Cofre**, **Pista de Gravação** particular |
| Clones | só na cidade | gravados na **Cidade** ou na **Pista da base**; cada um é uma **Fita** física na estante |
| Dinheiro dos clones | direto no Cash | cai no **Cofre** (com limite); o dono encosta para coletar |
| PvP | só bananas | **roubo de fitas** e de 25% do Cofre, **porta laser**, **tapa**, **laser de defesa**, proteção de novato, alertas |
| UI | estilo 2010 | **design system** (vidro escuro, Builder Sans, gradientes, animações), barra de ícones, cartões, GRAVAR circular com anel de progresso, blur nos menus |
| Áudio | nenhum | **música** com crossfade por zona, **ambiente** dia/noite e água 3D, **efeitos** |
| Luz | Compatibility | **Future** + Atmosphere, ColorCorrection, SunRays e **ciclo dia/noite de 12 min** (postes acendem à noite) |
| Desempenho | — | **StreamingEnabled**, decoração em Models `Atomic`, sem sombra em peças pequenas, `/stress` para teste de carga |

### Layout do mapa
- **Plots**: anel de raio 192 nos ângulos 22,5° + 45°·k, cada um olhando para a cidade. Cada jogador recebe um plot ao entrar e **nasce nele** (SpawnLocation + `RespawnLocation`). A placa grande em cima do portão mostra o **avatar (headshot)**, o nome e a cor do dono.
- **Caminhos de tijolo** ligam cada portão à rua em anel. Teleporte rápido **Ir para Base / Ir para Cidade** na HUD (tecla T).
- **Cidade de Blocos** (−115..115):
  - **Praça Central**: fonte com partículas, bancos, postes, canteiros, coreto e placa de ranking. Rota fácil.
  - **Parque** (noroeste): lago com ponte, árvores de 3 tamanhos, playground (escorregador e balanço) e trilha de pedras de pular.
  - **Canteiro de Obras** (nordeste): guindaste, andaime, vigas, esqueleto de prédio e esteiras. Rota difícil, com mais gemas.
  - **Castelo** (sudoeste): muralhas, torre em espiral com o **Baú** no topo, ponte levadiça com fosso, bandeiras nas cores das bases e a **sala VIP**.
  - **Bairro** (sudeste): prédios com parkour de telhado, carros estacionados, hidrantes, caixas de correio e lixeiras.
- **Bordas**: montanhas de blocos em degraus (com neve nos picos) e linhas de árvores.
- **Céu e vida**: nuvens de blocos e pássaros voando em loop (criados só no cliente).
- Módulos: `Build/MapBuilder` (orquestra), `PlotBuilder`, `CityBuilder`, `DecorBuilder`, `LightingSetup`, `Prefabs`. O layout dos plots é compartilhado em `Shared/MapLayout` (o cliente sabe onde fica cada base mesmo com streaming).

### Base de tycoon (níveis 1–6, preços em `Config.BaseLevels`)
| Nível | O que aparece | Vagas de fita | Cofre |
|---|---|---|---|
| 1 | piso, porta laser, estante, Pista curta, Cofre | 3 | 600 |
| 2 | muro baixo, rampa + plataforma e esteira na Pista | 5 | 2.5K |
| 3 | segundo andar com escada, trampolim e plataforma alta na Pista | 8 | 10K |
| 4 | torre de vigia, **plataforma móvel** (PrismaticConstraint) e gemas na Pista | 11 | 40K |
| 5 | telhado sobre a estante e **laser de defesa** | 15 | 150K |
| 6 | base dourada (Neon) e **baú próprio** na Pista | 20 | 600K |

- Compra pelo **botão redondo no chão da base** (pise nele) ou pelo menu **Base**.
- Vagas = nível da base + 1 por rebirth + 5 do passe ExtraSlots (teto 30 = estante cheia).
- **Pista de Gravação**: só o dono e os clones dele coletam as moedas dela. Rende menos que a Cidade (respawn mais lento), mas é segura de banana.
- Fitas da Pista são salvas no **espaço local do plot**: funcionam em qualquer base que você pegar na próxima sessão (e na base do ladrão, se forem roubadas).
- **Cofre**: o dinheiro dos clones cai nele até o limite (com o passe AutoCollect vai direto para o Cash). Encoste no Cofre para coletar.

### Roubo e defesa
- Com a porta aberta, outros jogadores podem **pegar uma fita** (segurar E), que vai **nas costas** e deixa o ladrão 30% mais lento. Ele precisa levá-la até a **estante da própria base**. Se conseguir, o clone passa para ele com o caminho original e os dois perfis são salvos na hora.
- Encostar no Cofre alheio leva **25%** (uma vez por base a cada 2 min).
- **Tapa** (tecla F / botão 👋): derruba quem estiver na frente. Ladrão derrubado **solta a fita**, que volta voando para a estante.
- **TRANCAR** (botão no chão da base, botão na HUD dentro da base, tecla L, ou menu Base): 60 s trancada (mais com o nível) e depois 60 s de recarga. Contador em cima do portão.
- **Proteção de novato**: 10 min no começo de cada sessão.
- **Laser de defesa** (nível 5): empurra invasores parados por mais de 3 s.
- **Fitas douradas** (passe GoldenClone) não podem ser roubadas. No máximo **1 fita roubada por base a cada 3 min**. Ladrão que sai do jogo, morre ou demora mais de 90 s devolve a fita.
- **Alertas**: toast vermelho, sirene curta e seta na tela apontando para a sua base, com ofertas contextuais ("Trancar (39 R$)", "Recuperar (49 R$)").

### UI v2
- Design system em `client/Ui/Theme.luau` e componentes em `client/Ui/Components/`: `Button`, `IconButton`, `Panel`, `Tab`, `Card`, `ProgressRing`, `Toast`, `Modal`, `Counter`, `Slider`, `Toggle`.
- Fonte **Builder Sans** (fallback Gotham SSm), painéis de vidro `#151A2B`, paleta `#5B6CFF` / `#2ED47A` / `#FFC83D` / `#FF4D5E`.
- **Topo**: pílula de Cash com contador animado + chip do multiplicador. Logo abaixo, chips de gravando, chuva de moedas, escudo e "clones caídos" com o botão Consertar.
- **Esquerda**: barra de ícones com tooltip e badge "!" (Loja, Base, Fitas, Rebirth, Diário, Códigos, Config, teleporte). No celular vira uma grade 4×2 no topo-esquerdo, longe do joystick.
- **Direita**: cartões de Fitas, Cofre (com barra), Bananas e Porta.
- **Inferior direito**: GRAVAR circular com anel de progresso (pulsa quando parado) + Banana, Tapa e Trancar.
- **Menus** com abas, cards em grade, selo "MAIS POPULAR", blur no fundo e tween de abrir/fechar. Tela de **Fitas** com mini-mapa do trajeto, renda por minuto, Regravar e Excluir.
- **Configurações**: volume de música, ambiente e efeitos, clones visíveis (30/60/120) e alertas de invasão. Tudo salvo no perfil.
- Mobile first: `ScreenInsets = DeviceSafeInsets`, `UIScale` automático (mínimo 0,9 no toque: botões de 72 px no desenho ficam com ≥ 64 px reais).

### Áudio
- `SoundGroup`s **Music**, **Ambient** e **SFX** (volumes no menu; padrão 0,35 para música e 0,6 para efeitos).
- Música: playlist aleatória com crossfade de 2 s; faixa calma na sua base; faixa animada na Chuva de Moedas; fade-in depois que o jogo carrega.
- Ambiente: pássaros e vento de dia, grilos à noite, água 3D na fonte, no lago e no fosso.
- Efeitos: usam sons que já vêm no cliente (`rbxasset://sounds/...`) até você trocar por IDs melhores.

---

## 1. Instalar as ferramentas

O projeto usa o **Rokit**. O `rokit.toml` já lista `rojo` 7.7.1, `selene`, `stylua`, `lune` e `wally`.

```powershell
# 1x por máquina: instale o Rokit (https://github.com/rojo-rbx/rokit#installation)
rokit install
# baixa o TestEZ (wally.toml) para DevPackages/ — necessário para o rojo serve/build
wally install
```

> Prefere o **Aftman**? Crie um `aftman.toml` com as mesmas linhas do `[tools]` do `rokit.toml` e rode `aftman install`.

Instale também o **plugin do Rojo** no Studio (`rojo plugin install`).

## 2. Rodar no Studio

**Primeira vez**: gere o place com `rojo build`. Ele grava as propriedades que script não consegue alterar: `Lighting.Technology = Future` e `Workspace.StreamingEnabled = true`.

```powershell
rojo build default.project.json -o MeX1000.rbxlx
```

Abra o `MeX1000.rbxlx` no Studio. Depois, para editar com sincronização ao vivo:

```powershell
rojo serve
```

No Studio: **Plugins > Rojo > Connect** e aperte **Play**.

> Se a sua máquina sofrer com `Future`, troque `"Technology": "Future"` por `"ShadowMap"` no `default.project.json` e gere o place de novo.

### DataStore no Studio
Sem ele o jogo roda em **modo memória** (funciona, mas não salva nada; o Output avisa).
1. Publique o place (File > Publish to Roblox).
2. **Game Settings > Security > Enable Studio Access to API Services** = ligado.

O perfil da v1 é **migrado** automaticamente para a v2: os slots comprados viram o nível de base equivalente e as fitas antigas viram fitas da Cidade.

### Configurações do jogo
- **Game Settings > Places > Max Players = 8**.
- (Opcional) **Avatar Type = R6**. O servidor já cria R6 por código.

## 3. Comandos de debug (chat)

Funcionam no Studio (`Config.DebugCommandsInStudio`) ou para `Config.Admins`:

| Comando | Efeito |
|---|---|
| `/stress 240` | **teste de carga**: as bases livres viram "bots" nível 6 (simula 8 jogadores) e 240 clones são espalhados entre a Cidade e as Pistas dos bots |
| `/spawnclones 240` | 240 clones simulados só na Cidade |
| `/clearclones` | remove os clones de teste e limpa as bases de bot |
| `/level` | constrói o próximo nível da sua base de graça |
| `/cash 100000` | soma Cash |
| `/bananas 10` | soma bananas |

O custo do servidor aparece no **MicroProfiler** (Ctrl+F6), marcador `MeX1000.Tick`. O total de Parts do mapa aparece no Output ao iniciar (há um aviso se passar de `Config.MaxPartsBudget` = 8000).

Para testar roubo e alertas: **Test > Clients and Servers > 2 Players** (a proteção de novato dura 10 min: para testar antes, baixe `Config.Lock.NewbieProtection`).

## 4. Testes, lint e formatação

Os testes usam o **TestEZ** (`roblox/testez`, instalado pelo Wally). Cada arquivo `tests/*.spec.luau` retorna uma função com `describe` / `it` / `expect`:

```lua
local load = require(if script then script.Parent.lib.load else "./lib/load")
local EconomyMath = load("EconomyMath") -- módulo de src/shared
local Base64 = load("Base64")

return function()
	describe("Exemplo", function()
		it("matchers mais usados", function()
			expect(EconomyMath.award(1, 1, 1)).to.equal(1)
			expect(EconomyMath.multiplier(3, 0.5, false, 2)).to.be.near(2.5, 1e-9) -- near(x, limite)
			expect(Base64.decode("abc")).never.to.be.ok() -- ok() = não-nil
			expect(function() error("boom") end).to.throw("boom")
		end)
	end)
end
```

Os mesmos specs rodam em dois lugares:

- **No Studio**: ao dar **Play**, `ServerScriptService.Tests.TestRunner` roda tudo com o TestEZ e escreve `Test results: N passed, M failed` no Output (só lista o que falhou). Não roda em servidor publicado. Para desligar, marque o atributo `Disabled = true` no Script `TestRunner`.
- **No terminal** (sem Studio, bom para CI): `lune run test` usa um runner compatível com a API do TestEZ (`.lune/lib/testez.luau`).

```powershell
lune run test            # 57 testes de lógica pura
lune run test Path       # só os specs cujo nome contém "Path"
selene src tests .lune   # lint
stylua --check src tests .lune
```

Cobrem: compressão e interpolação de caminho, transformação das fitas da Pista entre plots, layout dos plots (inclusive "não invade a rua"), vagas da estante, ciclo dia/noite, economia, níveis da base, Base64, spatial hash e textos PT/EN.

## 5. Monetização: IDs para trocar

Todos os IDs ficam em `src/shared/Config.luau` com valor `0` e o comentário `TROCAR`. Com `0`, a loja mostra **"Em breve"** e nada quebra. Crie os itens no [Creator Hub](https://create.roblox.com/dashboard/creations) > seu jogo > **Monetization** e cole cada ID no campo `Id`.

**Passes** (`Config.GamePasses`)
| Chave | Efeito | Preço sugerido |
|---|---|---|
| `ExtraSlots` | +5 vagas de fita | 299 |
| `LongRecord` | gravação 20 s → 40 s | 399 |
| `DoubleCash` | 2x Cash (**mais popular**) | 399 |
| `GoldenClone` | fita #1 rende 3x, brilha e não pode ser roubada | 249 |
| `VIP` | tag [VIP] + sala VIP | 299 |
| `OfflinePlus` | teto offline 8 h → 24 h | 199 |
| `AutoCollect` 🆕 | o Cofre deposita sozinho no Cash | 249 |
| `BigVault` 🆕 | Cofre com capacidade 3x | 199 |
| `FastThief` 🆕 | carrega fita roubada sem perder velocidade | 299 |

**Produtos** (`Config.Products`)
| Chave | Efeito | Preço sugerido |
|---|---|---|
| `FixAllClones` | levanta todos os clones caídos | 29 |
| `Shield30` | escudo anti-banana 30 min | 49 |
| `CoinRain` | 5 min de moedas 3x para o servidor (**mais popular**) | 99 |
| `BananaPack10` | +10 bananas | 25 |
| `DoubleOffline` | dobra o ganho offline | 49 |
| `CashPackS/M/L` | Cash proporcional ao rebirth | 49 / 149 / 399 |
| `LockBase5` 🆕 | tranca a base 5 min (ignora a recarga) | 39 |
| `LockBase30` 🆕 | tranca a base 30 min | 129 |
| `RecoverTape` 🆕 | devolve a última fita roubada | 49 |
| `InstantBaseLevel2..6` 🆕 | constrói o próximo nível na hora (um produto por nível) | 99 / 149 / 249 / 349 / 499 |

**Outros IDs para trocar**
- `Config.Music.Tracks`, `Config.Music.BaseTrack`, `Config.Music.CoinRainTrack`: faixas da **biblioteca de música licenciada do Roblox** (Creator Store > Audio > Music, autoria "Roblox"/APM). Vazias = sem música.
- `Config.Ambient` (`DayBirds`, `Wind`, `NightCrickets`, `Water`): loops de ambiente da Creator Store.
- `Config.Sfx`: já funcionam com os sons do cliente; troque por IDs da Creator Store para mais qualidade.
- `Config.Icons`: ícones gratuitos da Creator Store. Vazios = emoji.
- `Config.GroupId` (recompensa de grupo) e `Config.Codes`.

Regras mantidas: `ProcessReceipt` idempotente (PurchaseId salvo e perfil salvo antes de `PurchaseGranted`), passes com `UserOwnsGamePassAsync` + `PromptGamePassPurchaseFinished`, e **sem itens aleatórios pagos** (TODO no `Config.luau`).

## 6. Publicar

1. `rojo build default.project.json -o MeX1000.rbxlx` e abra o arquivo (ou use o place conectado ao `rojo serve`).
2. **File > Publish to Roblox**.
3. Creator Hub: ícone, thumbnails, descrição, **Max Players = 8** e visibilidade.
4. Crie os passes, produtos, músicas e ícones (seção 5), cole os IDs e publique de novo.

---

## Estrutura

```
default.project.json   Rojo (Lighting Future, StreamingEnabled, Players)
docs/ESTADO_ATUAL.md   resumo do MVP v1
src/shared/            -> ReplicatedStorage.Shared
  Config.luau          TODOS os números e IDs (puro, testável)
  MapLayout.luau       geometria dos plots (mundo <-> local), vagas da estante
  DayNight.luau        ciclo dia/noite determinístico
  Path.luau            compressão, interpolação, mapXZ (fitas da Pista), preview
  Net, Types, Format, Strings (PT/EN), Base64, EconomyMath, SpatialHash, Signal, Clock
src/server/            -> ServerScriptService.Server
  Main.server.luau
  Build/  MapBuilder, PlotBuilder, CityBuilder, DecorBuilder, LightingSetup, Prefabs
  Services/
    DataService        DataStore + lock de sessão + migração v1 -> v2
    PlotService        plots, níveis, cofre, porta laser, invasão, laser de defesa, teleporte
    TheftService       fitas na estante, roubo, entrega, tapa, recuperação
    CloneService       clones = dados; zonas Cidade/Pista; trânsito; transferência
    RecordingService   o servidor amostra o HRP a 10 Hz (Cidade ou Pista)
    PickupService      coletáveis (grupos por plot; "primeiro a tocar")
    EconomyService     Cash, cofre, upgrades, rebirth, offline, estado do cliente
    MonetizationService, SettingsService, CharacterService, TrapService,
    LeaderboardService, RetentionService, DebugService
src/client/            -> StarterPlayerScripts.Client
  Main.client.luau
  Controllers/  State, Sound, Notify, Hud, Shop, BaseMenu, Panels, Settings, Record,
                CloneRenderer, WorldFx, Base, Environment, CharacterAnimator
  Ui/           Theme, Builder, Root, I18n, Hooks, Components/*
tests/                 -> ServerScriptService.Tests (specs TestEZ + TestRunner do Studio)
.lune/test.luau        lune run test (mesmos specs, fora do Studio)
DevPackages/           -> ReplicatedStorage.DevPackages (TestEZ, gerado pelo wally install)
```

## Pendências / limitações (leia antes de publicar)

- **Nada da v2 foi rodado no Studio.** Aqui não há Studio. O que foi verificado: selene e stylua sem avisos, **57 testes** de lógica (TestEZ, via Lune) e `rojo build` gerando o place. Falta testar no Studio:
  - jogabilidade: pulo, trampolins, plataforma móvel e o parkour de cada bairro;
  - roubo de fitas com 2 ou mais jogadores (pegar, carregar, entregar, tapa, laser de defesa);
  - layout da UI em celulares de verdade;
  - **teste de carga com `/stress 240`** (simula 8 bases + 240 clones). O comando existe, mas o resultado (FPS, MicroProfiler) ainda precisa ser medido. Ajuste `Config.MaxRenderedClones` e `Config.CloneQualityOptions` se precisar.
- **Contagem de Parts**: estimei cerca de 2,2 mil no mapa vazio e cerca de 3,5 mil com as 8 bases no nível 6 cheias de fitas (bem abaixo de 8 mil). O número real aparece no Output. Os modelos dos clones são criados só no cliente e não entram nessa conta.
- **Música e ambiente** estão sem IDs (`TROCAR`): não achei IDs de faixas licenciadas do Roblox que desse para confirmar daqui. O sistema de áudio funciona assim que os IDs forem preenchidos.
- **Ícones** sem IDs: a UI usa emoji até você preencher `Config.Icons`.
- **Sombra 9-slice**: o prompt pedia uma ImageLabel. Sem asset, a sombra dos painéis é um Frame escuro arredondado deslocado.
- `RecoverTape` devolve uma **cópia** da fita. O ladrão continua com a dele, porque mexer no perfil de alguém que pode estar em outro servidor quebraria o lock de sessão.
- O `InstantBaseLevelN` sempre constrói o **próximo** nível. Se a base já estiver completa, devolve o valor do nível em Cash.
- Fora de escopo (não feito, de propósito): trocas, caixas pagas, vários mapas (o `MapBuilder.build(seed)` continua determinístico), pets, clãs, anúncios e idiomas além de PT/EN.
