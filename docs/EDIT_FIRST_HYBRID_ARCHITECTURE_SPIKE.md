# CartoRig — primeiro experimento executável Fusion + OpenFX (Edit-first)

**Estado:** implementação de prova arquitetural; validação no Resolve Studio 20 real **PENDENTE**. Não é ainda um editor de mapas para usuário final.
**Branch:** `feat/edit-first-hybrid-poc` (derivada da branch de Natural Earth, sem alterar o motor C++).

## Decisão que este experimento testa

A hipótese crítica da arquitetura é que o **mesmo CartoRig Map (Edit) OpenFX inserido na timeline** pode possuir uma Fusion Composition que receba os pixels do mapa como `MediaIn`, componha dois objetos editáveis com curvas próprias e emita tudo via `MediaOut`, conservando o estado após salvar/reabrir o projeto.

É importante evitar a conclusão prematura de que `TimelineItem.AddFusionComp()` funciona em um **OFX Generator**. O método está documentado para itens da timeline, mas a compatibilidade exata com esse tipo de gerador deve ser medida no host. O experimento bloqueia explicitamente em caso de incompatibilidade.

### O que foi implementado

- `tools/cartorig_fusion_spike.py`: ponte de diagnóstico usando API pública DaVinci Resolve/Fusion, sem pacotes Python externos.
- `inspect`: valida Resolve 20 e gera SHA256 do binário OpenFX instalado, sem editar projetos.
- `prepare`: com consentimento explícito, cria exclusivamente um novo projeto `CartoRig_Fusion_Architecture_QA` e uma timeline 1080p; insere o gerador CartoRig, tenta anexar Fusion e conectar `MediaIn → Merge BRA → Merge VEN → MediaOut`.
- Cada merge recebe um modificador `BezierSpline` próprio no parâmetro `Blend`: BRA nos frames 0–12, VEN nos frames 24–36.
- `verify`: recarrega o projeto separado e busca os quatro nós nomeados, consultando Blend no frame 18 (BRA visível, VEN oculto) e no frame 40 (ambos visíveis).
- `tests/test_fusion_spike.py`: testes simulados para estrutura, isolamento, nome de projeto, animação independente, incompatibilidades e relatório `BLOCKED`.
- CI Windows/Ubuntu executa esses contratos. **Testes simulados não são aceitação do Resolve real.**

**BRA/VEN são rótulos diagnósticos Text+**, não os polígonos geográficos; **nenhum georreferenciamento dos objetos é alegado**. A prova também não certifica Viewer/Deliver, gestão de camadas nem edição de keyframes pela UI.

## Como executar no Resolve real (teste de engenharia, não instalação do produto)

Pré-requisitos: Windows, DaVinci Resolve Studio 20 aberto, CartoRig OpenFX previamente instalado. A instalação do pacote completo Natural Earth **não é necessária**. O script requer apenas Python já disponível no ambiente de desenvolvimento e a API de scripting local do Resolve.

**Salve seu projeto atual antes de começar.** O comando `prepare` troca para um novo projeto. Ele recusa nome fora de `CartoRig_Fusion_*` e recusa substituir qualquer projeto existente. Se houver falha, o projeto QA pode ficar parcialmente criado: remova-o no Project Manager após revisar o resultado.

Executar a partir da raiz da branch exata:

```powershell
python -m tools.cartorig_fusion_spike --mode inspect --report "$env:TEMP\cartorig-hybrid-inspect.json"
python -m tools.cartorig_fusion_spike --mode prepare --allow-switch-project --report "$env:TEMP\cartorig-hybrid-prepare.json"
python -m tools.cartorig_fusion_spike --mode verify --report "$env:TEMP\cartorig-hybrid-verify.json"
```

Se ocorrer `BLOCKED`, preserve o JSON e a versão exata do Resolve. Não tente contornar criando objetos em um projeto de produção. Sempre examinar o Viewer do projeto QA e exportar um pequeno render manual para confirmar se os dois Text+ aparecem sobre o mapa; a API sozinha **não** prova os pixels renderizados.

## Matriz de aceitação

| ID | Critério | Estado com esta implementação |
|---|---|---|
| HYB-01 | Inspeção do Resolve 20 e presença do OpenFX | Automatizado; host real ainda **NOT RUN** |
| HYB-02 | Inserir OFX em Edit e anexar Fusion no mesmo clipe | Implementado como prova; host real **NOT RUN** |
| HYB-03 | `MediaIn/MediaOut` existentes e nós conectáveis | Implementado com falha explícita; host real **NOT RUN** |
| HYB-04 | Objetos com tempos distintos sobrevivem a save/reload | Implementado com validação de valores; host real **NOT RUN** |
| HYB-05 | Composição correta no Viewer e Deliver | **NOT IMPLEMENTED** no script, requer QA visual |
| HYB-06 | Geocoordenadas de objetos vinculadas à câmera | **NOT IMPLEMENTED** |
| HYB-07 | Autoria inteiramente pelo Inspector/Edit, sem console | **NOT IMPLEMENTED** |
| HYB-08 | Empacotamento em instalador final simples e offline | **NOT IMPLEMENTED** neste experimento |

## Critério de decisão arquitetural

1. Se HYB-02 ou HYB-03 falhar no Resolve 20, **não** expandir a integração Fusion por suposição; estudar template Fusion Generator contendo o OFX ou composição separada de mapa/overlay.
2. Se HYB-02–04 passar mas HYB-05 falhar, corrigir a conexão de render/alpha e cache antes de qualquer interface de autoria.
3. Se HYB-02–05 passar, desenvolver prova geográfica `country → object → geocoordinate → camera`, preservando identidade por objeto.
4. Só depois construir camada de autoria realmente Edit-first, escolhendo Inspector/macros ou Workflow Integration com base em medição de uso.
5. Até então, manter o OpenFX atual totalmente funcional e evitar baixar mais rasters como pré-requisito.

## Testes offline

```bash
python -m unittest discover -s tests -p 'test_fusion_spike.py' -v
```

## Evidências externas

- Blackmagic Resolve Scripting API: `TimelineItem.AddFusionComp`, `GetFusionCompCount`, `GetFusionCompByIndex`, `ProjectManager.CreateProject/LoadProject`.
- Blackmagic Fusion Scripting Guide: `Composition.AddTool`, `Tool.ConnectInput`, `Tool.SetInput`, `Tool.AddModifier` e operadores de Undo.
- DaVinci Resolve Studio 20: Edit page, OpenFX generator e Fusion compositions no mesmo projeto.

Este documento registra um **teste de arquitetura real executável**, não certificação do produto. A passagem de estágio depende do report gerado pelo Resolve instalado.
