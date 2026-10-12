# Estado atual (antes da v2)

Resumo do MVP v1 do "Me x1000", escrito antes das melhorias da v2.

## O que existe
- **Rojo + Rokit** (`rojo`, `selene`, `stylua`, `lune`). Tudo é gerado por código, sem `.rbxm`.
- **Mapa** (`Build/MapBuilder` + `Build/Prefabs`): baseplate verde de 300×300, praça cinza no centro com as **8 bases juntas**, um anel de moedas, uma escadaria ao norte, plataformas flutuantes a leste, pontes ao sul, uma ilha com trampolins, uma torre com baú e uma sala VIP. Cerca de 180 coletáveis.
- **Personagem R6 por código** (`CharacterService`): `CharacterAutoLoads = false` e `CreateHumanoidModelFromDescription(desc, R6)`.
- **Gravação** (`RecordingService`): o servidor amostra o HRP a 10 Hz, com anti-teleporte, mínimo de 3 s e cancelamento ao morrer.
- **Caminho comprimido** (`Shared/Path`): int16 + delta, 8 bytes por amostra, Base64 no DataStore.
- **Clones** (`CloneService` + `CloneRenderer`): no servidor são só dados; a posição sai de `(Clock.now() - startTime) % duração`. O cliente renderiza com LOD (120 modelos R6 + fantasmas), `BulkMoveTo` e pool de modelos.
- **Coleta** (`PickupService`): spatial hash, regra "primeiro a tocar", popups "+N".
- **Bananas** (`TrapService`): derrubam clones alheios; escudo; conserto pago.
- **Economia** (`EconomyService`): Cash, multiplicador por rebirth, upgrades (Slot/Tempo/Velocidade), rebirth e renda offline.
- **DataStore** (`DataService`): lock de sessão próprio via `UpdateAsync`, autosave e `BindToClose`.
- **Monetização**: 6 passes e 8 produtos com IDs 0 ("em breve"); `ProcessReceipt` idempotente.
- **Retenção**: recompensa diária, recompensa de grupo, códigos.
- **UI**: estilo 2010 (botões chapados com borda preta), HUD, loja com abas e painéis modais.
- **Testes**: 35 testes de lógica pura no Lune.

## Problemas apontados no teste
1. As 8 bases ficam juntas na praça: o jogador não tem um espaço próprio.
2. Mapa vazio e "seco".
3. HUD com cara de antiga, sem animação nem hierarquia.
4. Sem música ou som.

## O que a v2 reaproveita
Gravação, compressão de caminho, simulação e renderização dos clones, coleta, bananas, DataStore, monetização, retenção, Net (rate limit) e testes.
A v2 troca o mapa (plots + Cidade de Blocos), adiciona base de tycoon/cofre/fitas/roubo, refaz a UI com um design system e adiciona áudio.
