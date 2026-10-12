# Teste 01

**Commit testado:** (a preencher)
**Objetivo:** Verificar que a migração dos testes para o TestEZ (Wally) sincroniza pelo Rojo e que o `TestRunner` roda os 57 specs ao dar Play no Studio, sem atrapalhar o jogo.
**Pré-requisitos:**
- Studio aberto com o place do projeto
- `wally install` já executado (pasta `DevPackages/` presente na raiz do repositório)
- Plugin Rojo conectado ao `rojo serve`
- Sincronização confirmada (ver passo 0)

## Passo 0: Verificação inicial
- Confirme que o plugin Rojo mostra conexão ativa.
- Confirme que o commit do repositório (HEAD) é o informado acima **ou** o commit imediatamente seguinte a ele com a mensagem `test: fixa hash em Teste-01`. Esse commit seguinte só grava o hash neste arquivo e não altera o código. Qualquer outro HEAD conta como falha.
- Se algum item falhar, pare e relate. Não execute os passos seguintes.

## Passo 1: Estrutura sincronizada no Explorer
- **Ação:** No modo Edit (sem Play), abra o Explorer e expanda `ServerScriptService > Tests` e `ReplicatedStorage > DevPackages`.
- **Esperado:** `ServerScriptService.Tests` contém o Script `TestRunner`, os ModuleScripts `Economy.spec`, `Misc.spec`, `Path.spec`, `V2.spec` e a pasta `lib` com o ModuleScript `load`. Não existem `run` nem `lib.T`. `ReplicatedStorage.DevPackages` contém o ModuleScript `TestEZ` e a pasta `_Index`.
- **Print:** `tests/prints/teste-01-passo1.png`

## Passo 2: Testes rodam ao dar Play
- **Ação:** Limpe a janela Output (botão Clear Output) e clique em **Play** (F5). Aguarde 5 segundos.
- **Esperado:** A Output mostra o bloco de resultado do TestEZ, sem nenhuma linha marcada com `[-]` entre as duas linhas abaixo.
- **Print:** `tests/prints/teste-01-passo2.png`
- **Log esperado:**
  - `Test results:`
  - `57 passed, 0 failed, 0 skipped`
  - Não deve aparecer `[Tests]` nem `test nodes reported failures` nem `Errors reported by tests:`.

## Passo 3: O jogo continua funcionando com o runner ativo
- **Ação:** Ainda em Play, observe a tela do jogo e a Output por 10 segundos.
- **Esperado:** O personagem aparece no mapa e o HUD carrega normalmente. A Output não mostra erros (texto em vermelho) vindos de `TestRunner`, `TestEZ`, `DevPackages` ou `load`.
- **Print:** `tests/prints/teste-01-passo3.png`
- **Log esperado:** nenhuma linha com `[DataService]`, `[CloneService]`, `[PlotService]` ou `[Net]` em vermelho.

## Passo 4: Runner desligado pelo atributo `Disabled` (caso de borda)
- **Ação:** Pare o Play. No Explorer, selecione `ServerScriptService > Tests > TestRunner`. Em Properties > Attributes, clique em **Add Attribute**, nome `Disabled`, tipo `boolean`, e marque o valor como `true`. Limpe a Output e clique em **Play**. Aguarde 5 segundos.
- **Esperado:** O jogo sobe normalmente e a Output **não** mostra `Test results:`.
- **Print:** `tests/prints/teste-01-passo4.png`
- **Log esperado:** ausência de `Test results:` e de `[Tests]`.

## Passo 5: Runner religado após remover o atributo
- **Ação:** Pare o Play. Em `TestRunner`, remova o atributo `Disabled` (ícone de engrenagem do atributo > Delete). Limpe a Output e clique em **Play**. Aguarde 5 segundos.
- **Esperado:** O bloco de resultado volta a aparecer, igual ao passo 2.
- **Print:** `tests/prints/teste-01-passo5.png`
- **Log esperado:**
  - `Test results:`
  - `57 passed, 0 failed, 0 skipped`

## Critérios de aprovação
- Todos os passos com resultado igual ao esperado.
