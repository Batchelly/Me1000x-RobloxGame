# Prompt para o Claude Code: melhorias do "Me x1000" (v2)

> Abra o Claude Code **na pasta do projeto do MVP** que já existe e cole tudo abaixo da linha.

---

Este projeto é o MVP do jogo de Roblox **"Me x1000"** (Rojo, Luau, tudo gerado por código). Primeiro **leia o projeto inteiro** (`src/`, `Config.luau` e `README.md`) para entender o que já existe. Depois implemente a versão 2 descrita abaixo. **Reaproveite** os serviços existentes (gravação, clones, economia, DataStore, monetização) e refatore só o necessário. Não reescreva do zero.

## 0. Problemas da versão atual (resultado do teste)
- As 8 bases ficam todas juntas numa praça no centro. O jogador não tem um espaço próprio.
- O mapa é um baseplate cinza xadrez enorme e vazio, com alguns obstáculos soltos. Parece "seco" e inacabado.
- A HUD é funcional, mas parece antiga: botões quadrados chapados, sem animação, sem hierarquia visual.
- Não há música nem som ambiente.

## 1. Novo layout do mapa: bases de tycoon nas bordas + mapa central compartilhado
- **8 terrenos de tycoon (plots)** em anel nas **bordas** do mapa, cada um com cerca de 70×70 studs, separados por cercas, árvores e caminhos.
- Cada jogador **nasce na própria base** (`SpawnLocation` dentro do plot, atribuído na entrada). O plot mostra uma placa grande com o nome, o avatar (headshot) e a cor do dono.
- **Centro: "Cidade de Blocos"**, o mapa compartilhado onde todos disputam moedas (o que já existe, refeito com mais detalhe, seção 3).
- Caminhos de tijolo ligam cada base ao centro. Teleporte rápido "Ir para Base" / "Ir para Cidade" na HUD.
- `MapBuilder` passa a ter módulos separados: `PlotBuilder`, `CityBuilder`, `DecorBuilder` e `LightingSetup`.

## 2. Base do jogador (tycoon com upgrade)
### 2.1 Estrutura e níveis
A base evolui em **níveis 1 a 6**, comprados com Cash (preço em `Config.BaseLevels`). Cada nível **constrói peças novas com animação** (os blocos caem do céu e encaixam, estilo Lego, com som de "clique").

| Nível | O que aparece |
|---|---|
| 1 | Chão de studs, portão com porta laser, estante com 3 slots de "Fita", Pista de Gravação curta, Cofre |
| 2 | Muro baixo, +2 slots, pista ganha rampa e esteira |
| 3 | Segundo andar (escada), +3 slots, trampolim na pista, upgrade do Cofre |
| 4 | Torre de vigia, +3 slots, pista com plataforma móvel e moedas de gema |
| 5 | Telhado, +4 slots, laser de defesa automático (seção 2.3) |
| 6 | Base "dourada" (detalhes Neon dourados), +5 slots, pista completa com baú próprio |

Os botões de compra do tycoon ficam **no chão da base** (botões redondos com preço, estilo tycoon clássico) e também no menu.

### 2.2 Gravar na própria base
- Dentro da base existe a **Pista de Gravação**, um circuito particular com moedas que **só os clones do dono** coletam. A renda é menor que na Cidade, mas é segura de banana.
- O jogador pode gravar **na Pista da base** ou **na Cidade**. O clone fica atrelado ao lugar onde foi gravado.
- **Todo clone vira uma "Fita"** (um cartucho VHS de blocos com a cor e o nome do clone) exposta na **estante** da base. A fita é o item físico que representa o clone.
- O dinheiro que os clones geram (da Pista e da Cidade) cai no **Cofre** da base, que tem limite de capacidade (upgrade aumenta). O jogador precisa **ir até o Cofre e encostar** para coletar. Isso traz o jogador de volta à base.

### 2.3 Roubo e defesa (inspirado no Steal a Brainrot)
**Como roubar**
- Outros jogadores podem entrar em qualquer base **quando a porta laser está aberta**.
- Podem fazer duas coisas:
  1. **Pegar uma Fita** da estante. O ladrão carrega a fita nas costas (fica mais lento: −30% de velocidade) e precisa levá-la até a estante **da própria base**. Se conseguir, o clone passa para ele com o caminho original e começa a rodar na base do ladrão.
  2. **Pegar 25% do Cofre** encostando nele. Uma vez por base a cada 2 minutos.
- Quando alguém invade, o dono recebe um **alerta** (toast vermelho, som de sirene curto, seta na tela apontando para a base).

**Como se defender**
- **Porta laser (grátis):** botão "TRANCAR" dentro da base. Fecha a entrada por **60 s** e depois entra em recarga de **60 s** (os tempos ficam no Config). Upgrade de base aumenta o tempo trancado. Contador visível em cima do portão para todo mundo ver.
- **Tapa:** o dono e qualquer jogador podem acertar o ladrão com o item padrão (luva/bastão de blocos). O ladrão derrubado **solta a fita**, que volta voando para a estante.
- **Laser de defesa (nível 5):** dispara em invasores parados na base por mais de 3 s e os empurra para fora.
- **Proteção de novato:** nos primeiros 10 minutos de cada sessão a base fica protegida e não pode ser invadida.
- **Fitas Douradas** (passe GoldenClone) não podem ser roubadas.
- Escudo pago (seção 6) tranca a base por mais tempo.

**Regras técnicas**
- Tudo validado no servidor: distância para pegar, tempo de carregamento, chegada na base.
- Se o ladrão sair do jogo carregando a fita, ela volta para o dono.
- Salve o roubo na hora (DataStore dos dois jogadores, com lock de sessão) para não duplicar nem perder clones.
- Limite: no máximo 1 fita roubada por base a cada 3 minutos, para não frustrar demais.

## 3. Mapa mais completo e detalhado (fim do "seco")
Mantenha a estética **Roblox clássico + Lego** (blocos, studs, cores BrickColor), mas com **densidade e vida**:
- **Chão:** substitua o baseplate xadrez por placas de grama verde com studs, ruas cinza-escuro com faixa amarela, calçadas claras e praças de tijolo. **Nenhuma área grande vazia.**
- **Cidade de Blocos (centro), com 4 bairros temáticos** e rotas de valor diferente:
  1. **Praça Central:** fonte com água (Part azul translúcida + partículas), bancos, postes de luz, canteiros de flores, coreto, placa de ranking.
  2. **Parque:** lago com ponte, árvores de blocos de 3 tamanhos, playground (escorregador, balanço), trilha com pedras de pular.
  3. **Canteiro de Obras:** guindaste, andaimes, vigas, esteiras, cones e caixas. É a rota de parkour difícil, com mais gemas.
  4. **Castelo de Blocos:** muralhas, torre com o **Baú** no topo, ponte levadiça, bandeiras com as cores das bases.
- **Bordas:** montanhas de blocos em degraus e uma linha de árvores para fechar o horizonte. Nada de "fim do mundo" visível.
- **Detalhes espalhados:** nuvens de blocos brancos flutuando devagar, pássaros simples voando em loop, carrinhos de blocos estacionados, hidrantes, lixeiras, caixas de correio, placas com setas para os bairros.
- **Iluminação:** `Lighting.Technology = Future` (ou `ShadowMap` como fallback de desempenho), `Atmosphere` leve, `ColorCorrection` levemente quente, `SunRays` sutil e **ciclo dia/noite** de 12 min (à noite os postes e as moedas brilham mais).
- **Desempenho:** use `StreamingEnabled`, agrupe a decoração em Models com `ModelStreamingMode = Atomic`, `CastShadow = false` em peças pequenas e no máximo cerca de 8 mil Parts no total. Gere as peças repetidas a partir de prefabs em `Build/Prefabs`.

## 4. Menu e HUD modernos (com capricho)
Refaça toda a UI com um **design system** próprio em `client/Ui/Theme.luau` e componentes reutilizáveis em `client/Ui/Components/` (Button, IconButton, Panel, Tab, Card, ProgressRing, Toast, Modal, Counter).

**Visual**
- Fonte `BuilderSans` via `Font.new("rbxasset://fonts/families/BuilderSans.json")` (Bold para títulos, Medium para texto). Fallback: `GothamSSm`.
- Cantos arredondados (`UICorner` 12–20 px), `UIStroke` fino semitransparente e `UIGradient` suave nos botões principais.
- Painéis em **vidro escuro**: fundo `#151A2B` com 15% de transparência, sombra suave (ImageLabel com 9-slice) e borda clara.
- Paleta: primária azul-violeta `#5B6CFF`, sucesso verde `#2ED47A`, aviso amarelo `#FFC83D`, perigo vermelho `#FF4D5E`, texto `#FFFFFF` / `#A9B1D6`. Cores de destaque vibrantes, combinando com o mundo Lego.
- Ícones: use `ImageLabel` com IDs em `Config.Icons` (escolher ícones gratuitos da Creator Store). Enquanto não houver ID, use emoji como fallback.

**Layout**
- **Topo central:** pílula com Cash (contador com animação de contagem) e o multiplicador ao lado como chip.
- **Esquerda:** barra vertical compacta só com ícones (Loja, Base, Clones, Rebirth, Diário, Códigos, Config), com tooltip ao passar o mouse e badge de notificação (ex.: "!" quando a recompensa diária está disponível).
- **Direita:** cartões pequenos com Clones x/y, Cofre (barra de capacidade), Bananas e status da porta (🔒 0:42).
- **Inferior direito:** botão **GRAVAR circular** grande com anel de progresso dos 20 s, pulsando de leve quando parado. Ao lado, botões menores: Banana, Tapa e Trancar (este só aparece dentro da própria base).
- **Menus (Loja, Base, Clones, Rebirth):** modal central com abas, cards em grade (ícone, nome, descrição curta, preço em botão) e destaque "MAIS POPULAR" num item de cada aba. O fundo do jogo ganha `BlurEffect` (tamanho 12) com tween.
- **Tela de Clones:** lista de fitas com mini-mapa do trajeto, quanto cada uma rende por minuto e botões Regravar e Excluir.

**Movimento e conforto**
- Toda abertura e fechamento com `TweenService` (escala 0,92→1 e transparência, 0,18 s, `Quint Out`). Hover com leve aumento (1,04) e press com leve redução (0,96).
- Som de clique suave em botões, som de "moeda" no ganho e confete no rebirth.
- **Mobile first:** área segura (`ScreenInsets = DeviceSafeInsets`), botões de toque ≥ 64 px, `UIScale` automático por tamanho de tela, e nada sobreposto ao joystick.
- Toasts empilhados no topo com ícone e cor por tipo. Somem sozinhos em 3 s.
- Menu **Configurações:** volume de música, volume de efeitos, qualidade dos clones (mostrar até 30/60/120), e ligar/desligar alertas. Salvo no perfil.

## 5. Música e som ambiente
- `SoundService` com `SoundGroup`s **Music**, **Ambient** e **SFX**, cada um com volume controlado pelo menu.
- **Música:** playlist de 3 a 5 faixas tranquilas e alegres (estilo lo-fi / chiptune leve / "Roblox clássico"), em ordem aleatória, com **crossfade** de 2 s entre faixas. IDs em `Config.Music.Tracks`. Escolha faixas da **biblioteca de música licenciada do Roblox na Creator Store** (as de autoria "Roblox"/APM, liberadas para qualquer experiência). Deixe comentário "TROCAR" se não tiver certeza do ID.
- **Por zona:** na própria base, uma faixa mais calma. Na Cidade, a playlist principal. Durante a Chuva de Moedas, uma faixa mais animada temporária. Transições com fade.
- **Ambiente:** som de pássaros e vento de dia, grilos à noite, água perto da fonte e do lago (`Sound` 3D com `RollOffMaxDistance`).
- **SFX:** moeda, clique de bloco Lego ao construir upgrade, sirene curta de invasão, laser da porta, tapa, rebirth.
- A música começa com fade-in depois que o jogo carrega, nunca alta de repente. Volume padrão: música 0,35, efeitos 0,6.

## 6. Monetização (ajustes para o novo sistema)
Mantenha tudo o que existe e adicione:
| Tipo | Chave | Efeito | Preço sugerido |
|---|---|---|---|
| Produto | LockBase5 | Tranca a base por 5 min (ignora a recarga) | 39 |
| Produto | LockBase30 | Tranca a base por 30 min | 129 |
| Produto | RecoverTape | Recupera na hora a última fita roubada | 49 |
| Produto | InstantBaseLevel | Constrói o próximo nível da base na hora | 99–499 (escala) |
| Passe | AutoCollect | O Cofre deposita sozinho (não precisa encostar) | 249 |
| Passe | BigVault | Cofre com capacidade 3x | 199 |
| Passe | FastThief | Carrega fita roubada sem perder velocidade | 299 |

- Ofertas contextuais: quando o alerta de invasão disparar, mostre "Trancar agora (39 R$)". Quando uma fita for roubada, mostre "Recuperar (49 R$)".
- Mantenha o `ProcessReceipt` idempotente e todos os IDs em `Config` com "TROCAR".

## 7. Ordem de trabalho
1. Ler o projeto e escrever um resumo curto do que existe em `docs/ESTADO_ATUAL.md`.
2. Layout novo: plots nas bordas, spawn na base, caminhos e teleporte.
3. Base com níveis, animação de construção e Pista de Gravação.
4. Fitas na estante, Cofre e coleta.
5. Roubo, porta laser, tapa, alertas, proteção de novato e laser de defesa.
6. Cidade de Blocos detalhada, bordas, decoração, iluminação e ciclo dia/noite.
7. Design system e refação completa da HUD e dos menus.
8. Música, ambiente e SFX, com o menu Configurações.
9. Novos produtos e passes, com as ofertas contextuais.
10. Teste de desempenho com 8 jogadores simulados e 240 clones. Rodar `selene` e `stylua`, depois atualizar o `README.md` (em português) com o que mudou, os novos IDs para trocar e o que ficou pendente.

Não peça confirmação entre as etapas. Siga até o fim. Mantenha todos os números de balanceamento em `Config.luau`, com comentários.
