# Prompt para o Claude Code: MVP do "Me x1000"

> Copie tudo abaixo da linha e cole no Claude Code, dentro de uma pasta vazia.

---

Você vai criar o MVP de um jogo de Roblox chamado **"Me x1000"**. Trabalhe 100% em código, com **Rojo** (sincroniza arquivos `.luau` com o Roblox Studio). Construa **todos os modelos e o mapa por código** (Parts criadas em scripts de build). Assim o projeto inteiro vive em arquivos e eu só preciso abrir o Studio, conectar o Rojo e apertar Play.

## 1. Conceito (não mude)
O jogador aperta **Gravar** e tem **20 segundos** para correr, pular e coletar moedas. Ao parar, nasce um **clone com o avatar dele** que repete **exatamente** aquele trajeto em loop, para sempre, coletando moedas pelo caminho. O jogador monta um exército de cópias de si mesmo e otimiza a rota. Os clones de todos os jogadores do servidor disputam as mesmas moedas: **a moeda é do primeiro clone (ou jogador) que encostar**. Os jogadores podem jogar **cascas de banana** que derrubam clones alheios. Clone derrubado para de gerar até o dono regravar ou pagar o conserto.

O jogo segue a fórmula dos hits recentes do Roblox: loop simples, renda passiva, rebirth com multiplicador, ganho offline e compras que aceleram progresso.

## 2. Estilo visual: Roblox clássico, nostálgico, pegada Lego
- Avatares e clones em **R6** (`StarterPlayer.GameSettings`/`Workspace` configurados para R6).
- Peças **retangulares simples**: só `Part` (Block, Cylinder, Wedge), sem MeshParts, sem texturas realistas.
- Material `Plastic` / `SmoothPlastic` com **studs** no topo: use `TopSurface = Enum.SurfaceType.Studs` e `BottomSurface = Enum.SurfaceType.Inlet`. Se os studs não renderizarem, crie um `Texture` com a imagem clássica de studs (deixe o asset id em `Config.StudsTextureId`).
- Paleta de BrickColors clássicas: `Bright red`, `Bright blue`, `Bright yellow`, `Bright green`, `Dark green` (chão), `Medium stone grey`, `Black`, `Institutional white`.
- Céu: Skybox padrão clássico e iluminação `Lighting.Technology = Compatibility` ou `Voxel`, `ClockTime = 14`, sem sombras fortes, sem bloom e sem efeitos pós-processamento.
- Fonte da UI: `Enum.Font.Legacy` ou `SourceSansBold`, bordas pretas grossas e botões coloridos chapados (estilo 2010).
- Moedas: cilindro dourado (`Bright yellow`, Neon leve) girando. Gemas: wedge azul. Baú: bloco marrom com tampa.
- Banana: pequeno conjunto de Parts amarelas em formato de "C".
- Clones: avatar do jogador (`Players:GetHumanoidDescriptionFromUserId`) com leve transparência (0.2) e um `BillboardGui` mostrando o nome do dono e "#N". Clone dourado ganha `Highlight` dourado.

## 3. Estrutura do projeto
```
me-x1000/
  default.project.json          # Rojo
  aftman.toml / rokit.toml      # rojo, selene, stylua
  selene.toml, stylua.toml
  src/
    shared/                     # ReplicatedStorage.Shared
      Config.luau               # TODOS os números de balanceamento e IDs de produtos
      Types.luau
      Net.luau                  # cria/obtém RemoteEvents e RemoteFunctions
      Format.luau               # 1.2K, 3.4M etc.
    server/                     # ServerScriptService.Server
      Main.server.luau
      Build/MapBuilder.luau     # constrói o mapa em Parts
      Build/Prefabs.luau        # moeda, gema, baú, banana, pedestal de gravação
      Services/DataService.luau       # DataStore + sessão (lock, autosave, BindToClose)
      Services/RecordingService.luau
      Services/CloneService.luau
      Services/PickupService.luau     # spawn de moedas e regra "primeiro a tocar"
      Services/TrapService.luau       # bananas
      Services/EconomyService.luau    # dinheiro, multiplicadores, rebirth, offline
      Services/MonetizationService.luau
      Services/LeaderboardService.luau
    client/                     # StarterPlayerScripts.Client
      Main.client.luau
      Controllers/RecordController.luau   # botão, contagem regressiva, rastro visual
      Controllers/CloneRenderer.luau      # renderiza clones localmente
      Controllers/HudController.luau
      Controllers/ShopController.luau
      Ui/                       # UI criada por código (sem .rbxm)
  README.md                     # como rodar, onde trocar IDs, como publicar
```

## 4. Sistemas e regras

### 4.1 Gravação (RecordingService + RecordController)
- Pedestal "GRAVAR" na base de cada jogador, ou botão na HUD.
- Ao iniciar, o **servidor** amostra o `HumanoidRootPart.CFrame` do jogador a **10 Hz** por `Config.RecordSeconds` (20 s, ou 40 s com passe). Não confie em dados de gravação vindos do cliente.
- Salve também eventos discretos (pulo) para a animação.
- Mostre um rastro (Trail ou bolinhas) durante a gravação e um contador grande na tela.
- Gravação com menos de 3 s é descartada. Se o jogador morrer, a gravação é cancelada.
- Se já atingiu o limite de clones, pergunte qual substituir.

### 4.2 Clones (CloneService + CloneRenderer)
- **Desempenho é crítico** (8 jogadores × até 30 clones = 240 clones).
  - O servidor guarda só os dados: caminho comprimido, fase do loop e estado (ativo/caído).
  - O servidor **simula** a posição de cada clone pelo tempo (`(os.clock() - startTime) % duration`) e interpola entre as amostras. Não cria Humanoid físico no servidor.
  - Os **clientes renderizam** os clones: modelo R6 ancorado, CFrame interpolado a cada frame, animação de corrida simples.
  - Os modelos ficam em cache e são reaproveitados por `HumanoidDescription`.
  - Renderizar no máximo `Config.MaxRenderedClones` (ex.: 120) por cliente, priorizando os mais próximos. Os outros viram "fantasmas" de baixo detalhe (um bloco com a cor da camisa).
- Coleta pelo clone: o servidor checa a cada `0.1 s` a distância da posição simulada às moedas ativas (spatial hash por célula de 8 studs).
- Clone fica "caído" (deitado, cinza, ícone ⚠️) ao passar por uma banana.
- Ao sair do servidor, os clones somem do mundo, mas o jogador ganha **renda offline** (seção 4.5).

### 4.3 Moedas e coleta (PickupService)
- Pontos de spawn fixos definidos no MapBuilder (100 a 200 pontos), com respawn a cada `Config.CoinRespawn` (ex.: 4 s).
- Tipos: Moeda (1), Gema (10, rara, respawn 30 s), Baú (100, um por mapa, respawn 120 s, em lugar difícil de alcançar).
- **Regra principal:** o primeiro clone ou jogador a tocar leva. O valor é multiplicado pelo multiplicador do dono.
- Mostre um popup "+12" acima de quem coletou, com a cor do dono.

### 4.4 Bananas (TrapService)
- Cada jogador ganha 3 bananas grátis a cada 10 min (máx. 3 no estoque). Mais bananas só comprando.
- Coloca na frente de onde está olhando. A banana dura 60 s ou até derrubar 1 clone.
- Não afeta os clones do próprio jogador nem clones com Escudo ativo.
- Clone caído: o dono vê aviso na HUD com o botão "Consertar todos (29 R$)" ou pode regravar de graça.

### 4.5 Economia (EconomyService)
- `Cash` (moeda principal), `Rebirths`, `Multiplier = 1 + Rebirths * 0.5` (× passes).
- Loja in-game (paga em Cash): +1 slot de clone (preço exponencial), +2 s de gravação (até o teto), velocidade de corrida +1 (até 5 níveis).
- Começo: 3 slots, 20 s de gravação.
- **Rebirth:** exige `Config.RebirthCost(n)`. Zera Cash, slots comprados e clones; dá multiplicador e +1 slot base permanente.
- **Renda offline:** ao entrar de novo, credite `média de ganho por minuto dos clones na última sessão × minutos offline`, com teto de 8 h (24 h com passe) e 50% de eficiência. Mostre uma tela "Enquanto você estava fora, seus clones ganharam X" com botão "Dobrar (49 R$)".
- Todos os números ficam em `Config.luau`, com comentários.

### 4.6 Dados (DataService)
- DataStore com session locking. Pode usar ProfileStore (via Wally) ou implementar `UpdateAsync` com lock. Autosave a cada 60 s e no `BindToClose`.
- Salvar: Cash, Rebirths, slots, upgrades, gravações dos clones (comprimidas: posições quantizadas em int16 relativas à origem da gravação e delta encoding, string via `buffer`), cosméticos, recibos processados (`PurchaseHistory`), último login e ganho/min.
- Respeitar o limite de 4 MB por chave. Limitar o número de amostras.

### 4.7 Monetização (MonetizationService)
Todos os IDs ficam em `Config.Products` e `Config.GamePasses` com valor `0` e comentário "TROCAR". O jogo funciona com IDs zerados (a loja mostra "em breve").

Passes (GamePass):
| Chave | Efeito | Preço sugerido |
|---|---|---|
| ExtraSlots | +5 slots de clone | 299 |
| LongRecord | Gravação 20 s → 40 s | 399 |
| DoubleCash | 2x Cash | 399 |
| GoldenClone | 1 clone rende 3x e brilha | 249 |
| VIP | Tag [VIP] no chat, porta VIP no mapa com moedas extras | 299 |
| OfflinePlus | Teto offline 8 h → 24 h | 199 |

Produtos (DeveloperProduct, consumíveis):
| Chave | Efeito | Preço sugerido |
|---|---|---|
| FixAllClones | Levanta todos os clones caídos | 29 |
| Shield30 | Escudo anti-banana 30 min | 49 |
| CoinRain | 5 min de moedas 3x mais frequentes **para o servidor todo**, com anúncio "🌧️ {Nome} fez chover moedas!" | 99 |
| BananaPack10 | +10 bananas | 25 |
| DoubleOffline | Dobra o ganho offline da tela de retorno | 49 |
| CashPackS/M/L | Cash instantâneo proporcional ao rebirth atual | 49 / 149 / 399 |

Regras técnicas obrigatórias:
- `MarketplaceService.ProcessReceipt` idempotente, com o `PurchaseId` salvo no perfil antes de retornar `PurchaseGranted`.
- Passes checados com `UserOwnsGamePassAsync` (com cache) e `PromptGamePassPurchaseFinished` para aplicar na hora.
- **Sem itens aleatórios pagos no MVP**, para evitar a obrigação de exibir chances e as checagens do `PolicyService`. Deixe um TODO documentado para um futuro sistema de caixas que siga a política de "Paid Random Items" do Roblox.
- Botões de compra visíveis: HUD lateral com "Loja", aviso contextual quando um clone cai ("Consertar") e oferta na tela de retorno offline.

### 4.8 Mapa (MapBuilder)
- Um mapa de **obby/parkour aberto** em blocos estilo Lego, cerca de 300×300 studs:
  - Centro: praça com 8 bases (uma por jogador, com o nome e a cor do dono), pedestal GRAVAR e placa de ranking.
  - Em volta: plataformas em níveis, escadas de blocos, pontes estreitas, esteiras (`AssemblyLinearVelocity` em Part ancorada), trampolins e uma torre com o baú no topo.
  - Moedas espalhadas de modo que **rotas diferentes tenham valores diferentes** (rota fácil = pouco, rota difícil = muito). Isso dá o puzzle de otimização.
  - Área VIP atrás de uma porta (só passa quem tem o passe).
- Função `MapBuilder.build(seed)` determinística, para gerar mapas novos semanais depois.

### 4.9 UI (tudo por código)
- HUD: Cash (grande, topo), clones ativos/slots, multiplicador, bananas, botão GRAVAR enorme no canto inferior direito (mobile first).
- Loja com abas Upgrades (Cash), Passes e Produtos.
- Painel de Rebirth com a recompensa clara.
- Leaderboard (`leaderstats`): Cash e Rebirths.
- Notificações em toast no topo (compras de servidor, rebirths dos outros).
- Funcionar bem em **celular** (botões ≥ 60 px, `UIScale` por tamanho de tela).

### 4.10 Retenção extra (simples no MVP)
- Recompensa diária (dia 1 a 7 crescente, reseta se perder um dia).
- Recompensa por entrar no grupo do Roblox (`Config.GroupId`, checado com `IsInGroup`): +3 bananas e 1 escudo.
- Códigos (`Config.Codes`, tabela de código → recompensa, com uso único por jogador).

## 5. Segurança
- O servidor é a autoridade em tudo: coleta, dinheiro, gravação e compras.
- Valide RemoteEvents (tipos e rate limit).
- Rejeite amostras de gravação com teleporte (distância > velocidade máxima × dt × 1,5): marca a gravação como inválida.

## 6. Entregáveis e ordem de trabalho
1. Projeto Rojo rodando com o mapa gerado e um jogador andando em R6.
2. Gravação + 1 clone repetindo o caminho (é o coração do jogo; teste bem).
3. Moedas, coleta e "primeiro a tocar".
4. Vários clones, desempenho (testar com 240 clones simulados, comando de debug `/spawnclones 240`).
5. Economia, loja de upgrades e rebirth.
6. DataStore e renda offline.
7. Bananas e conserto.
8. Monetização (passes e produtos com IDs placeholder).
9. UI final, mobile, recompensa diária, códigos e grupo.
10. `README.md` em português: instalar Rokit/Aftman, `rojo serve`, conectar no Studio, ativar "Enable Studio Access to API Services" para DataStore, onde criar passes e produtos e colar os IDs, e como publicar.

Ao final de cada etapa, rode `selene` e `stylua --check`. Escreva testes de lógica pura (compressão de caminho, cálculo de economia, interpolação) com TestEZ ou um runner simples em Luau. Não peça confirmação entre as etapas: siga a ordem até o fim e liste no README o que ficou pendente.

## 7. Fora do MVP (não fazer agora)
Trocas entre jogadores, caixas aleatórias pagas, vários mapas, pets, clãs, anúncios patrocinados e localização além de PT/EN (deixe as strings em `Shared/Strings.luau` com PT e EN).
