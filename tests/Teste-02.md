# Teste 02

**Commit testado:** 709c6ca22fadcde81649cbd53a1298d50e9fa867
**Objetivo:** Verificar as correções do Teste-01: o Rojo apaga as cópias duplicadas de `Tests`/`DevPackages` do place, os 57 specs rodam uma vez só, o atributo `Disabled` desliga o runner e o som `swoosh.wav` não gera mais erro.
**Pré-requisitos:**
- Studio aberto com o place do projeto (use uma única janela do Studio; se houver outra com o mesmo place, clique em Disconnect no plugin Rojo dela e não mexa mais nela)
- `wally install` já executado (pasta `DevPackages/` presente na raiz do repositório)
- `rojo serve` rodando na raiz do repositório (projeto `me-x1000`)
- Sincronização confirmada (ver passo 0)

## Passo 0: Verificação inicial
- Confirme que o plugin Rojo mostra conexão ativa com o projeto `me-x1000`.
- Confirme que o código em disco é o do commit testado. Rode na raiz do repositório:
  - `git cat-file -t 709c6ca22fadcde81649cbd53a1298d50e9fa867` → deve imprimir `commit`.
  - `git diff --stat 709c6ca22fadcde81649cbd53a1298d50e9fa867 -- . ":(exclude)tests/Teste-*.md" ":(exclude)tests/Resultados" ":(exclude)tests/prints"` → **saída vazia**.
  - O HEAD pode estar à frente do commit testado (por exemplo, o commit que adiciona este arquivo). Isso é esperado e não conta como falha, desde que o comando acima saia vazio.
  - O repositório tem `.gitattributes` com `* text=auto`, então diferenças só de quebra de linha (CRLF x LF) não aparecem mais no diff.
- Se algum item falhar, pare e relate. Não execute os passos seguintes.

## Passo 1: Rojo apaga as cópias duplicadas ao reconectar
- **Ação:** No modo Edit, no plugin Rojo clique em **Disconnect** e depois em **Connect**. Se aparecer a janela de confirmação de mudanças, leia a lista e clique em **Accept**. Depois expanda `ServerScriptService` e `ReplicatedStorage` no Explorer e salve o place (Ctrl+S).
- **Esperado:** A lista de confirmação mostra a remoção das cópias extras de `Tests` e/ou `DevPackages` (registre no resultado tudo o que ela listar para remover). Depois de aceitar, `ServerScriptService` tem **uma** pasta `Tests` e `ReplicatedStorage` tem **uma** pasta `DevPackages`. `Tests` contém `TestRunner`, `Economy.spec`, `Misc.spec`, `Path.spec`, `V2.spec` e `lib/load`; `DevPackages` contém `TestEZ` e `_Index`. As pastas `prints` e `Resultados` podem aparecer dentro de `Tests` e não contam como falha.
- **Print:** `tests/prints/teste-02-passo1.png`

## Passo 2: Testes rodam uma vez só ao dar Play
- **Ação:** Limpe a janela Output (Clear Output) e clique em **Play** (F5). Aguarde 5 segundos.
- **Esperado:** O bloco de resultado do TestEZ aparece **uma única vez**, sem `(x2)` e sem linhas marcadas com `[-]`.
- **Print:** `tests/prints/teste-02-passo2.png`
- **Log esperado:**
  - `Test results:` (uma vez)
  - `57 passed, 0 failed, 0 skipped` (uma vez, sem `(x2)`)
  - Não deve aparecer nenhuma linha começando com `[Tests]`, nem `test nodes reported failures`, nem `Errors reported by tests:`.

## Passo 3: Jogo sobe sem o erro de som
- **Ação:** Ainda em Play, observe a tela do jogo e a Output por 10 segundos. Depois feche a janela Daily Reward (se aparecer) e clique em qualquer botão do HUD que abra um painel.
- **Esperado:** O personagem aparece no mapa, o HUD carrega e o painel abre. A Output **não** mostra `Failed to load sound rbxasset://sounds/swoosh.wav`. Não há erros em vermelho vindos de `TestRunner`, `TestEZ`, `DevPackages`, `load`, `[CloneService]`, `[PlotService]` ou `[Net]`.
- **Print:** `tests/prints/teste-02-passo3.png`
- **Log esperado:** `[Me x1000] servidor pronto` presente.
- **Observação:** se o acesso do Studio às APIs estiver desligado, aparecem `DataStoreService: StudioAccessToApisNotAllowed` (vermelho) e `[DataService] ... MODO MEMÓRIA` (laranja). Isso é configuração do Studio, não falha deste teste: só registre no resultado.

## Passo 4: Runner desligado pelo atributo `Disabled` (caso de borda)
- **Ação:** Pare o Play. No Explorer, selecione `ServerScriptService > Tests > TestRunner`. Em Properties > Attributes, clique em **Add Attribute**, nome `Disabled`, tipo `boolean`, valor `true`. Limpe a Output e clique em **Play**. Aguarde 5 segundos.
- **Esperado:** O jogo sobe normalmente e a Output **não** mostra `Test results:`.
- **Print:** `tests/prints/teste-02-passo4.png`
- **Log esperado:** ausência de `Test results:` e de qualquer linha começando com `[Tests]`.

## Passo 5: Runner religado após remover o atributo
- **Ação:** Pare o Play. Em `TestRunner`, remova o atributo `Disabled` (engrenagem do atributo > Delete). Limpe a Output e clique em **Play**. Aguarde 5 segundos.
- **Esperado:** O bloco de resultado volta a aparecer **uma única vez**, igual ao passo 2.
- **Print:** `tests/prints/teste-02-passo5.png`
- **Log esperado:**
  - `Test results:`
  - `57 passed, 0 failed, 0 skipped` (sem `(x2)`)

## Critérios de aprovação
- Todos os passos com resultado igual ao esperado.
- Ao final, pare o Play e salve o place (Ctrl+S) sem o atributo `Disabled` no `TestRunner`.
