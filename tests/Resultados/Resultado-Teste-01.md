# Resultado — Teste 01

**Data:** 2026-10-12
**Commit testado:** `5fbe33f24a25ce068647abfe4c38a24b4779a88b`
**HEAD do repositório:** `e4f2d0ee14c2e1635230262f340f0b3d4a0018e9` (branch `main`, à frente do commit testado: adiciona o Teste-01)
**Ambiente:** Roblox Studio + Rojo 7.7.1 (`rojo serve`, projeto `me-x1000`, localhost:34872), TestEZ via Wally (`DevPackages/`)

## Resumo

| Passo | Descrição | Status |
|---|---|---|
| 0 | Verificação inicial | ✅ PASSOU |
| 1 | Estrutura sincronizada no Explorer | ⚠️ PASSOU com ressalva (pastas `Tests` e `DevPackages` duplicadas no place) |
| 2 | Testes rodam ao dar Play | ⚠️ PASSOU com ressalva (bloco de resultado aparece 2x) |
| 3 | Jogo continua funcionando com o runner ativo | ✅ PASSOU (com avisos de ambiente, ver abaixo) |
| 4 | Runner desligado pelo atributo `Disabled` | ❌ FALHOU como escrito (diagnóstico confirma a causa) |
| 5 | Runner religado após remover o atributo | ⚠️ PASSOU com ressalva (bloco 2x, igual ao Passo 2) |

**Causa raiz do que falhou/ficou com ressalva:** o place salvo no Studio contém **duas cópias** de `ServerScriptService.Tests` (e de `ReplicatedStorage.DevPackages`). Existem, portanto, dois `TestRunner`. Os 57 testes rodam duas vezes e desligar só um `TestRunner` com `Disabled` não basta. Isso parece já existir no place salvo (o diff do Rojo na primeira conexão só mostrou a remoção de `SprintController`). Nada foi apagado do place.

## Passo 0: Verificação inicial — ✅ PASSOU

- Rojo conectado ao projeto `me-x1000`. ✅
- `git cat-file -t 5fbe33f24a25ce068647abfe4c38a24b4779a88b` → `commit`. ✅
- `git diff --stat 5fbe33f… -- . ":(exclude)tests/Teste-*.md" ":(exclude)tests/Resultados" ":(exclude)tests/prints"` → **saída vazia**. ✅
- HEAD à frente do commit testado (`e4f2d0e`, `5fbe33f` → `e4f2d0e`), previsto no roteiro.
- Observação: não há terminal controlável nesta sessão, então os comandos git foram executados em uma cópia do repositório copiada para o ambiente de teste. Com a conversão de quebra de linha do Windows (CRLF vs. LF), o diff cru mostra 86 arquivos de ruído; com `-c core.autocrlf=true` e com `--ignore-cr-at-eol` a saída fica vazia.
- `rojo serve` já estava rodando e `DevPackages/` já existia, então nenhum pré-requisito precisou ser executado.

## Passo 1: Estrutura no Explorer — ⚠️ PASSOU com ressalva

Print: `tests/prints/teste-01-passo1.png`

- `ServerScriptService.Tests` contém `TestRunner`, `Economy.spec`, `Misc.spec`, `Path.spec`, `V2.spec`, a pasta `lib` com `load` e a pasta `Resultados`. Não existem `run` nem `lib.T`. ✅
- `ReplicatedStorage.DevPackages` contém `TestEZ` e `_Index`. ✅
- **Ressalva:** `Tests` aparece **duas vezes** em `ServerScriptService` e `DevPackages` aparece **duas vezes** em `ReplicatedStorage`. Cada cópia tem a estrutura esperada. Pelo critério estrito "igual ao esperado", este passo pode ser considerado falha.

## Passo 2: Testes rodam ao dar Play — ⚠️ PASSOU com ressalva

Print: `tests/prints/teste-01-passo2.png`

Linhas relevantes da Output:

```
Test results:
57 passed, 0 failed, 0 skipped (x2)  -  Server - TextReporterQuiet:78
Test results:
57 passed, 0 failed, 0 skipped
```

- `Test results:` e `57 passed, 0 failed, 0 skipped` presentes. ✅
- Sem `[Tests]`, sem `test nodes reported failures`, sem `Errors reported by tests:`. ✅
- **Ressalva:** o bloco aparece duas vezes (dois `TestRunner`).

## Passo 3: Jogo continua funcionando — ✅ PASSOU

Print: `tests/prints/teste-01-passo3.png`

- Personagem no mapa e HUD carregados (Cash, Tapes, Vault, Bananas, Door, botão RECORD, janela Daily Reward). ✅
- Nenhum erro vermelho vindo de `TestRunner`, `TestEZ`, `DevPackages` ou `load`. ✅
- Nenhuma linha vermelha com `[CloneService]`, `[PlotService]` ou `[Net]`. ✅
- Linha `[DataService]` aparece em **laranja (warn)**, não vermelha. Está ligada à configuração do Studio, não ao runner (ver Avisos de ambiente).

Linhas da Output:

```
DataStoreService: StudioAccessToApisNotAllowed: Studio access to APIs is not allowed. API: GetAsync, Data Store: MeX1000_PlayerData_v1  -  Studio   (vermelho)
[DataService] DataStore indisponivel (502: API Services rejected request with error. Error code: 7 Reason: Studio access to APIs is not allowed.). Rodando em MODO MEMÓRIA: nada será salvo. No Studio, ative Game Settings > Security > Enable Studio Access to API Services.   (laranja)
[PickupService] 148 coletáveis na Cidade
[Me x1000] servidor pronto: mapa seed 1, 148 coletáveis na Cidade, 1775 Parts
Failed to load sound rbxasset://sounds/swoosh.wav: Asset is not approved for the requester (x4)   (vermelho)
```

Por uma leitura estrita ("nenhuma linha com `[DataService]` em vermelho"), o erro vermelho `DataStoreService: StudioAccessToApisNotAllowed` é a causa do aviso `[DataService]` laranja; a linha com a tag `[DataService]` em si é laranja.

## Passo 4: Runner desligado pelo atributo `Disabled` — ❌ FALHOU como escrito

Print: `tests/prints/teste-01-passo4.png`

Ação feita: atributo `Disabled` (boolean, `true`) adicionado ao `TestRunner` da primeira pasta `Tests`. Output limpa, Play, 5 s.

```
Test results:
57 passed, 0 failed, 0 skipped  -  Server - TextReporterQuiet:78
```

- Esperado: sem `Test results:`. Obtido: `Test results:` apareceu **uma vez** (o segundo `TestRunner`, que não tem o atributo, rodou). ❌
- Sem `[Tests]`. ✅
- O jogo subiu normalmente. ✅

**Diagnóstico:** `Disabled` também aplicado ao `TestRunner` da segunda pasta `Tests` (print `tests/prints/teste-01-passo4-diagnostico-2-runners-desativados.png`). Com os dois desativados, a Output **não** mostra `Test results:` nem `[Tests]`, e o jogo sobe normalmente. O mecanismo do atributo funciona; o que falha é a duplicação de `Tests` no place.

## Passo 5: Runner religado após remover o atributo — ⚠️ PASSOU com ressalva

Print: `tests/prints/teste-01-passo5.png`

Atributo `Disabled` removido (gear > Delete) dos **dois** `TestRunner` (o roteiro cita apenas um). Output limpa, Play, 5 s.

```
Test results:
57 passed, 0 failed, 0 skipped (x2)  -  Server - TextReporterQuiet:78
```

- `Test results:` e `57 passed, 0 failed, 0 skipped` de volta, igual ao Passo 2. ✅
- Ressalva: bloco duplicado, como no Passo 2.

## Avisos de ambiente (não são falhas do teste)

- **DataStore bloqueado no Studio:** `StudioAccessToApisNotAllowed` + `[DataService] ... MODO MEMÓRIA: nada será salvo`. Correção: Game Settings > Security > Enable Studio Access to API Services.
- **Som bloqueado:** `Failed to load sound rbxasset://sounds/swoosh.wav: Asset is not approved for the requester (x4)` em todas as execuções.
- **Rojo:** na primeira conexão, o aviso de sincronização queria **remover `SprintController`** do place, embora o arquivo exista em disco (aceito para sincronizar). Ao parar o Play, o Rojo mostrou de novo o convite "Would you like to connect?" (desconexão do Play, sem impacto nos passos).

## Estado final

- Place sem o atributo `Disabled` em nenhum `TestRunner` (estado original). Nada foi salvo no place.
- Nenhum arquivo de código foi alterado. Nenhum commit foi feito.
- Prints em `tests/prints/`: `teste-01-passo1.png`, `teste-01-passo2.png`, `teste-01-passo3.png`, `teste-01-passo4.png`, `teste-01-passo4-diagnostico-2-runners-desativados.png`, `teste-01-passo5.png`.
