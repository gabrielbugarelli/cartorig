# CartoRig — Especificações completas de animação v1.0

> **Documento pré-implementação.** Não foram feitas alterações no repositório.



---

<!-- Origem: README.md -->

# CartoRig — Especificações de animação avançada

**Versão do pacote:** 1.0 · **Data:** 2026-11-05  
**Natureza:** especificação pré-implementação (design + contratos + TDD)  
**Base de referência:** repositório privado `gabrielbugarelli/cartorig`, branch `main`, commit `31f9069efd75d06f0198e655b1e2833e0109c1cd` (CartoRig v0.2.9).  
**Status:** documento de engenharia; nenhuma das features aqui descritas foi implementada por este pacote.

## Objetivo

Evoluir o CartoRig de animações simples `from/to` para um sistema de motion graphics cartográficos com keyframes por propriedade, trilhas, editor de curvas, câmera geográfica multiponto, rotas e territórios animáveis, presets e futura exportação de keyframes nativos do Fusion.

Este documento **não autoriza alteração de código nem publicação no GitHub**. As especificações são um contrato para orientar a implementação subsequente.

## Índice e ordem de leitura

| Documento | Responsabilidade |
|---|---|
| [01 — Produto e 42 funcionalidades](01_PRODUCT_REQUIREMENTS.md) | Scope, prioridades, casos de uso e critérios de aceite por feature |
| [02 — Arquitetura e dados](02_ARCHITECTURE_AND_DATA_MODEL.md) | Integração com a base atual, módulos, modelo v2, invariantes e migração v1 |
| [03 — Motor de keyframes](03_KEYFRAMES_AND_TIMELINE.md) | Avaliação por frame, interpolações, Graph Editor, operações e UX |
| [04 — Câmera geográfica](04_CAMERA_AND_PRESETS.md) | Trajetórias, projeções, fly-to, bounds, follow e presets |
| [05 — Territórios, rotas e efeitos](05_GEO_MOTION.md) | Animações geográficas, path editor, labels, grupos e expressões |
| [06 — Render, integração e desempenho](06_RENDER_FUSION_AND_SECURITY.md) | PNG, Fusion, escalabilidade, exportação, arquivos e segurança |
| [07 — Estratégia e matriz de testes](07_TEST_STRATEGY.md) | Unidade, propriedade, golden, contrato, integração, E2E e gates |
| [08 — Roadmap e instruções para Codex](08_ROADMAP_AND_AGENT.md) | PRs incrementais, execução TDD, responsabilidades e DoD |
| [09 — Decisões e riscos](09_DECISIONS_AND_RISKS.md) | Escolhas congeladas, hipóteses, limitações e pontos a validar |
| [10 — UX e acessibilidade](10_UI_AND_ACCESSIBILITY.md) | Wireframes textuais, fluxos e interações teclado/mouse |
| [Contrato de cena — JSON Schema](contracts/scene-v2.schema.json) | Forma estrutural da cena v2; regras cruzadas exigem validação adicional |
| [Exemplo de cena v2](contracts/scene-v2.example.json) | Cena de referência serializável e previsível |
| [Tipos públicos esperados](contracts/animation-api.d.ts) | Assinaturas TypeScript para implementação JavaScript |
| [Matriz de cenários](tests/TEST_MATRIX.csv) | Casos identificados com prioridades, entradas e saídas esperadas |
| [Contratos executáveis — TDD](tests/animation-core.contract.test.cjs) | Testes que **ficarão vermelhos** até os módulos serem implementados |
| [Contratos de migração — TDD](tests/migration.contract.test.cjs) | Preservação semântica de cenas v1 |
| [Contratos de operações — TDD](tests/operations.contract.test.cjs) | Undo/redo, keyframe operations e conflitos |
| [Referências técnicas](reference/SOURCES.md) | Fontes de APIs, câmera, easing e Fusion |

## Release map

- **v0.3.0 — Animation Core:** timeline, tracks, keyframes, easing, Bézier de tempo, Auto Keyframe, Undo/Redo, avaliação determinística, migrador v1→v2, compatibilidade com render PNG.
- **v0.4.0 — Camera & Advanced Editing:** Graph Editor, câmera multiponto, trajetória Bézier, fly-to, bearing, auto frame, follow, presets, retiming, controles temporais e exportação em lotes.
- **v0.5.0 — Geographic Motion:** animação de regiões e rotas avançadas, moving objects, constraints, loops, grupos, expressões seguras e efeitos cartográficos.
- **v0.6.0 — Fusion Native (experimental):** keyframes e controles nativos do Fusion conforme *capability detection* e testes reais; PNG continua como fallback estável.

## Princípios vinculantes

1. **A cena é a fonte da verdade**; preview, PNG e Fusion devem resultar da mesma avaliação por frame.
2. **Nenhuma regressão nas cenas atuais**; migração automática, sem salvar sobre o original sem consentimento e com testes de equivalência numérica/visual.
3. **Determinismo**; mesmo JSON + FPS + frame + ativos + versão do motor → mesmo estado avaliado.
4. **Edição não destrutiva**; keyframes não modificam geometrias e arquivos exportados existentes.
5. **Render offline e sem serviços pagos obrigatórios**; atribuições cartográficas preservadas.
6. **Acesso seguro ao Resolve**; nenhum objeto nativo Fusion atravessa a ponte Electron; automação Lua isolada e cancelamento confiável.
7. **Test-first**; falhas verificáveis geram testes antes da implementação. Cobertura isolada não substitui teste no Resolve real.
8. **Produto independente**; nenhuma dependência ou referência a identidades editoriais externas.

## Situação dos testes deste pacote

A suíte `*.contract.test.cjs` foi escrita como especificação executável **para módulos futuros** e não deve ser contada como aprovada. Após implementar os módulos indicados em `contracts/animation-api.d.ts`, executá-la com `node --test tests/*.contract.test.cjs` (preferencialmente copiando os testes para a árvore de testes do repositório). A matriz CSV é normativa. Os gates do documento 07 também exigem regressão dos testes da versão atual.

## Antes de começar a codificar

Ler integralmente os documentos 01–10, validar as decisões de `09_DECISIONS_AND_RISKS.md`, criar branch de feature e implementar de forma incremental. **Não alterar a branch `main` nem publicar commits durante o trabalho exclusivamente documental.**


---

<!-- Origem: 01_PRODUCT_REQUIREMENTS.md -->

# 01 — Especificação de produto e catálogo completo

## Problema e resultado esperado

O CartoRig v0.2.9 limita a câmera a duas poses (`camera.from`/`camera.to`) com `smoothstep`, a animação das rotas a `start/end`, e o destaque territorial a uma interpolação linear de opacidade. O slider atual não expõe trilhas ou tangentes. O objetivo é permitir animações narrativas com múltiplos movimentos cartográficos sincronizados, sem entrar no Fusion para ajustar cada quadro.

**Personas:** editor de documentários geopolíticos, motion designer de jornalismo visual, cartógrafo que publica vídeo, contribuinte open source. **Casos centrais:** (A) sobrevoo de múltiplos países com pausa e retomada, (B) cor de território muda sob narração, (C) duas rotas e um avião se deslocam em velocidades diferentes, (D) reedição com keyframes preservados, (E) reimportação de sequência sem renderizar novamente.

## Catálogo das 42 features aprovadas

As IDs são estáveis para PRs e casos de teste. *P0* = bloqueante para marco; *P1* = parte do marco; *P2* = pode ser entregue em PR posterior do mesmo marco. Complexidade é relativa, não cronograma.

| ID | Recurso | Release | Prioridade | Critério de aceite resumido |
|---|---|---|---|---|
| KF-01 | Keyframes múltiplos por propriedade | 0.3 | P0 | Adicionar, excluir, substituir e avaliar ≥3 keyframes num mesmo track |
| KF-02 | Timeline multicamadas | 0.3 | P0 | Trilha por objeto/propriedade, keyframes visíveis, seleção e playhead |
| KF-03 | Auto Keyframe | 0.3 | P1 | Editar propriedade animável no frame N grava/atualiza keyframe N somente quando ativo |
| KF-04 | Graph Editor | 0.4 | P0 | Curvas de valor/velocidade, handles e preview sincronizados |
| KF-05 | Easing individual | 0.3 | P0 | Linear, Ease In/Out/InOut, Hold, cubic-bezier com efeitos apenas no segmento escolhido |
| KF-06 | Tracks independentes | 0.3 | P0 | Zoom não altera longitude, cor não altera opacidade |
| KF-07 | Copiar, colar, duplicar | 0.3 | P1 | Copia offsets temporais e valores com IDs recriados |
| KF-08 | Mover e escalar grupos | 0.4 | P0 | Reposicionar/retimar sem colidir e preservar a ordem dos keys |
| KF-09 | Snap e marcadores | 0.3 | P1 | Snap configurável a frames, keyframes e playhead; habilitar/desabilitar |
| KF-10 | Undo/Redo | 0.3 | P0 | 100 operações reversíveis sem corromper cena |
| CAM-11 | Câmera multiponto | 0.4 | P0 | 4+ destinos e keyframes próprios de lon/lat/zoom |
| CAM-12 | Trajetória Bézier espacial | 0.4 | P0 | Alças geográficas editáveis com continuidade e preview |
| CAM-13 | Fly-to cinematográfico | 0.4 | P1 | Zoom intermediário previsível entre origens/distâncias diferentes |
| CAM-14 | Bearing / rotação | 0.4 | P0 | Rotacionar mapa, preservar posições geográficas e opção rótulos legíveis |
| CAM-15 | Zoom ancorado | 0.4 | P1 | Coordenada geográfica fixa sob âncora de viewport durante zoom |
| CAM-16 | Auto Frame / Fit Bounds | 0.4 | P1 | País/estado/rota enquadrados com margem, inclusive no antimeridiano |
| CAM-17 | Velocidade constante | 0.4 | P1 | Trajetória por distância de tela ou geográfica (modo explícito) |
| CAM-18 | Camera Follow | 0.4 | P1 | Seguir marcador/objeto sem deslocá-lo indevidamente |
| GEO-19 | Cor animada | 0.5 | P0 | Interpolação colorimétrica explícita; endpoints exatos |
| GEO-20 | Opacidade por keyframe | 0.5 | P0 | Qualquer keyframe 0..1, não apenas fade inicial |
| GEO-21 | Stroke Reveal | 0.5 | P1 | Contornar fronteiras ao longo do perímetro, inclusive MultiPolygon |
| GEO-22 | Fill Reveal | 0.5 | P1 | Reveal direcional ou radial com clipping ao polígono |
| GEO-23 | Pulsação de território | 0.5 | P1 | Pulsação de borda/alpha configurável e reprodutível |
| GEO-24 | Espessura de fronteira | 0.5 | P1 | Stroke width animável em unidades de tela |
| GEO-25 | Glow animado | 0.5 | P2 | Glow com força/raio keyframáveis e limite de custo |
| GEO-26 | Scale / Pop | 0.5 | P1 | Marcador, rótulo ou região surgem com escala/overshoot |
| GEO-27 | Presets de destaque | 0.5 | P1 | Aplicar, reparametrizar e desfazer como uma operação |
| ROUTE-28 | Rotas multiponto | 0.5 | P0 | ≥3 waypoints com geometria de caminho determinística |
| ROUTE-29 | Path Editor Bézier | 0.5 | P0 | Edição de controle e tangentes sem alterar endpoints inadvertidamente |
| ROUTE-30 | Trim Path Start/End | 0.5 | P0 | Início/fim independentes; janela de traçado válida |
| ROUTE-31 | Moving Object | 0.5 | P0 | Ícone avança por distância acumulada ao longo da rota |
| ROUTE-32 | Orient Along Path | 0.5 | P1 | Tangente local define heading com offset |
| ROUTE-33 | Trailing Line | 0.5 | P1 | Rastro de comprimento/duração controlável |
| ROUTE-34 | Dashed Motion | 0.5 | P1 | Offset de tracejado animável sem mudar geometria |
| ROUTE-35 | Route Morphing | 0.5 | P2 | Interpolação por reamostragem com pontos consistentes |
| ROUTE-36 | Velocidade por segmento | 0.5 | P1 | Vários segmentos com duração/easing independentes |
| MG-37 | Presets cinematográficos | 0.4–0.5 | P1 | Presets como tracks editáveis, sem dependência de runtime proprietário |
| MG-38 | Parent & Constraints | 0.5 | P0 | Vincular objetos/câmera, detecção de ciclos e fallback estável |
| MG-39 | Grupos e cascata | 0.5 | P1 | Stagger por frame, ordem explícita, reversível |
| MG-40 | Marcadores de sincronização | 0.4 | P1 | Marker temporal em frame; alinhamento de eventos com timestamps |
| MG-41 | Loop / Ping-Pong / Hold | 0.5 | P1 | Loop finite/infinite em preview; export finita |
| MG-42 | Expressions | 0.5 | P2 | Linguagem/AST restrita, sem eval e ciclos, erro seguro |

**v0.6 (integração transversal):** mapear tracks nativos do Fusion onde houver suporte verificado. Não cria 43ª feature nem substitui a compatibilidade PNG.

## Requisitos funcionais globais

- RF-001: Qualquer propriedade animável possui exatamente uma trilha ativa por `target + path`. Valores base continuam definidos fora das trilhas.
- RF-002: Keys têm frame inteiro, ID único, tipo coerente e ordenação estável; não há dois keys com o mesmo frame numa trilha (novo valor substitui anterior, com Undo).
- RF-003: Preview e render geram a mesma cena avaliada para `frame`, `fps`, assets e configurações idênticos.
- RF-004: A alteração de um track não escreve em outros tracks nem altera dados cartográficos.
- RF-005: Keyframes funcionam para câmera, cores e opacidades, rotas, ícones, marcadores e efeitos declarados pelo catálogo de propriedades.
- RF-006: Keyframe editável exige seleção explícita de objeto/propriedade; Auto Keyframe tem indicador visual de ativação.
- RF-007: Undo/Redo cobre criação, remoção, retime, presets, alterações de tracks, curvas e parenting.
- RF-008: Ao abrir cena v1, o sistema migra para v2 em memória; salvar cria v2, preserva backup/arquivo original salvo anteriormente.
- RF-009: Exportação long-form oferece pausa/cancelamento, gravação atômica de metadados e recuperação baseada em manifest.
- RF-010: Uma falha do Fusion não invalida PNGs exportados nem corrompe projeto.
- RF-011: Funcionalidade avançada indisponível no backend Fusion deve ser explícita; nunca declarar falso sucesso.
- RF-012: Instalação do Windows continua sem requerer Node.js no computador do editor.

## Não funcionais

- NFR-001 Determinismo: sem dependência de `Date.now()`, RNG não seedado ou estado global no avaliador; exceção: geração de IDs na edição, não na avaliação.
- NFR-002 Robustez: rejeitar `NaN`, `Infinity`, frames negativos, IDs inexistentes, ciclos e tangentes inválidas.
- NFR-003 Tempo: avaliação de 1 frame do modelo (sem rasterizar) idealmente < 4 ms p95 com 500 tracks/5.000 keys no hardware de referência documentado; benchmark observacional, não gate em CI genérica.
- NFR-004 Escala: editar sem carregar PNGs de todos os frames na memória; streaming para disco, exportação com checkpoints.
- NFR-005 Acessibilidade: edição de keyframes via teclado, foco visível, ARIA e controle de zoom na timeline.
- NFR-006 Segurança: IPC schema validation, caminhos absolutos verificados, nenhuma execução de JS arbitrário em expressions; política CSP mantida.
- NFR-007 Visual: preservar zoom e cores nos frames antigos sem tolerância perceptível; golden tests de referência.
- NFR-008 Licenças: manter atribuições dos dados de mapa e documentação de recursos externos; presets não embutem assets de terceiros sem licença.

## Casos de aceitação ponta a ponta

**AC-E2E-01 — Voo investigativo:** 240 frames/24fps; câmera no Brasil (0), Venezuela (72), Caribe (156), Washington (239); zoom e bearing em tracks próprios; pausa no frame 120; reprodução determinística.

**AC-E2E-02 — Destacar países:** Brasil muda #2597BF → #D85E58 em 30 frames enquanto Venezuela mantém sua cor; opacity 0 → 0.65 → 0.3; alterar cor não modifica zoom, câmera ou rota.

**AC-E2E-03 — Rotas diferentes:** duas rotas em tempos independentes, uma linha com Trim Path 0..1 e outra com Moving Object + Orient Along Path; export em 4 camadas e reimportação pelo gerenciador.

**AC-E2E-04 — Cena legada:** JSON v1 carregado e migrado; todos os frames do material anterior (1–480) resultam na mesma pose de câmera, highlights e rotas, respeitadas as regras de arredondamento de SVG.

**AC-E2E-05 — Falhas:** edição é desfeita, exportação cancelada mantém arquivos existentes e estado recuperável; importação Fusion sinaliza PARTIAL se criou clipe mas falhou em nós.

**AC-E2E-06 — Fusion Native:** exportar track de opacidade, zoom ou posição em formato nativo somente se o probe do Resolve real confirmar; caso contrário informar modo raster e manter render PNG correto.


---

<!-- Origem: 02_ARCHITECTURE_AND_DATA_MODEL.md -->

# 02 — Arquitetura, contratos e migração de cena

## Baseline realmente existente (v0.2.9)

Auditado no commit `31f9069efd75d06f0198e655b1e2833e0109c1cd`:

| Código | Responsabilidade | Risco de evolução |
|---|---|---|
| `plugin/js/app.js` | Estado/UI, câmera `from/to`, desenho SVG, render de rota, preview/export | Arquivo monolítico e cálculos de animação misturados ao DOM |
| `plugin/main.js` | Validação de cena v1, Electron IPC, export e Fusion | `MAX_FRAMES=480`, schema v1 rígido, validação duplicada |
| `plugin/fusion-comp.js` | `.comp` raster e metadados de quadros | Padrão de 4 camadas fixo; animações já renderizadas como PNG |
| `plugin/bridge/cartorig-insert.lua` | Cria composição com Loaders/Merges/MediaOut | Não recebe objetos keyframe; ponte Lua deve permanecer isolada |
| `plugin/export-manager.js` | Descoberta e validação de exports PNG | Não indexa diretamente novas trilhas de animação |
| `plugin/import-attempts.js` | Histórico separado de importação | Manter independente de mudanças no motor de animação |
| `tests/*.test.cjs` e `tests/lua_harness.py` | Node test runner e simulação Fusion | Devem permanecer passando antes/depois de cada release |

A câmera atual calcula `ease(t)=t*t*(3-2*t)` para `t=frame/(frames-1)`, interpola longitude pelo menor arco via `normLon` (incluindo semântica específica do empate), latitude linear e zoom linear. O `activeFill` é linear, e o progresso da rota tem endpoints próprios. Esses detalhes são **compatibilidade obrigatória de migração**.

## Arquitetura modular alvo

```text
plugin/
  main.js                        # host Electron; UI não conhece fs diretamente
  preload.js                     # IPC explícito tipado/validado
  js/
    app.js                       # camada de orquestração UI; reduzir progressivamente
    keyframe-timeline-ui.js      # trilhas, seleção, drag/drop, shortcuts
    graph-editor-ui.js           # curvas, tangentes, snapping, zoom
  animation/                     # fonte da verdade; sem DOM/IO/Resolve
    schema.js                    # validação semântica, types e limites
    evaluate.js                  # evaluateTrack / evaluateScene
    interpolation.js             # linear/hold/smoothstep/cubic-bezier
    geographic.js                # anti-meridian, Mercator, arc-length, fitBounds
    operations.js                # comandos undo/redo, transações
    migration.js                 # v1 -> v2, idempotente
    paths.js                     # waypoint paths, progress, morph
    constraints.js               # dependency graph e parent/follow
    presets.js                   # compõe tracks; não possui render próprio
    expressions.js               # AST restrita e referências seguras
    index.js                     # API pública CommonJS
  renderer/
    scene-svg.js                 # recebe estado avaliado, sem interpolação própria
  assets/
  bridge/
    cartorig-insert.lua          # no v0.6, adapter em prova de capacidade
build/
  bundle-animation.mjs           # empacota Animation Core pro Electron offline
plugin/dist/cartorig-animation.js# bundle gerado incluído na distribuição
contracts/
  scene-v2.schema.json           # validação estrutural
```

Escolha de compatibilidade: os módulos `plugin/animation/*` exportam CommonJS testável via Node. `npm run build` usa bundler determinístico (por exemplo esbuild com versão travada), produz um IIFE em `plugin/dist` e define `window.CartoRigAnimation`; não usa `require()` no renderer, onde `nodeIntegration` está desabilitado. O instalador distribui o bundle já gerado; Node.js é necessário somente para desenvolver/testar.

**Responsabilidades:** 1) IO e Dialogs no host; 2) engine é pura; 3) UI edita comandos; 4) render consome `evaluatedScene` sem lógica temporal própria; 5) Fusion consome PNGs ou tracks exportáveis por adaptador.

## API obrigatória do avaliador

```ts
validateScene(input: unknown): SceneV2;
migrateSceneV1(input: SceneV1): SceneV2;
evaluateTrack(track: Track, frame: number, baseValue: unknown): Value;
evaluateScene(scene: SceneV2, frame: number): EvaluatedScene;
applyCommand(scene: SceneV2, command: AnimationCommand): CommandResult;
invertCommand(sceneBefore: SceneV2, command: AnimationCommand): AnimationCommand;
serializeScene(scene: SceneV2): string; // ordenação estável
```

`evaluateScene` nunca altera `scene`, track ou geometria. Múltiplas chamadas devem retornar estados com igualdade profunda; sem random, relógio ou dependências do DOM.

## Modelo de cena v2

A versão v2 preserva estruturas de objetos já utilizadas (`territories`, `markers`, `routes`, `style`) e adiciona `animation` como camada declarativa. `camera.base` define valores padrão; `animation.tracks` substitui valores por frame. Posição de câmera é longitude/latitude em graus WGS84 e zoom cartográfico atual. `bearing` é em graus no sentido horário; posição do centro e projeção seguem convenções explicitadas no documento 04.

```json
{
  "version": 2,
  "id": "scene:documentary-001",
  "title": "Brasil e Venezuela",
  "fps": 24,
  "frames": 240,
  "countries": [],
  "territories": [{"id":"country:BRA","name":"Brasil","type":"country","code":"BRA","fill":"#2597BF","stroke":"#2597BF","opacity":0.65}],
  "markers": [],
  "routes": [],
  "camera": {"base":{"lon":-61,"lat":-14,"zoom":3.4,"bearing":0}},
  "style": {"ocean":"#0D1E32","land":"#243B52","highlight":"#EFB26B","accent":"#7AD6E0","border":"#62809A"},
  "animation": {
    "version": 1,
    "tracks": [
      {"id":"track:cam-lon","target":{"objectId":"camera:main","property":"lon"},"valueType":"longitude","preBehavior":"first","postBehavior":"last","keyframes":[
        {"id":"k0","frame":0,"value":-61,"interpolation":"smoothstep"},
        {"id":"k1","frame":239,"value":-54,"interpolation":"hold"}
      ]}
    ],
    "markers":[],"groups":[],"constraints":[]
  }
}
```

O arquivo `contracts/scene-v2.schema.json` valida estrutura e valores básicos. **Validação semântica adicional é obrigatória**, em particular nomes de propriedades por tipo, IDs únicos, resolução de referências e grafos sem ciclos; `JSON Schema` sozinho não basta.

### Invariantes de dados

- `scene.version=2`; `fps` em {24,25,30} enquanto o editor ainda não suportar timebase racional; `frames` inteiro positivo, limite de fase 0.3 ainda 480, v0.4 expande a 36.000 com export por streaming e limites de recurso.
- `track.target.objectId` referencia um objeto existente: `camera:main`, `country:BRA`, `marker:caracas`, `route:caracas-brasilia`, `style:scene` etc.
- `track.target.property` deve existir na registry de propriedades e ser compatível com o objeto. Sem caminhos JavaScript arbitrários (`__proto__`, acesso dinâmico, expressões).
- Track único por `(objectId, property)`. Cada track tem keys ordenados por frame, IDs únicos, no máximo 1 por frame; `frame ∈ [0, frames−1]`.
- `valueType` ∈ `number`, `color`, `angle`, `longitude`, `boolean`, `vector2`, `enum`, `pathProgress`, `path`; cada tipo tem interpoladores permitidos.
- `interpolation` pertence ao **segmento que sai do key** (o último key não influencia o segmento seguinte); os modos `hold`, `linear`, `smoothstep`, `cubicBezier` e `legacySmoothstep` são distintos e testados.
- Tracks têm comportamento `preBehavior`/`postBehavior`: `first` / `last` ou `base`; não extrapolar involuntariamente antes/depois dos keys.
- Cor #RRGGBB ou #RRGGBBAA normalizada; em 0.3 apenas #RRGGBB + opacidade separada; em 0.5 `color` por espaço sRGB linear (lerp em luz linear com conversão final), e fallback `sRGB` histórico explicitado.
- Todas as animações são locais a frames inteiros; avaliação em tempo real pode usar frame fracionário apenas em preview avançado, **sem alterar o resultado do export**.
- `animation.markers` é reservado a marcadores **temporais**; não confundir com `scene.markers` geográficos.
- Valores base ausentes para propriedades derivadas são resolvidos pelo **registro de propriedades**: por exemplo, `route.progress` inicia em 0 quando não declarado; uma trilha desabilitada (`enabled:false`) devolve valor base/valor padrão do registro e não participa do grafo.
- `preBehavior=constant` exige `preValue`, `postBehavior=constant` exige `postValue`; esta regra é checada pelo validador semântico.
- `NaN`, `Infinity`, strings executáveis, objetos cíclicos ou geometrias inválidas são rejeitados antes de renderizar.

## Registro de propriedades animáveis (mínimo)

| Tipo de objeto | Propriedade | Tipo | Faixa / Semântica | Marco |
|---|---|---|---|---|
| `camera:main` | `lon` / `lat` | longitude / number | lon [-180,180), lat [-85,85] | 0.3 |
| `camera:main` | `zoom` | number | [0,7] baseline; cap configurável validado no futuro | 0.3 |
| `camera:main` | `bearing` | angle | graus; interpolação shortest com opção contínua | 0.4 |
| `territory:*` | `opacity` | number | [0,1] | 0.3/0.5 |
| `territory:*` | `fill` / `stroke` | color | #RRGGBB | 0.5 |
| `territory:*` | `strokeWidth` / `glowStrength` | number | valores finitos, clamp por render | 0.5 |
| `route:*` | `progress` | pathProgress | [0,1] | 0.3 |
| `route:*` | `trimStart` / `trimEnd` | pathProgress | [0,1] cada um, start ≤ end | 0.5 |
| `route:*` | `width` / `dashOffset` | number | width [1,30] baseline | 0.5 |
| `marker:*` | `opacity` / `scale` / `rotation` | number/angle | alpha [0,1], scale [0,8] | 0.5 |
| `style:scene` | `ocean`/`land`/`border` | color | #RRGGBB | 0.5 |

## Migração v1→v2 — especificação normativa

A migração ocorre **em memória** ao abrir o arquivo. `version:1` é somente leitura; ao salvar, oferecer gravar novo arquivo `.cartorig.json` ou preservar cópia do original. Não sobrescrever silenciosamente.

1. Copiar `title`, `countries`, `territories`, `markers`, `routes`, `style`, `fps`, `frames` e geometrias sem alterar IDs/coordenadas (cópia profunda).
2. Criar `camera.base = {...camera.from,bearing:0}`. Para `lon`, `lat`, `zoom`, criar key em `frame=0` com `interpolation:"legacySmoothstep"` e key em `frame=frames−1`, se `frames>1`; se `frames=1`, valor estático do frame inicial. Longitude precisa usar **mesma** `normLon(b.lon-a.lon)` do v1.
3. Para cada território `opacity`, produzir os keys em `start/end` com curva **linear**, `preBehavior:"base"` e base de opacidade temporária 0 antes de `start`, preservando o valor final original; se `start=end`, criar degrau. É proibido emitir duas chaves no mesmo frame.
4. Para cada rota `progress`, produzir keys `start=0`, `end=1`, `preBehavior=0` e hold após `end`; se `start=end`, degrau instantâneo. Para `start=0,end>0`, frame 0 vale 0, como no v1. Persistir `start/end` originais como `legacy` somente para auditoria, não como segundo runtime de animação.
5. Markers e demais propriedades sem animação permanecem valores base. Não introduzir fades, easing ou rotação novos.
6. Após migração e reavaliação em todos os frames, a pose de câmera e o progresso de cada rota devem ser numericamente idênticos ao v1 (tolerância aritmética 1e−10); o SVG gerado deve ser idêntico após aplicar mesmos formatadores.
7. `migrateSceneV1()` é determinístico/idempotente: `migrateSceneV1(v1)` produz mesmo JSON estável; `validateScene(v2)` não migra novamente.
8. Falha de migração não altera o arquivo e apresenta erro com `path` da propriedade problemática.

**Nota de implementação:** o esquema v2 usa valores-base e tracks; funções legadas (`currentCamera`, `activeFill`, progresso de `renderSVG`) devem migrar para um adapter que chama `evaluateScene`, não continuar rodando paralelamente. O teste de equivalência sobre v1 é pré-condição para removê-las.

## Evolução de protocolos

- `scene:save/open`: aceitar v1 e v2; resposta de `scene:open` já convertida a v2, com flag de migração na UI. `scene:save` salva sempre v2 após migração.
- `export:begin`: recebe metadados validados e `sceneSnapshotHash`; valida `scene.version=2` e não altera snapshot durante export.
- `export:frame`: manter interface atual inicialmente, mas adicionar `renderJobId` para impedir gravações misturadas de jobs.
- `export:finish`: manifest de formato `exportVersion:2`, `animationEngineVersion`, `sceneSnapshotHash`, FPS, frames e versões de assets. Leitura de exports antigos permanece suportada.
- `exports:inspect/list/import`: aceitar metadados v1 de exportação, mas o diálogo deve exibir modo PNG e modo nativo experimental corretamente.
- `resolve:insert`: permanece serializado por tentativa, preservando histórico e status Lua; nunca passar Tool/Comp nativos à UI.

## Compatibilidade e flags

Habilitar funcionalidades em PRs pequenos com `featureFlags: { animationV2, graphEditor, geoMotion, fusionNative }`; nunca ativar o editor completo antes da equivalência v1+v2. Persistir flags apenas em preferências do usuário, não como requisito para reprodução semântica de uma cena v2.


---

<!-- Origem: 03_KEYFRAMES_AND_TIMELINE.md -->

# 03 — Keyframe Engine, timeline, Graph Editor e operações

## 3.1 Semântica do tempo

**Tempo canônico:** frame inteiro `f`, indexado desde zero, inclusivo em `[0, scene.frames−1]`. O tempo em segundos é `f / fps`; duração total da sequência = `scene.frames / fps`. Um projeto com `fps=24, frames=120` possui frames 0..119 e duração de reprodução de 5 segundos. Não confundir duração com timestamp do último frame (119/24 s). O motor trabalha com keyframes numéricos e calcula os intermediários somente na avaliação, sem gravar frames intermediários no documento.

### Ordem de avaliação

1. Validar integridade da cena e criar mapa de IDs; 2. resolver time-warp/loop; 3. obter valores base; 4. avaliar tracks independentes; 5. avaliar expressões e constraints em ordem topológica; 6. computar geometrias derivadas (caminhos, bounding boxes); 7. aplicar clipping e estilos; 8. entregar `EvaluatedScene` imutável ao render. A ordem é determinística e não depende da ordem de DOM.

### Regras do avaliador `evaluateTrack`

- 0 keys: devolver `baseValue` (clonado ou primitivo), respeitando `enabled`.
- 1 key: antes do key, `preBehavior` (base, first ou `preValue` quando declarado); a partir do frame do key, valor dele.
- ≥2 keys: localizar `k[i]`/`k[i+1]` por busca binária com `k[i].frame <= f < k[i+1].frame`.
- No frame exato do key, devolver exatamente o valor salvo, sem arredondamento prematuro.
- `hold`: valor de `k[i]` no intervalo semiaberto `[ki.frame, k(i+1).frame)`, e valor do próximo key no frame dele.
- `linear`: `u=(f−fi)/(fj−fi)`, `value=lerp(a,b,u)`; a regra do valor depende do tipo (`longitude`, `angle`, `number`).
- `smoothstep/legacySmoothstep`: `u²(3−2u)`; o modo legacy usa o algoritmo de longitude v1, sem reescrever valores.
- `cubicBezier`: converter progresso temporal `u` em easing `E(u)` pelo Bézier 2D normalizado com `P0=(0,0), P1=(x1,y1), P2=(x2,y2), P3=(1,1)`. **Resolver x(t)=u** por Newton-Raphson com fallback bisseção (sem inversão na formula y), depois avaliar `y(t)`.
- `preBehavior=first` retorna primeiro key antes dele, `postBehavior=last` último key após; `base` retorna valor padrão da propriedade. `preValue` só pode ser usado com `preBehavior=constant`, `postValue` com `postBehavior=constant`.
- Nenhuma interpolação entre propriedades de tipos incompatíveis. Strings/enum/boolean só aceitam `hold`.
- Os limites numéricos são validados por propriedade; quantização visual para SVG ocorre **após** a avaliação. 

### Bézier: regras de segurança

- `0 ≤ x1 ≤ 1` e `0 ≤ x2 ≤ 1` garantem monotonicidade temporal; `y1/y2` admitem overshoot controlado (sugestão −2..3; os limites reais por propriedade continuam valendo).
- Newton com até 8 iterações, bisseção até 24; tolerância de x `≤1e−7` e `y` finito; pontos endpoints 0/1 exatos.
- Não cachear resultados por referência mutável; caches indexados por IDs/versão de track + frame.
- Opções *Ease In* `(0.42,0,1,1)`, *Ease Out* `(0,0,0.58,1)`, *Ease In Out* `(0.42,0,0.58,1)`, *Linear* `(0,0,1,1)`; valores equivalentes aos convencionais de funções temporais. `Hold` é discreto.
- Extrapolações não declaradas são proibidas; overshoot de Bézier não pode provocar longitude/zoom/opacity inválidos: política por propriedade é `clamp` ou `reject`, nunca silenciosa e inconsistente.

## 3.2 Tracks e keyframes

- Tracks possuem ID persistente, `enabled`, `locked`, `muted` (alias explícito no UI), `target`, `valueType`, `preBehavior/postBehavior` e lista ordenada de keyframes.
- `keyframe.id` persistente (UUID ou identificador no padrão `kf:<token>`); keyframes têm `frame`, `value`, `interpolation`, opcionais `easing` e `meta` textual limitado.
- Ao inserir keyframe num frame ocupado, `setKeyframe` atualiza o key existente; não permite dois valores ativos nesse frame e guarda comando reversível.
- Operação de copiar keyframes gera novos IDs e preserva offsets temporais relativos (copiar de frame 12 para 80 desloca cada key +68), com erro se extrapolar duração. Transações multitrack aplicam tudo ou nada.
- `retime` escala em relação ao pivô definido (início ou playhead); arredondamento `round-half-up` definido em helper próprio; collisions são resolvidas antes da aplicação por **rejeição e mensagem**, não sobrescrita silenciosa.
- O Auto Keyframe grava apenas no track da propriedade editada; com Auto Keyframe OFF, uma propriedade já animada não pode ter seu valor base alterado silenciosamente em desacordo com o playhead; UI oferece `Editar base`, `Adicionar keyframe` ou `Cancelar`.
- O modo seleção permite `Shift+click`, box select, mover múltiplos keys, copiar/colar, deletar; Ctrl/Cmd+Z/Y e Ctrl/Cmd+Shift+Z seguem convenção de SO.

## 3.3 Undo/Redo — modelo de comando

Cada operação de edição gera `AnimationCommand` com `do`/`undo` sem mutação do snapshot anterior. Uma *ação de usuário* (ex.: arrastar 20 keys ou aplicar preset) é **uma transação no histórico**, mesmo que contenha 20 mudanças. O histórico registra no mínimo 100 transações e pode ter limite de memória; exceder limite descarta a entrada mais antiga. Ao executar nova ação após Undo, limpar a pilha Redo. Export não é ação editável e não entra no Undo.

| Comando | Estado afetado | Reversão |
|---|---|---|
| `track.create/delete` | coleção de tracks | restaura track integral e ordem |
| `keyframe.upsert/delete` | keyframes da propriedade | restaura valor/tangentes originais |
| `keyframes.move/scale` | lista de keys em tracks | restaura frames anteriores |
| `track.setEasing` | modo/tangentes do segmento | restaura easing anterior |
| `object.setBase` | propriedade base | restaura valor anterior |
| `object.parent` | grafo de constraints | restaura parent antigo |
| `preset.apply` | múltiplos objetos/tracks | desfaz toda a transação de uma vez |
| `time.marker.add/move/delete` | marcadores temporais | restaura marker/posição |

## 3.4 Timeline multicamadas (v0.3)

### Layout

- Faixa temporal superior: escala de frames/segundos/timecode, playhead, zoom horizontal, range de preview.
- Painel de objetos hierárquico: Câmera, Territórios, Rotas, Marcadores, Grupos, Efeitos; expandir para propriedades.
- Keyframes: diamantes, seleção simples/múltipla, hover tooltip `frame/value/easing`, distinção de Hold/Bezier, track locked e muted.
- Inspector: value base, valor avaliado no frame, controles de keyframe, Auto Keyframe, menu de easing, valor exato e tangentes.
- Playhead sincronizado: scrubbing deve sempre visualizar `evaluateScene(scene, frame)`; modificação em inspector atualiza somente o target selecionado.
- Filtro e pesquisa de trilhas, colapso de grupos, lista virtualizada quando >100 tracks; teclado Tab navega sem exigir mouse.
- Botões essenciais: adicionar/remover key, anterior/próximo key, pausar/reproduzir, loop preview, snap, Auto Keyframe, zoom timeline e Undo/Redo.

### Política de snap

A ordem de prioridade sugerida é (1) playhead, (2) marker temporal, (3) keyframe adjacente, (4) frame inteiro; distância de snap em pixels do viewport e não em tempo absoluto. `Alt` durante arraste suspende snap. Desabilitar snap não altera a quantização final para frames inteiros; permite só arrastar livremente antes do release.

## 3.5 Graph Editor (v0.4)

- Modo **Value Graph** para number/color-channels, e **Speed Graph** para propriedades escalares e caminhos, com eixos rotulados, zoom/pan e seleção de handles.
- Handle do segmento representa timing Bézier `(x1,y1,x2,y2)` — não confundir com handles geográficos de `CAM-12` e `ROUTE-29`.
- Para `longitude`, renderizar curva *unwrapped* durante edição, valor final normalizado depois; para bearing, usar modo shortest ou contínuo definido na trilha.
- Valores de cor podem ser apresentados como canais R/G/B no espaço escolhido; edição por canal deve recalcular cor de forma determinística.
- `Hold` é representado em degraus; objetos enumerados não têm editor de Bézier.
- Edição de tangentes deve manter regras x∈[0,1], validando monotonicidade; curva inválida não é salva.
- Graph Editor e Inspector compartilham histórico e state; Undo restaura handles e pontos.

## 3.6 Casos de teste de referência (valores explícitos)

| Caso | Entrada | Resultado |
|---|---|---|
| `linear mid` | keys f0=0, f10=100; frame5 | 50 |
| `hold` | f0=0 Hold, f10=100; f9 / f10 | 0 / 100 |
| `smoothstep` | f0=0→f10=1; f5 | 0.5 |
| `easeIn` | Cubic(0.42,0,1,1) em f5 | 0 < y < 0.5 |
| `easeOut` | Cubic(0,0,0.58,1) em f5 | 0.5 < y < 1 |
| `outside` | base=9, keys f5=10 / f10=20, preBehavior=base | frame0=9 |
| `three keys` | f0=0, f10=100, f20=0 | f0=0, f10=100, f20=0 |
| `single frame` | frames=1 key f0=42 | 42, sem divisão por zero |
| `negative zero` | valor -0 ou +0 | serialização canônica definida (normalizar -0→0) |
| `duplicate frame` | inserir valor no mesmo frame | atualiza valor, mantém 1 key |
| `immutability` | `evaluateScene` duas vezes | cena de entrada byte-a-byte inalterada |

## 3.7 Gate do marco 0.3

O marco não está concluído até existir: motor puro, cena v2+migração v1, timeline de múltiplos tracks, easing linear/hold/smoothstep/Bézier, Auto Keyframe, Undo/Redo, copiar/colar, snap, preview/export idênticos, testes de valores e golden em pelo menos 3 projetos existentes, sem regressão da inserção Lua.


---

<!-- Origem: 04_CAMERA_AND_PRESETS.md -->

# 04 — Câmera multiponto, caminhos geográficos e presets

## Estado de câmera

```ts
CameraPose = { lon:number, lat:number, zoom:number, bearing:number };
CameraRig  = { base:CameraPose, anchor?:{lon:number,lat:number, screenX:number,screenY:number} };
```

A câmera atual do CartoRig usa **Web Mercator próprio** em SVG, não MapLibre como runtime. Preservar sua projeção na v0.3. O modelo geográfico deve funcionar com lon ∈ [−180,180), lat ∈ [−85,85], zoom ∈ [0,7] na compatibilidade inicial. `bearing` rotaciona a projeção 2D ao redor do centro da viewport; globo/terreno/pitch não fazem parte destes marcos.

## CAM-11 — Multiponto

- Criar keyframes independentes para `lon`, `lat`, `zoom` e, desde 0.4, `bearing`.
- Selecionar posição atual da câmera (preview) e definir key em frame desejado; remover/editar um key não recalcula demais tracks.
- Suportar caminho de 4 ou mais destinos sem travar; em câmera com paths espaciais, tratar `lon/lat` como um **track vetorial posicional** que pode coexistir com `zoom` e `bearing`, mas nunca com tracks de lon/lat independentes simultaneamente sem política de prioridade explícita: UI deve oferecer conversão para path rig.
- Nomear poses (ex.: América do Sul, Caracas, Caribe, Washington) usando marcadores temporais associados aos keyframes.

## CAM-12 — Bézier espacial

- Posições geográficas são convertidas a um espaço de cálculo contínuo (Mercator com longitude desembrulhada) antes do Bézier. `world wrap` evita saltos de ±360 graus.
- Controles de Bézier **espacial** são lat/lon ou deslocamento de tela com base em uma pose e zoom de referência; armazenar coordenadas geográficas/control points no JSON, não pixels de viewport.
- Tangentes em nós com modo `free/aligned/mirrored` e opção de trajetória straight; edição na prévia oferece handles sobre mapa.
- Distância percorrida avaliada por tabela de arco acumulado (`arc length LUT`) para velocidade de percurso; subdivisão determinística com erro máximo documentado (ex.: 0,5 px em 4K no zoom máximo testado).
- Longitude curta é default, com `wrapMode:'shortest'|'eastward'|'westward'|'continuous'`; empates ±180 preservam regra especificada e testada.

## CAM-13 — Fly-to

Compor zoom-out intermediário + translação + zoom-in para deslocamentos extensos. Na primeira versão, implementar um modelo determinístico e configurável (`peakZoomOut`, `flightCurve`, `minZoom`, `ease`) documentado no projeto; não fazer promessa de equivalência pixel-a-pixel com `MapLibre.flyTo`. Caso se deseje o modelo de van Wijk/Nuij, realizar spike técnico referenciado antes de adotá-lo.

**Aceite:** viagem entre Caracas e Washington possui plano de zoom contínuo (sem NaN/saltos), chega à posição e zoom exatos no último key; preservar anchors quando configurados. Curva de tempo e trajetória espacial são controles separados.

## CAM-14 — Bearing

- `bearing` em graus (clockwise positivo). `0°` preserva render atual; `90°` muda orientação sem distorcer posicionamento relativo ao centro.
- Interpolação `shortest`: 350° → 10° percorre +20°, não −340°; modo `continuous` permite voltas completas.
- Ícones/rótulos podem permanecer orientados à tela (`keepUpright`) ou girar com mapa (`rotateWithMap`), com controle por tipo/objeto.
- Interação geográfica (picking/invert lon-lat) deve inverter bearing antes da operação de Mercator; duplo clique para criar marcador deve continuar acertando localização.

## CAM-15 — Zoom com âncora

Dada uma coordenada `(lon,lat)` e um ponto `(screenX,screenY)`, ao alterar zoom/bearing, calcular o novo centro que preserve a projeção do anchor no mesmo pixel. Desfazer/restaurar entre keyframes. O contrato é geométrico, não depende de UI.

## CAM-16 — Fit Bounds

- Aceitar bounds de uma ou mais features de países, estados e rotas, com padding configurable (px ou %) e limitação min/max zoom.
- Resolver bounds cruzando antimeridiano pelo menor intervalo circular de longitude (ex.: 179°E a −179°W = 2°, não 358°).
- Tratar features multi-polígono, ilhas e geometrias degeneradas; se vazio, devolver erro descritivo sem mover câmera.
- Output: `{lon,lat,zoom,bearing}` calculado para caber em viewport real `width×height` de destino e padding.

## CAM-17 — Velocidade constante

Definir claramente o espaço: `uniformGeo` (distância geodésica aproximada) ou `uniformScreen` (distância de tela na projeção de referência). Usar lookup cumulativa de comprimento de arco com busca binária; separar easing de velocidade: quando `uniform=true` mas o usuário escolhe `easeIn`, o percurso obedece easing temporal e mantém uniformidade da parametrização espacial (não velocidade instantânea constante, que seria contraditória).

## CAM-18 — Camera Follow

`followTarget` referencia `marker:<id>` ou `movingObject:<id>`, com offset geográfico/pixel e parâmetros de amortecimento determinístico. A posição do objeto deve ser avaliada **antes** da câmera follow; detecção de ciclos impede câmera seguir um objeto que se posiciona relativamente à própria câmera. `latencyFrames` para follow não pode consultar tempo real, apenas amostras por frame.

## MG-37 — Presets de câmera e cinematografia

| ID | Nome | Tracks criados | Parâmetros editáveis |
|---|---|---|---|
| PRESET-CAM-01 | Focus Region | lon/lat/zoom/bearing | alvo, margem, frames, easing |
| PRESET-CAM-02 | Fly In | zoom + pose | destino, duração, pico, easing |
| PRESET-CAM-03 | Fly Out | zoom + pose | origem, duração, pico, easing |
| PRESET-CAM-04 | Multi-stop Tour | camera path + markers | waypoints, pausa, velocidade |
| PRESET-CAM-05 | Orbit 2D | bearing + centro | ângulo, duração, loop (2D) |
| PRESET-CAM-06 | Follow Route | camera follow | rota/objeto, offset, amortecimento |
| PRESET-GEO-01 | Country Reveal | opacity/trace | alvo, delay, cor |
| PRESET-GEO-02 | Border Trace | stroke progress | modo, sentido, easing |
| PRESET-ROUTE-01 | Route Draw | route trim | percurso, duração, easing |

Os presets são **templates que criam keyframes comuns**. Nenhum preset tem runtime oculto, template proprietário ou acesso à rede. Aplicar preset = transação única com Undo; alterar parâmetros após aplicar edita tracks identificados, sem duplicar indevidamente.

## Testes específicos de geografia

- `lon=179` → `lon=−179`, modo shortest, posição intermediária junto do antimeridiano (não atravessa o mapa inteiro).
- `bearing=350` → `10`, frame médio ≈ 0° no modo shortest; `continuous` preserva rotação longa.
- Projeção/inversa com bearing 0°, 45°, 90° e zoom 0/3.4/7; erro geográfico ≤1e−5 grau para pontos visíveis, exceto bordas/clipping.
- Fit Bounds da Venezuela + Brasil funciona em 16:9 HD/4K e não corta os polígonos escolhidos fora da margem especificada (considerando datasets simplificados).
- Fly-to, para qualquer duração 2..240, mantém endpoints exatos e valores finitos em todos os frames; um único frame não divide por zero.
- Multi-stop com 4 destinos atravessa todos na ordem e cada keyframe tem pose exata.
- Follow sem ciclo produz offset estável após warmup; follow com ciclo é rejeitado.

## Tecnologia externa

MapLibre GL JS é uma **referência algorítmica de alto nível**, não uma dependência obrigatória desta implementação. Documentação relevante: https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/FlyToOptions/ e https://maplibre.org/maplibre-gl-js/docs/API/type-aliases/CameraOptions/ . A geometria final é gerada pelo renderer SVG existente até um futuro projeto específico de substituição.


---

<!-- Origem: 05_GEO_MOTION.md -->

# 05 — Territórios, fronteiras, rotas, objetos e motion

## 05.1 Base cartográfica e efeitos

O renderer atual parte de polígonos GeoJSON simplificados, projeta em Web Mercator e gera SVG. Em 0.5, o renderer recebe um `EvaluatedScene` **imóvel** de `evaluateScene()`. Ele nunca pergunta "qual frame?" para calcular animações por conta própria.

A camada `base` continua independente de `highlights`, `routes` e `markers`. Efeitos sobre uma mesma região devem ter IDs estáveis e ordem de composição explícita; não reordenar por acaso durante animações.

### GEO-19 — Cor por keyframe

- Cores #RRGGBB, interpolação documentada. Escolha de produto: sRGB **linear-light** no motor novo, com conversão final a sRGB para saída SVG; modo `legacySrgb` somente para preservação de renderizações anteriores.
- Cada canal interpolado em espaço linear; endpoints exatos (sem deslocamento no primeiro/último quadro).
- UI permite selecionar curva de cor, exibindo visualização; não inferir opacidade de hex sem contrato.

### GEO-20 — Opacidade por keyframe

- Opacidade 0..1 em número real; keyframes independentes de cor, border width e glow.
- `opacity` se aplica ao grupo de região, com opção separada por fill e stroke em release posterior.
- Ordem de composição: opacidade de grupo * opacidade do efeito. Caso de testes: valores 0, 0.65, 0.3 e nunca >1 ou <0.

### GEO-21 — Stroke Reveal

- Caminhos de anéis externos e internos devem ser computados em sequência estável. Recurso `reveal.progress` 0..1 percorre comprimento de contorno, não número de vértices.
- Ordem de revelação: exterior→interiores, índices de GeoJSON determinísticos, opção `allAtOnce` vs `sequential`.
- Ao cruzar antimeridiano, dividir paths antes de projetar; não desenhar linha reta atravessando a tela.
- MultiPolygon e ilhas são suportados. Nós inválidos são tratados no carregamento, não ignorados no render sem mensagem.

### GEO-22 — Fill Reveal

- Clip mask por polígono, modo `leftToRight|rightToLeft|topToBottom|radial|centerOut` e `progress` 0..1.
- Máscara evolui em coordenadas cartográficas ou de tela conforme opção de modo; default `screen` preserva direção visual durante rotação da câmera.
- Fill reveal limita preenchimento ao interior (incluindo holes) e não pinta oceano indevidamente.

### GEO-23–26 — Pulse, stroke width, glow e pop

- Pulse: módulo determinístico `periodFrames`, `phaseFrames`, `min/max` e `iterations`; sem reliance em clocks/timers para export.
- Stroke width: animável em **pixels de saída**, escalando com resolução conforme política `screenPx` ou `worldUnits` (default `screenPx`); preservar bordas a zooms diferentes.
- Glow: camada de pós-efeito controlável, fallback SVG (`filter`) limitado; renderizador pode desligar glow em preview low-quality, mas export final deve respeitar configuração.
- Pop: animar `scale` com origem geométrica, overshoot limitado; em regiões muito grandes, documentar que pop de máscara geográfica pode custar caro; marcadores primeiro.

### GEO-27 — Presets de destaque

Usar presets transacionais como `Country Fade`, `Border Trace`, `Pulse Alert`, `Country Color Shift`, `Pop Marker`. Presets produzem tracks e efeitos comuns, com parâmetros modificáveis, sem runtime escondido. Undo = uma ação.

## 05.2 Rotas multiponto

### ROUTE-28 — Waypoints

Estrutura:

```json
{
  "id":"route:caracas-brasilia",
  "kind":"arrow",
  "path":{"type":"bezierPath","waypoints":[
    {"id":"wp:1","lon":-66.9036,"lat":10.4806,"in":null,"out":{"dx":4,"dy":1}},
    {"id":"wp:2","lon":-60,"lat":-4,"in":{"dx":-2,"dy":1},"out":{"dx":2,"dy":-1}},
    {"id":"wp:3","lon":-47.8828,"lat":-15.7939,"in":{"dx":-2,"dy":-1},"out":null}
  ],"wrapMode":"shortest"},
  "color":"#7AD6E0", "width":4
}
```

Waypoints geográficos são o source of truth. `in/out` são deslocamentos em graus no modo geográfico e devem ser documentados de forma transparente; para precisões maiores, implementar controles projetados em metros/mercator com os mesmos IDs, não persistir pixels dependentes de zoom.

### ROUTE-29 — Path Editor

- Adicionar/remover/mover waypoint; tangentes livres, alinhadas ou espelhadas; snapping opcional a cidade/país/rota, com tolerância em pixels.
- Edição preserva IDs não afetados e retorna comando Undo reversível; coordenadas WGS84 verificadas; não permitir route inválida com menos de dois pontos.
- Regiões de limite e antimeridiano devem ser tratadas antes da projeção.

### ROUTE-30 — Trim Paths Start/End

Definir `trimStart` e `trimEnd` em [0,1]. O segmento visível cobre distância cumulativa parametrizada de `trimStart` a `trimEnd`; `0,0` é invisível, `0,1` revela tudo, `start>end` é erro em edição normal. Efeito especial de wrap loop deve explicitar `allowWrap=true`, não assumir.

### ROUTE-31–33 — Moving Object, Orient, Trail

- `movingObject.routeId` + `progress` e `iconAssetId` (biblioteca local permitida), escala/tint/opacity.
- `position` = caminho avaliado na distância cumulativa. `rotation` = `atan2` da tangente projetada + `angleOffset`; opção `keepUpright` e `orientAlongPath` não são combinadas implicitamente.
- Trail: por padrão renderizar `[max(0, progress−length), progress]`, permitindo duração em frames opcional como janela temporal avaliada no path; não persistir milhões de pontos amostrados.
- Durante playback/export, objeto só existe entre `visibilityStart/End` e possui tratamento para endpoint e caminho degenerado.

### ROUTE-34–36 — Tracejado, morph e velocidade variável

- `dashOffset` é propriedade animável independente de `progress`; valor interpretado em pixels de saída e modulo padrão de dash, determinístico.
- `morph` entre dois paths é definido por reamostragem em N pontos a comprimentos normalizados e interpolação de coordenadas *unwrapped*, preservando direção/origem. `N` fixo por export; evitar auto-reordenar waypoint para reduzir distorção. Não permitir morph em rotas com geometrias inválidas.
- Velocidade por segmento: cada trecho tem `startFrame`, `endFrame`, `easing`, `distanceMode`; soma de durações/segmentos não pode exceder o período global do objeto sem regra clara de clipping.

## 05.3 Constraints, grupos e composição

### MG-38 — Parent/Constraints

- Grafo direcionado `parentId -> childId`, proibindo self-parent/ciclos. Ordenação topológica estável por ID.
- Tipos: `followPosition`, `followRotation`, `keepScreenSize`, `keepUpright`, `offsetScreen`, `offsetGeographic`, `followRoute` e `cameraFollow`.
- Unidade de offset declarada: pixels de saída ou graus/meters. Zoom muda a transformação conforme essa unidade, sem ambiguidade.
- Remover pai oferece opção de preservar posição mundial atual (*keepWorldTransform*) ou reverter ao base.

### MG-39 — Grupos e cascata

- Grupos suportam seleção e animação múltipla; `staggerFrames` desloca os keys de cada membro em ordem declarada `document|name|reverse|manual`.
- Aplicar à lista de 10 países com +3 frames produz offsets [0,3,6,...,27]; transação única; Undo restaura integralmente.

### MG-40 — Sincronização temporal

- Markers com `id`, `frame`, `label`, `color`, opcional `sourceTimecode`; não armazenar arquivos de áudio no JSON.
- Timecode de interface usa FPS; importação de marcadores de narração é arquivo CSV explícito no futuro. Prioridade 0.4: marcadores manuais, snap e export.

### MG-41 — Loops e tempo

- `loopMode: none|repeat|pingPong|hold` aplicado a um track ou grupo, com região `[start,end]` e contagem finita/indefinida em preview.
- `pingPong` deve visitar endpoints sem duplicar indevidamente um frame ao inverter; definir fórmula de período `2*(end-start)` quando intervalo >0.
- Export é sempre finita: o avaliador recebe frame 0..frames−1 e resolve o loop localmente.

### MG-42 — Expressions seguras

- Sem JavaScript arbitrário, sem `eval`, `Function`, shell, rede, disco ou acesso a objeto Electron.
- Linguagem mínima: números, `+ - * /`, parênteses, `min/max/clamp/abs/sin/cos`, constantes, `frame`, `time`, referência restrita `track("id")` apenas para tracks existentes; parser própria ou biblioteca com AST inspecionável.
- Avaliar no grafo topológico. Ciclo A→B→A é erro de validação antes do render. Divisão por zero, overflow e `NaN` causam erro descritivo do track, não degradação silenciosa.
- Orçamento de complexidade: ≤1.024 nós AST, ≤16 níveis, sem recursão e sem loop; resultados sempre finitos.

## 05.4 Critérios visuais e desempenho

- Rotas/territórios permanecem georreferenciados ao mudar câmera e bearing.
- Em cada frame, mesma rota e parâmetros geram a mesma geometria (golden snapshot por classe de zoom).
- Frames 0, 1, meio, fim de cada animação têm snapshots visuais para PNG final e `renderSVG` canônico; tolerância de pixels limitada (discutida no documento 07).
- Efeitos como glow não podem mudar coloração/posição de regiões sem efeito; composição transparente precisa preservar alpha.
- Para paths longos, tabelas de comprimento de arco são cacheadas por identidade/versão da geometria + parâmetros, não por frame.


---

<!-- Origem: 06_RENDER_FUSION_AND_SECURITY.md -->

# 06 — Render, Fusion, formatos, escalabilidade e segurança

## 06.1 Fonte da verdade

O renderer consome `evaluateScene(scene, frame)` e não contém interpolação temporal. O caminho de saída atual (SVG→PNG→Loader/MediaOut no Fusion) permanece **suportado durante todo o roadmap**. A futura exportação nativa Fusion **não deve** substituir a opção PNG até haver paridade funcional comprovada no Windows.

Fluxo:

```text
Scene v2 JSON
  ↓ validação semântica e resolução de assets
Keyframe Engine (puro, determinístico)
  ↓ EvaluatedScene por frame
Geographic Renderer (SVG com transform e clipping)
  ├─ Preview (viewport / downscale)
  ├─ PNG Export (composite ou base/highlights/routes/markers)
  └─ Fusion Native Adapter (v0.6, condicionado a capability probe)
          ↓ Lua/fuscript com fallback PNG
Fusion Composition + Timeline
```

## 06.2 Exports long-form

Na versão de referência, `MAX_FRAMES=480`, 4 camadas e máximo 36 MB por PNG. Até 0.3 o limite permanece para não desestabilizar o IPC. Na v0.4 migrar para **até 36.000 frames por cena** (20 min a 30 FPS), sujeito a pré-estimativa de armazenamento, limite de processo/FS e configurações de render. Não é promessa de render rápido. A UI deve avisar caso o volume estimado seja impraticável.

### Pipeline de render em lote

1. Gerar `renderJobId` aleatório apenas para identificação de job, persistir `sceneSnapshotHash` do JSON normalizado e `engineVersion`; capturar snapshot profundo da cena antes de iniciar.
2. Validar projeção, assets, pistas de animação e disponibilidade de disco; escolher `batchSize` configurável 8–48 frames, padrão 24.
3. Produzir imagens de cada frame com limite de buffers simultâneos; gravar atomically `map_XXXXXX.png.part` e renomear após validação de assinatura/dimensões. Nomes com 6 dígitos na export v2 suportam >9.999 frames. Exportações v1 com 4 dígitos são compatíveis na importação.
4. Registrar `export.json` progressivo/sidecar `render-progress.json` atualizado a cada lote, incluindo `completedFrames`, `hash`, `layerLayout`, `source`, `timestamp` e estado `IN_PROGRESS|COMPLETE|CANCELLED|FAILED`.
5. Recuperar só se `sceneSnapshotHash`, engine, ativos, resolução, fps e layout de camadas forem idênticos. Arquivo `*.part` incompleto nunca é tratado como frame concluído.
6. Cancelamento interrompe criação de novos lotes, não apaga exportações anteriores e devolve resultado claro. `COMPLETE` é persistido somente após validar todas as camadas/frames.
7. Reimportações de PNG usam manifest, validam hash/contagem e **não re-renderizam**; log de tentativas Lua separado da exportação de frames.

### Render incremental

Para edição em preview, cache por `(sceneSnapshotHash, frame, width, height, layer, rendererVersion)`; invalidar por dependência de tracks/objetos, não por momento aleatório. No MVP desta etapa, invalidar todos os frames ao alterar uma geometria é aceitável; perf avançada por intervalo só após teste de correção.

## 06.3 Metadados de exportação

Formato novo `exportVersion:2` com campos obrigatórios:

```json
{
  "exportVersion":2,
  "title":"Mapa",
  "frames":240,
  "fps":{"num":24,"den":1},
  "width":1920,
  "height":1080,
  "layers":["base","highlights","routes","markers"],
  "framePattern":"map_%06d.png",
  "sceneSnapshotHash":"<sha256-hex>",
  "animationEngineVersion":"0.3.0",
  "status":"COMPLETE"
}
```

A estrutura `{fps:{num,den}}` **no export manifest** prepara suporte racional futuro; `SceneV2.fps` permanece inteiro até uma versão que defina nova política timebase. `export-manager.js` deverá aceitar ambos os formatos (v1 e v2) com validadores independentes. Se não houver `exportVersion`, interpretar como manifest v1 apenas quando todos os campos legados forem válidos.

## 06.4 Fusion e API externa

**v0.3–0.5:** o Lua deve continuar criando nós Loader/Merge/MediaOut sem devolver objetos nativos ao Electron. Animar um país no CartoRig significa PNG por frame; a edição continua possível no CartoRig, não no Graph Editor nativo do Fusion. A UI deve tornar essa distinção explícita.

**v0.6 experimental:** implementar `FusionNativeAdapter` com detecção de capacidades do Resolve instalado (versão, ferramentas, atributos e tipos de spline). Investigar via script Lua os métodos `BezierSpline`, `SetKeyFrames`, `GetKeyFrames`, `AddModifier` e animação de `Tool`/`Input`, de acordo com a documentação da **versão instalada**. Materiais antigos do Fusion 8 são somente referência e não prova de compatibilidade com Resolve 20/21. Usar Lua ou arquivos `.comp` bem formados; nenhum `Tool/Composition` pela ponte JS.

Proposta de suporte por propriedade:

| Recurso | Backend PNG v0.3–0.5 | Native Fusion v0.6 |
|---|---|---|
| Opacity em Layer | Renderizada | Converter a controle de Merge Blend, quando comprovado |
| Marker/Text transform | Renderizado | Testar Text+, Transform, animators nativos |
| Camera geográfica lon/lat | Renderizada | Só com nó/projetor próprio validado; caso contrário PNG |
| Route path/trim | Renderizado | Só se máscara/path nativo for representável fielmente |
| Color/glow | Renderizado | Testar ColorCorrector/Glow separadamente |
| 3D terrain/globe | Fora de escopo | Fora de escopo deste roadmap |

O `native` retorna estado `SUPPORTED|PARTIAL|UNSUPPORTED` com razões. Sem equivalência, gerar PNG e declarar fallback. **Jamais** criar uma composição que pareça importada mas não inclua a animação prometida.

### Idempotência de inserção

Distinguir exportação de tentativa de importação (regra já implementada na linha v0.2.9): `cartorig-imports/<attemptId>/{job,result}`. Uma sequência pode ser inserida mais de uma vez mediante confirmação; a mesma tentativa Lua não pode se repetir cegamente. Uma falha `PARTIAL` é tratada como risco de clipe presente, com aviso e verificação do usuário.

## 06.5 Performance e caches

- Motor: `evaluateTrack` O(log K) para localizar segmento em K keys; `evaluateScene` O(T log K + D) para T tracks e D dependências. Pré-compilar tracks e caches dentro de objeto derivado imutável não serializado.
- Renderizar só camada alterada no preview quando for seguro; para export final usar snapshot integral.
- Caminhos de perímetro/câmera devem usar LUT de comprimento de arco com cache por identidade e versão de geometria.
- Undo/Redo registra comandos, não duplicatas de todas as PNGs.
- UI virtualizada para grandes listas, workers isolados para projeção se o Electron permitir, sem bloquear thread principal; usar cancelamento por `AbortSignal` quando houver operações async.
- Definir hardware de medição nos relatórios. Não exigir p95 de desktop em runners CI compartilhados.

## 06.6 Segurança de dados e IPC

- Electron: `contextIsolation:true`, `sandbox:true`, `nodeIntegration:false`, `CSP` restritiva existentes devem ser preservados.
- Qualquer payload de IPC é validado no processo principal; não confiar na UI. Limitar tamanho da cena/geometry; migrar o limite 2 MB somente com estudo de RAM/tempo, configurável com limites rígidos por categoria.
- Pastas importadas: resolver/canonicalizar, rejeitar traversal, symlinks inesperados, loops de diretórios, arquivos especiais; validar arquivos PNG (assinatura, dimensões, extensão, fechamento IEND; CRC quando bibliotecas permitirem).
- Expressions: AST restrita, sem `eval`, network, JavaScript engine arbitrária ou plugins carregados dinamicamente.
- Export arquivo temporário e rename no mesmo volume; nunca apagar projeto/PNG existente por falha de export ou rollback.
- Não transformar texto de legendas de usuário em HTML; renderer escapa caracteres. Não usar SVG externo com scripts embutidos.
- Armazenar snapshots sem tokens/credenciais/caminhos privados desnecessários. Git nunca recebe exports locais por acidente; atualizar `.gitignore` se novos diretórios forem introduzidos.

## 06.7 Erros e telemetria

Mensagens amigáveis com códigos estáveis: `ANIM_INVALID_TRACK`, `ANIM_DUPLICATE_FRAME`, `ANIM_UNSUPPORTED_VALUE`, `ANIM_CYCLE`, `RENDER_CANCELLED`, `RENDER_DISK_FULL`, `FUSION_PARTIAL`, `FUSION_CAPABILITY_UNAVAILABLE`. Log estruturado local, com opção de copiar diagnóstico **sem publicar dados do usuário automaticamente**.

## 06.8 Gates de qualidade por release

- 0.3: antiga suíte JS/Lua verde, migrador v1 golden green, novas curvas e render pass, sem regressão do gerenciador de export.
- 0.4: benchmarks long-form, cancelamento/retomada e e2e de câmera em múltiplos destinos; nenhum frame perdido/duplicado.
- 0.5: geometria/antimeridiano/alpha/layers e arquivos GeoJSON; property-based sobre paths e constraints.
- 0.6: sandbox do Resolve Studio 20/21 real com vídeo/timeline e prova de equivalência por keyframe; fallback PNG se native não passar.


---

<!-- Origem: 07_TEST_STRATEGY.md -->

# 07 — Estratégia de testes e gates de certificação

## Escopo e interpretação

Testes automatizados podem demonstrar conformidade com requisitos observáveis e reduzir regressões, mas **não provam ausência de bugs**. Nenhuma feature é considerada pronta por um relatório textual isolado: requer execução do código real, identificação de versão/commit, evidências de testes, validação visual e, para Fusion Native, teste na instalação real do Resolve no Windows.

**Baseline antes do desenvolvimento:** executar `npm test` e `npm run test:lua` no `main` da v0.2.9 e registrar SHA/saída. Após cada PR, repetir regressão antes de considerar novos testes. Os contratos executáveis desta pasta estão no estado *red-by-design* até a implementação; não devem ser reportados como aprovados.

## Tipos de testes

| Camada | Testes exigidos | Framework/estratégia |
|---|---|---|
| Unidade do motor | easing, track, ranges, key mutations, validation, command history | Node `node:test` + `assert`, sem Electron |
| Unidade de geografia | wrap/antimeridiano, Mercator/inversa, Bezier, arc length, fitBounds | Node, testes numéricos e propriedades |
| Unidade de efeitos | opacity, colors, routes, trims, markers, parent cycles e expressions AST | Node, entradas malformadas, golden JSON |
| Unidade de migração | v1→v2, frames 1/2/120/480, preservação da amostra e idempotência | Node, fixture v1 real, modelo legada como oráculo |
| Unidade de UI | snap, dragging, Auto Keyframe, focus, undo/redo e confirmação | DOM simulado (jsdom/Playwright se adicionado) |
| Integração IPC | save/open, export PNG, cancel, import assets, erros de validação | host mock existente (`tests/helpers.cjs`) |
| Visual golden | SVG normalizado e PNGs de frames principais, HD/4K, antimeridiano | Playwright/Chromium versionado; tolerância formal |
| E2E | edição UI real, export em lotes, retomar, reimportar | Windows/Resolve; manual + Playwright se viável |
| Lua | importação, partial, retries, 4 layers e novas animações nativas | `tests/lua_harness.py` + teste no Resolve real |
| Performance | perf de tracks, memória, render long-form | microbench com máquina registrada, não somente CI |
| Segurança | traversal, JSON malformado, ciclo, expressions e assets | Node e revisão de permissão/escopo |

## Regras de qualidade

1. Toda feature `P0/P1` possui pelo menos testes de caminho feliz, borda, erro e regressão.
2. **Cobertura alvo** dos módulos `animation/*`: linhas ≥95%, branches ≥90% (reportar com `c8` ou ferramenta equivalente). Cobertura não substitui *property tests* e snapshots.
3. Casos de modelo determinístico usam `deepStrictEqual` ou tolerância numérica documentada; não usar `Date.now` real nos testes.
4. **Importação v1** precisa testar todos os frames de pelo menos 3 cenas de referência; câmera e progresso com tolerância ≤1e−10, render SVG/golden por frame-chave e tamanhos HD/FullHD.
5. Testes numéricos de Bézier usam validação independente (tabela golden de fontes confiáveis) e propriedades: endpoints, monotonicidade de tempo, ausência de NaN.
6. Testes de antimeridiano verificam os dois modos de deslocamento e trajetória render; não basta testar `normLon` isoladamente.
7. Golden PNGs: versão do navegador travada, fonts conhecidas no runner, metadata PNG normalizada; *tolerância de diferença* para raster (por exemplo pixel MAE ≤1/255 em 99.5% dos pixels) só após estabelecer baseline. Geometria de objeto não pode deslocar arbitrariamente mesmo com fontes distintas.
8. Testes de export simulam falta de espaço, crash, frame duplicado, cancelamento, recomeço e mudança de hash.
9. Ao terminar cada release, gravar relatório com commit SHA, SO, Node, Resolve (quando aplicável), comandos, total pass/fail/skip, cobertura, cenários E2E e limitações.
10. **Fail closed**: erro em render/animator/import não pode reportar `ok:true` nem produzir export `COMPLETE`.

## Matriz testável

A matriz principal está em `tests/TEST_MATRIX.csv`, com IDs `T-KF`, `T-CAM`, `T-GEO`, `T-RT`, `T-MG`, `T-MIG`, `T-IPC`, `T-NATIVE` etc. Cada teste deve referenciar pelo menos uma feature `KF-##`, `CAM-##`, `GEO-##`, `ROUTE-##` ou `MG-##` e o marco de entrega.

## Suites e comandos futuros

```bash
npm ci
npm run build
npm test                 # testes existentes + novos tests/*.test.cjs
npm run test:contracts   # testes de contrato que falham até API existir
npm run test:lua         # simulador Lua original + novos casos
npm run test:coverage    # cobertura engine e adaptadores
npm run test:integration # IPC, export e UI mock
npm run test:e2e         # quando houver ambiente apropriado
npm run test:performance # máquinas controladas, fora de CI padrão
```

Os scripts ausentes na v0.2.9 são propostas, não comandos disponíveis hoje. O pacote não executou nenhuma das futuras suítes contra features não implementadas.

## Casos obrigatórios detalhados

### A) Tempo e interpolação

- Keys 0→10 (0→100) com linear retornam 50 no frame 5; hold mantém 0 até frame 9 e retorna 100 em 10.
- Smoothstep em t=.25 = .15625; t=.5=.5; t=.75=.84375.
- Cubic Bézier `(0,0,1,1)` ≈ linear; `(0.42,0,1,1)` em u=.5 fica < .5; parâmetros de x inválidos rejeitados.
- Último frame exato, single frame, keys duplicados, track vazio, track desabilitado, inversão de frames, overflow, interpolação de enum com linear rejeitada.

### B) Editor

- Auto Keyframe ON no frame 37 cria keyframe somente na propriedade selecionada; repetição atualiza key em vez de duplicar; OFF abre fluxo explícito.
- Movimento de três keys com +7 frames mantém offsets relativos, IDs e valores; conflito lança erro, sem mutação parcial.
- Undo de preset remove apenas tracks criados pela transação; Redo restaura mesma semântica; nova ação após Undo limpa Redo.
- Snap em time markers, habilitado/desabilitado, teclado e foco; nenhum render ocorre durante apenas a seleção de um key.

### C) Migração

- Cena v1 com `frames=1` utiliza somente `camera.from` e não duplica frame 0.
- v1 com 120 frames preserva `smoothstep` em 0, 30, 60, 90, 119, além de **todos os frames** no teste golden.
- Rotas com `start=end` são degrau instantâneo; fade `start=end` vira opacidade completa no frame especificado.
- longitude de +179 até −179 preserva menor arco do legado, sem salto de 358°.
- Cores, geometrias e IDs são bitwise iguais nas estruturas copiadas (exceto canonicalização controlada de números).

### D) Geografia e camera

- Projetar + inverter coordenadas de Brasília em zoom 3.4 e bearing 45° volta ao original com erro ≤1e−5 grau.
- Fit bounds com lon 179° / -179° usa 2° de largura (aproximado), não 358°.
- 4 keyframes de câmera distintos produzem poses exatas e ordem declarada; uma pausa Hold não desloca câmera.
- Zoom ancorado mantém ponto dentro de 1 px em FULL HD/4K (dependendo da precisão numérica declarada).

### E) Paths e território

- Polygon com hole continua vazado em Fill Reveal; MultiPolygon não preenche buracos ou oceanos.
- `trimStart=0,trimEnd=0` desenha zero caminho; `0,1` desenha caminho completo; `start>end` rejeitado.
- MovingObject no progresso 0, .5, 1 está nas posições esperadas por comprimento de arco; heading segue tangente.
- Morph com paths de comprimentos diferentes permanece finito e estável; reamostragem não muda origem/destino nos endpoints.
- Parent A→B→C correto; ciclo C→A rejeitado antes do render. Expressão com `eval`/rede/identificador desconhecido rejeitada.

### F) Export e Fusion

- Render em 24-frame batches preserva a mesma sequência de PNG que render monolítico (hash do conteúdo, após fixar versão do encoder).
- Cancel em frame 37 após concluir lote 24 não marca status COMPLETE; retomar sem diferenças gera frames restantes.
- Reimportar export v1 de 4 dígitos e v2 de 6 dígitos respeita manifest e não mistura padrões.
- `sceneSnapshotHash` divergente bloqueia resume; preview diferente do export é regressão P0.
- Lua falha após criar clipe retorna PARTIAL; ao importar novamente requer confirmação e nova tentativa independente.
- Native adapter com capability ausente cai para PNG explicitamente; nunca reporta keyframes nativos editáveis quando não são.

## E2E Windows/Resolve real (obrigatório em releases)

1. Instalar plugin a partir de build limpa; abrir Resolve Studio; criar projeto/timeline descartáveis.
2. Abrir cena v1 e confirmar preview de 0, meio e último frame; salvar como v2 sem sobrescrever original.
3. Criar 4 posições de câmera, editar zoom, ajustar Bézier; salvar/reabrir e comparar keyframes.
4. Inserir dois territories, uma rota e um marcador móvel; render 120 quadros; importar no Fusion.
5. Abrir página Fusion: verificar Loader/Merge/MediaOut, sequência temporal, dimensões, alpha; página Edit reproduz 5s sem frames faltantes.
6. Deletar clipe e reinserir mesmo export pela UI com confirmação; nenhum re-render desnecessário; estado dos jobs independente.
7. Provocar falha parcial em timeline descartável; verificar PARTIAL, desbloqueio da composição e aviso correto.
8. Testar cancelamento e retomada de export longo; preservar projeto/PNG de export anterior.

Se algum desses E2E não puder rodar, marcar release como **preview/experimental**; não declarar certificado.

## Composição do relatório de aceite

`release`, `commit`, `node`, `SO`, `Resolve version`, `tests node count`, `tests Lua count`, `contracts count`, `coverage`, `golden diffs`, `perf`, `E2E screenshots`, `bugs abertos`, `risco`, `decision`. Contagem de testes não é apresentada sem logs acessíveis.


---

<!-- Origem: 08_ROADMAP_AND_AGENT.md -->

# 08 — Roadmap de implementação e instruções para agente

## Instrução mestre (para Codex)

> Você é o engenheiro responsável por evoluir o **CartoRig** em um editor cartográfico com keyframes profissionais. Antes de alterar código, leia integralmente os documentos 01–10, os contratos e a matriz TDD. Compare os contratos com a branch `main` no SHA indicado no README. Não modifique documentos/código sem justificar desvios. Comece por uma branch de desenvolvimento, execute os testes legados e entregue PRs pequenos. Para cada PR: escreva testes, observe falha, implemente a alteração mínima, execute regressões, documente resultados e preserve as exportações anteriores. Não declare compatibilidade de Fusion Native sem teste no Resolve real.

**Branching:** `feature/animation-core`, `feature/keyframe-ui`, `feature/camera-motion`, `feature/geo-motion`, `experimental/fusion-native`. Em geral, cada PR deve ser reviewable (preferencialmente <800 linhas funcionais de mudança, exceto fixtures/snapshots). Nunca publicar direto na branch principal sem revisão/autorização do responsável pelo repositório.

## Dependency graph

```text
Baseline QA (0.2.9)
   ↓
Scene schema v2 + migration + validScene (PR-01)
   ↓
Evaluator/interpolation + property registry (PR-02)
   ↓
Renderer adapter + legacy golden equivalence (PR-03)
   ↓
Command history / keyframe operations (PR-04)
   ↓
Timeline/editor + auto-keyframes + snap (PR-05)
   ↓ [v0.3.0 release gate]
Graph Editor / retime (PR-06) ─┐
Geographic camera math (PR-07)├─> Camera UX/presets (PR-08)
Long-form renderer (PR-09) ────┘
   ↓ [v0.4.0 release gate]
Territory animation/effects (PR-10)
Route path editor/trim/movers (PR-11)
Groups/constraints/loops (PR-12)
Expressions + rich presets (PR-13)
   ↓ [v0.5.0 release gate]
Fusion capability probe (PR-14)
Native converter (PR-15)
Windows E2E/compatibility (PR-16)
   ↓ [v0.6.0 experimental]
```

## PRs e gates

| PR | Entrega | Testes mínimos | Bloqueante? |
|---|---|---|---|
| 00 | Auditoria base/fixture e logs de baseline | `npm test`, `test:lua` no main | Sim |
| 01 | JSON Schema v2, validação semântica, migrador v1 | 100% casos MIG/contrato | Sim |
| 02 | Evaluator puro, easing e registry | tests KF-01/05/06, properties | Sim |
| 03 | Adapter SVG/preview/export com engine único | equivalência SVG/PNG e regressão render | Sim |
| 04 | Operações Undo/Redo e auto-keyframe | comandos + transações + conflitos | Sim |
| 05 | Timeline UI, snap, teclado e inspector | UI unit + E2E local, acessibilidade | Sim, libera v0.3 |
| 06 | Graph Editor e retime | curvas, handles, retiming | Sim, libera v0.4 |
| 07 | Câmera multiponto/Bézier/bearing/fly-to | geo numeric + visual antimeridiano | Sim |
| 08 | Camera Follow, fit bounds e presets | constraints, fly-to, anchors | Sim |
| 09 | Export longo, streaming, resume/cancel | IPC/disk/crash/canary | Sim |
| 10 | Animações territory, fill, stroke, glow | alpha/golden | Sim, libera v0.5 |
| 11 | Rotas multiponto e objetos móveis | LUT, trim, path, morph | Sim |
| 12 | Parent/grupo/stagger/loops | DAG, temporal | Sim |
| 13 | Expressions seguras/presets | AST, budget, segurança | Sim |
| 14 | Fusion probe e relatório de suporte | Lua + Windows Resolve real | Sim |
| 15 | Export nativo por propriedades suportadas | paridade temporal e visual | Sim |
| 16 | E2E Fusion e fallback em 20/21 | Windows real + regressão | Sim, libera v0.6 |

## Estratégia TDD

1. Copiar `tests/*.contract.test.cjs` desta documentação para `/tests` do projeto e adaptar somente imports, antes de implementar o módulo-alvo.
2. Criar `npm run test:contracts` e comprovar falhas por módulo inexistente ou comportamento não implementado (RED); não pular testes para deixá-los verdes artificialmente.
3. Implementar fonte `plugin/animation` pura, adicionar builders de cena de teste e fixtures de migração.
4. Executar contratos até GREEN, observar cobertura e adicionar testes de regressão para bugs reais.
5. Conectar engine ao render/UI por adapter; remover cálculos antigos somente depois da equivalência golden.
6. Empacotar bundle para Electron com versão fixada; validar integridade do instalador e permissões de scripts Lua.
7. Só marcar feature como `done` após `01_PRODUCT_REQUIREMENTS`, matriz CSV e critérios E2E pertinentes serem atendidos.

## Regras de engenharia

- Não reescrever UI/renderer inteiro antes de validar engine. Primeiro o domínio puro e migração.
- Não implantar 36.000 frames sem export em lotes, arquivos atômicos e estudo de disco.
- Não misturar conceitos de Bézier temporal (Graph Editor) e Bézier espacial (câmera/rota).
- Não criar função `eval` para expressions nem render interativo que dependa de relógio; animação determinística sempre.
- Não adicionar assets de satélite/terreno 3D neste roadmap; precisam de projeto específico de licenças e render.
- Não ocultar fallback para PNG sob nome "Fusion Native".
- Tratar upgrades de schema, export manifests e scripts Lua como produtos versionados com compatibilidade retroativa.
- README deve documentar Keyframe Engine, atalhos, migração e limitações por release.
- Nunca gravar em arquivos do usuário sem confirmação; não deletar exports automaticamente.

## Definition of Done — cada feature

- Especificação e feature ID mapeados a issue/PR.
- Unit tests positivos/negativos/borda e coverage conforme `07_TEST_STRATEGY.md`.
- Golden render para mudanças visuais, tests UI para interações.
- Nenhum regression test legado falhou.
- Sem mudança silenciosa em serialização ou output de v1.
- Documento de arquitetura e changelog atualizados.
- Teste no Resolve real quando a feature afeta insertion/TIMELINE ou Fusion Native.
- Evidência de QA com commit SHA e versões de ferramentas anexada ao PR.

## Roadmap de release sem data arbitrária

Versões são **marcos funcionais**, não datas prometidas. Ao concluir um release, manter branch main estável, publicar tags somente após os gates e preferir release notes verificáveis a números de testes sem log.


---

<!-- Origem: 09_DECISIONS_AND_RISKS.md -->

# 09 — Decisões de projeto, riscos e pendências

## Decisões congeladas para a primeira implementação

| ADR | Decisão | Justificativa / consequência |
|---|---|---|
| ADR-01 | **Engine própria**, independente de Fusion e de DOM | Preview e PNG verificáveis; fácil testar e portar |
| ADR-02 | **Scene schema v2** + migração automática de v1 | Não quebrar projetos antigos; cena é source of truth |
| ADR-03 | Frames inteiros base zero | Determinismo de export e compatibilidade com edição de vídeo |
| ADR-04 | Easing em segmentos com `interpolation` no key da esquerda | Semântica previsível e serialização simples |
| ADR-05 | Tracks individuais por `target + property` | Zoom/posição, color/opacity independentes |
| ADR-06 | Temporização Bézier e paths Bézier separados | Evita confusão entre velocidade e trajetória |
| ADR-07 | Undo/Redo por transações atômicas | Segurança de múltiplos keys/objetos |
| ADR-08 | Renderer SVG atual como backend primário | Minimiza risco durante mudanças do motor |
| ADR-09 | Fusion Native só após prova de capacidade real | Histórico de incompatibilidade de proxies JS/Tool |
| ADR-10 | Suportar modo offline | Sem dependência operacional de serviços externos |
| ADR-11 | Preserve `nodeIntegration:false`, CSP e validação IPC | Segurança da aplicação |
| ADR-12 | Sem exigência de Node no Windows do usuário final | Distribuir bundle já compilado |

## Questões técnicas que exigem spike/decisão antes do PR relevante

1. **Bézier temporal:** aceitar y fora de 0..1 para overshoot, mas obrigar clamp de opacity e de outras propriedades. Implementador deve provar comportamento de `cubicBezier` em extremos x1/x2.
2. **Interpretação de cor:** sRGB linear-light no motor novo ou interpolation `legacySrgb` em importações. Documentar screenshots de comparação.
3. **Rotas espaciais:** controles em graus ou coordenadas projetadas? O contrato inicial em graus deve ter conversão explícita para Mercator numérico estável.
4. **Câmera unwrapped:** política de longitude e empate ±180 deve preservar o algoritmo antigo no modo legacy; new `shortest/east/west` deve ter testes.
5. **Limites de frames:** suportar até 36.000 significa gerenciamento de disco, RAM e export em lotes; não substituir `MAX_FRAMES` isoladamente.
6. **Versionamento dos outputs:** atualização de pattern de `map_0000` (v1) para `map_000000` (v2) exige reader de ambos os manifests no export-manager e Lua.
7. **Erro de expressão:** preferir falhar antes de export, em vez de renderizar com valores arbitrários; decidir UI de diagnóstico por track.
8. **3D:** pitch/globo/terrain não foram aprovados neste pacote; não inferir suporte só porque MapLibre tem API.
9. **Escopo do Fusion Native:** medição direta de pontos keyframáveis na versão instalada do Resolve antes de documentar quais propriedades funcionam.

## Riscos prioritários

| Risco | Impacto | Mitigação |
|---|---|---|
| Divergência visual com cenas v1 | Alto | Golden por frame, adaptador legado, formatos novos não sobrescrevem v1 |
| Regressão de export e Fusion | Alto | Interface de export preservada, testes Node/Lua e E2E Windows |
| Engine temporal embutido no DOM | Alto | Módulos puros, interface de avaliação, compiler de bundle |
| Perda de performance em 4K/long-form | Alto | Streaming, caches, cancelamento, quotas e medições |
| Corrupção de projetos ao salvar | Alto | Save-as/migration + JSON schema + escrita atômica |
| Curvas Bézier instáveis | Alto | Inversão numérica testada, limites explícitos, property tests |
| Ciclos de constraints/expressions | Alto | DAG e validação antes do render |
| Inconsistência em antimeridiano | Alto | Normalização unwrapped e testes geográficos |
| Lua/Fusion Native indisponível | Médio-Alto | PNG fallback com mensagem de capacidade |
| UI saturada para muitos tracks | Médio | Virtualização e agrupamento |
| Fontes/cores divergentes em runners | Médio | Browser versionado, fontes conhecidas, golden tolerância controlada |

## Política de escopo

Nenhum projeto externo, canal ou marca editorial integra o produto. O CartoRig é uma ferramenta independente, compatível com outras futuras integrações, e seus contratos/projeto não precisam de referências a identidades editoriais privadas.

O limite desta documentação é a **especificação**. Tests TDD no pacote representam contratos de comportamento futuro, não resultados de testes de features ainda inexistentes.


---

<!-- Origem: 10_UI_AND_ACCESSIBILITY.md -->

# 10 — UI/UX, acessibilidade e fluxo de animação

## Objetivo

Transformar o slider de frame e os controles `from/to` atuais em uma timeline visual de animação sem exigir conhecimento de Fusion. O usuário precisa perceber rapidamente **o que será animado, onde há keyframes e quando cada animação acontece**.

## Wireframe textual — proposta

```text
┌────────────────────────────── CartoRig ──────────────────────────────────────────────┐
│ [Abrir] [Salvar] [Exportar] [Fusion]         Projeto: Brasil × Venezuela    24 fps  │
├─────────────────────┬────────────────────────────────────────────────────────────────┤
│ OBJETOS             │ PREVIEW CARTOGRÁFICO                                          │
│ ▾ Câmera            │                                                                │
│   • Posição         │                           [Mapa]                               │
│   • Zoom            │                                                                │
│   • Rotação         │                                                                │
│ ▾ Territórios       │                                                                │
│   ▾ Brasil          ├────────────────────────────────────────────────────────────────┤
│      • Cor          │  TIMELINE  [|◀] [▶] [▶|] [◈] [Auto Keyframe] [Snap] [Undo/Redo]  │
│      • Opacidade    │   Frame 0      30      60      90     120      150      180    │
│ ▾ Rotas             │   camera.lon:    ◆─────────◆────────────◆                  │
│   ▾ Caracas–Brasília│   camera.zoom:   ◆────◆─────────────────◆                  │
│      • Progresso    │   Brasil.alpha:       ◆──◆─────────────────◆                  │
│ ▾ Marcadores        │   Route.progress:         ◆──────────────────◆                │
├─────────────────────┤────────────────────────────────────────────────────────────────┤
│ INSPECTOR           │ GRAPH EDITOR (opcional, v0.4): curva de valor/velocidade       │
│ Valor atual         │                                                                │
│ Easing [Ease InOut] │                                                                │
│ [◈ Add Key]         │                                                                │
└─────────────────────┴────────────────────────────────────────────────────────────────┘
```

## Histórias de interação

### Fluxo 1 — Criar keyframes de câmera

1. Selecionar `Câmera > Zoom` e frame 0; digitar 3.5 e clicar diamante `Add Key`.
2. Ir ao frame 48, ativar Auto Keyframe e digitar 5.2; sistema adiciona frame 48.
3. Ir ao frame 80, digitar 4.1; aparecem 3 keys e o caminho do valor de zoom no Graph Editor (v0.4).
4. Clicar em key e alterar easing sem mexer em longitude/latitude.
5. Salvar, reabrir e encontrar os três keys idênticos. Export de PNG produz o valor certo em frame 48.

### Fluxo 2 — Importação e migração de cena antiga

1. Abrir v1 e exibir aviso discreto “Esta cena será convertida para o novo sistema de animação em memória; original será preservado”.
2. Timeline mostra keys convertidos da câmera, fade e rota. Preview continua idêntico em todos os frames.
3. Salvar pede novo caminho/Save As, com opção de backup; nunca sobrescreve sem escolha explícita.

### Fluxo 3 — Reutilizar animação

1. Selecionar keys de um país, copiar, selecionar outro país e colar no frame 90.
2. Mostra preview com offsets e erros por tipo incompatível; transação única.
3. `Ctrl+Z` reverte apenas essa operação e mantém seleção previsível.

### Fluxo 4 — Caminho de câmera e rota avançada

1. Clicar em mapa na visualização para adicionar waypoint e arrastar alças Bézier.
2. No Graph Editor controlar **velocidade temporal**, sem alterar geometria espacial.
3. Alterar trajetória espacial não muda os frames de keyframe; editar timing não move pontos geográficos.

## Estados da interface

- `idle`: cena carregada, sem render e sem modal.
- `editing`: arrastando keyframe/handle; preview usa estado otimista e faz commit somente no release.
- `rendering`: alterações de cena bloqueadas ou tratadas como novo draft após snapshot; progresso por lote.
- `validating`: abrir/salvar/importar, spinner/progresso e diagnóstico sem travar.
- `error`: mensagem com código, alvo e ação reparadora; não limpar estado editável.
- `incompatible`: scene schema desconhecido abre somente read-only com opção de backup; sem sobrescrever.

## Atalhos propostos (Windows; Linux/macOS com modificador equivalente)

| Ação | Atalho |
|---|---|
| Play/pause | Espaço (com foco fora de input de texto) |
| Próximo/anterior frame | Seta direita/esquerda |
| Próximo/anterior keyframe | Alt+direita/esquerda |
| Adicionar/atualizar keyframe | K |
| Deletar keyframe selecionado | Delete |
| Copiar/colar keys | Ctrl+C / Ctrl+V |
| Undo/Redo | Ctrl+Z / Ctrl+Y |
| Seleção múltipla | Shift+click / Ctrl+click |
| Selecionar todos keys de track | Ctrl+A com foco na timeline |
| Zoom temporal | Ctrl+roda do mouse ou botões +/- |
| Snap temporariamente desativado | Alt durante arraste |

## Acessibilidade

- Todos os botões possuem `aria-label` significativo; keyframes têm descrição acessível de objeto/propriedade/frame/valor/easing.
- Navegação por teclado funcional, foco visível e ordem lógica; não depender apenas de cor para distinguir keyframes.
- Animação de preview respeita preferências de redução de movimento da interface quando possível, **sem alterar export**.
- Feedback para invalid keys, trimStart>end e frames fora do range é apresentado antes de salvar, com foco no campo.
- Opacidade, escalas e curvas têm valor numérico editável, evitando controles exclusivamente gestuais.
- UI não deve abrir popups inesperados ao criar nós/alterar tracks.

## Responsividade e performance

- Projeto com ≥100 tracks usa lista virtualizada sem perder seleção/foco/scroll position.
- Scrubbing renderiza preview com qualidade adaptativa; export é sempre full quality e frame-accurate.
- Debounce somente em render de preview, **nunca** na persistência de command history; easing e key moves são determinísticos.
- Ferramenta permanece usável com janela mínima existente do plugin, oferecendo painéis colapsáveis e resize horizontal.


---

<!-- Origem: SPEC_QA_REPORT.md -->

# CartoRig — Relatório de consistência das especificações v1.0

**Data:** 2026-11-05  
**Baseline auditada no GitHub:** `gabrielbugarelli/cartorig`, `main`, SHA `31f9069efd75d06f0198e655b1e2833e0109c1cd`.

## Validações concluídas

- 11 arquivos de documentação principal presentes, sem arquivos vazios.
- **42 funcionalidades** distribuídas entre KF-01–KF-10, CAM-11–CAM-18, GEO-19–GEO-27, ROUTE-28–ROUTE-36 e MG-37–MG-42.
- **129 cenários** únicos em `tests/TEST_MATRIX.csv`; cada feature possui ao menos um teste positivo e um de borda/erro.
- JSON Schema Draft 2020-12 validado e o exemplo de cena v2 validado sem erros pela biblioteca Python `jsonschema`.
- Sintaxe JavaScript verificada com `node --check` nos três arquivos de testes de contrato.
- Script `tests/validate_spec_package.py` executado com sucesso.
- Auditoria textual de identidade realizada no pacote documental, sem ocorrências indevidas nas expressões procuradas.
- Documentação acompanha decisões, riscos, migração, compatibilidade PNG/Fusion, E2E real e critérios de aceite.

## O que estes resultados **não** comprovam

- Nenhuma das 42 features foi implementada por este pacote; **não existe resultado de teste funcional dessas features**.
- Os arquivos `tests/*.contract.test.cjs` representam contratos TDD que vão falhar antes da implementação de `plugin/animation/index.js`.
- Os testes da versão atual do plugin foram estudados como baseline mas **não foram reexecutados como parte desta entrega de especificação**.
- Não houve instalação ou verificação no DaVinci Resolve Studio real.
- Não houve alteração no repositório nem criação de commit.

## Comando de verificação documental

```bash
python tests/validate_spec_package.py
node --check tests/animation-core.contract.test.cjs
node --check tests/migration.contract.test.cjs
node --check tests/operations.contract.test.cjs
```

## Próxima etapa permitida mediante autorização

Copiar os contratos para a árvore de testes do CartoRig em uma branch de feature, construir os módulos da API pública, executar TDD e os gates por release descritos no documento 08.


---

# Apêndice: contracts/animation-api.d.ts

```ts
// CartoRig Animation Core: desired public contract; no implementation in this package.
export type Interpolation = 'hold' | 'linear' | 'smoothstep' | 'legacySmoothstep' | 'cubicBezier';
export type ValueType = 'number' | 'longitude' | 'angle' | 'color' | 'boolean' | 'enum' | 'vector2' | 'pathProgress' | 'path';
export type TrackValue = number | string | boolean | readonly [number, number] | Record<string, unknown>;
export interface BezierTiming { x1: number; y1: number; x2: number; y2: number; }
export interface Keyframe<T extends TrackValue = TrackValue> {
  id: string;
  frame: number;
  value: T;
  interpolation: Interpolation;
  easing?: BezierTiming;
  meta?: Record<string, string | number | boolean | null>;
}
export interface Track<T extends TrackValue = TrackValue> {
  id: string;
  target: {objectId: string; property: string};
  valueType: ValueType;
  enabled?: boolean;
  locked?: boolean;
  preBehavior?: 'base' | 'first' | 'constant';
  postBehavior?: 'base' | 'last' | 'constant';
  preValue?: T;
  postValue?: T;
  keyframes: Keyframe<T>[];
}
export interface CameraPose { lon:number; lat:number; zoom:number; bearing:number; }
export interface CartoRigSceneV2 {
  version: 2;
  id: string;
  title: string;
  frames: number;
  fps: 24 | 25 | 30;
  countries: string[];
  territories: Record<string, unknown>[];
  markers: Record<string, unknown>[];
  routes: Record<string, unknown>[];
  camera: {base: CameraPose};
  style: {ocean:string; land:string; highlight:string; accent:string; border:string};
  animation: {
    version: 1;
    tracks: Track[];
    markers: {id:string; frame:number; label:string; color?:string}[];
    groups: Record<string,unknown>[];
    constraints: Record<string,unknown>[];
  };
}
export interface EvaluatedScene {
  frame: number;
  camera: CameraPose;
  objects: Readonly<Record<string,Readonly<Record<string, TrackValue>>>>;
}
export interface AnimationCommand {
  kind: string;
  [key: string]: unknown;
}
export interface CommandResult {
  scene: CartoRigSceneV2;
  inverse: AnimationCommand;
}
// Required CommonJS module: plugin/animation/index.js
export function validateScene(input:unknown):CartoRigSceneV2;
export function migrateSceneV1(scene:Record<string,unknown>):CartoRigSceneV2;
export function evaluateTrack(track:Track,frame:number,baseValue:TrackValue):TrackValue;
export function evaluateScene(scene:CartoRigSceneV2,frame:number):EvaluatedScene;
export function cubicBezierAt(u:number,easing:BezierTiming):number;
export function applyCommand(scene:CartoRigSceneV2,command:AnimationCommand):CommandResult;
export function invertCommand(sceneBefore:CartoRigSceneV2,command:AnimationCommand):AnimationCommand;
export function serializeScene(scene:CartoRigSceneV2):string;
export function unwrapLongitude(from:number,to:number,mode?:'shortest'|'eastward'|'westward'|'continuous'):number;
export function evaluateKeyframeSeries(track:Track,frames:number[],baseValue:TrackValue):TrackValue[];

```


---

# Apêndice: contracts/scene-v2.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://cartorig.local/schemas/scene-v2.schema.json",
  "title": "CartoRig Scene v2 (structural schema)",
  "type": "object",
  "required": [
    "version",
    "id",
    "title",
    "fps",
    "frames",
    "countries",
    "territories",
    "markers",
    "routes",
    "camera",
    "style",
    "animation"
  ],
  "properties": {
    "version": {
      "const": 2
    },
    "id": {
      "type": "string",
      "minLength": 1,
      "maxLength": 180
    },
    "title": {
      "type": "string",
      "maxLength": 120
    },
    "fps": {
      "enum": [
        24,
        25,
        30
      ]
    },
    "frames": {
      "type": "integer",
      "minimum": 1,
      "maximum": 36000
    },
    "countries": {
      "type": "array",
      "maxItems": 100,
      "items": {
        "type": "string",
        "minLength": 1,
        "maxLength": 20
      }
    },
    "territories": {
      "type": "array",
      "maxItems": 500,
      "items": {
        "$ref": "#/$defs/territory"
      }
    },
    "markers": {
      "type": "array",
      "maxItems": 500,
      "items": {
        "$ref": "#/$defs/marker"
      }
    },
    "routes": {
      "type": "array",
      "maxItems": 500,
      "items": {
        "$ref": "#/$defs/route"
      }
    },
    "camera": {
      "type": "object",
      "required": [
        "base"
      ],
      "properties": {
        "base": {
          "type": "object",
          "required": [
            "lon",
            "lat",
            "zoom",
            "bearing"
          ],
          "properties": {
            "lon": {
              "type": "number",
              "minimum": -180,
              "maximum": 180
            },
            "lat": {
              "type": "number",
              "minimum": -85,
              "maximum": 85
            },
            "zoom": {
              "type": "number",
              "minimum": 0,
              "maximum": 7
            },
            "bearing": {
              "type": "number",
              "minimum": -36000,
              "maximum": 36000
            }
          },
          "additionalProperties": false
        }
      },
      "additionalProperties": false
    },
    "style": {
      "type": "object",
      "required": [
        "ocean",
        "land",
        "highlight",
        "accent",
        "border"
      ],
      "properties": {
        "ocean": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "land": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "highlight": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "accent": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "border": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        }
      },
      "additionalProperties": false
    },
    "animation": {
      "type": "object",
      "required": [
        "version",
        "tracks",
        "markers",
        "groups",
        "constraints"
      ],
      "properties": {
        "version": {
          "const": 1
        },
        "tracks": {
          "type": "array",
          "maxItems": 2000,
          "items": {
            "$ref": "#/$defs/track"
          }
        },
        "markers": {
          "type": "array",
          "maxItems": 2000,
          "items": {
            "type": "object",
            "required": [
              "id",
              "frame",
              "label"
            ],
            "properties": {
              "id": {
                "type": "string",
                "minLength": 1,
                "maxLength": 128
              },
              "frame": {
                "type": "integer",
                "minimum": 0
              },
              "label": {
                "type": "string",
                "minLength": 1,
                "maxLength": 160
              },
              "color": {
                "type": "string",
                "pattern": "^#[0-9A-Fa-f]{6}$"
              }
            },
            "additionalProperties": false
          }
        },
        "groups": {
          "type": "array",
          "maxItems": 500,
          "items": {
            "type": "object"
          }
        },
        "constraints": {
          "type": "array",
          "maxItems": 2000,
          "items": {
            "type": "object"
          }
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false,
  "$defs": {
    "keyframe": {
      "type": "object",
      "required": [
        "id",
        "frame",
        "value",
        "interpolation"
      ],
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 128
        },
        "frame": {
          "type": "integer",
          "minimum": 0,
          "maximum": 35999
        },
        "value": {
          "anyOf": [
            {
              "type": "number"
            },
            {
              "type": "string",
              "pattern": "^#[0-9A-Fa-f]{6}$"
            },
            {
              "type": "boolean"
            },
            {
              "type": "array",
              "minItems": 2,
              "maxItems": 2,
              "items": {
                "type": "number"
              }
            },
            {
              "type": "object",
              "minProperties": 1,
              "maxProperties": 100,
              "additionalProperties": true
            },
            {
              "type": "string",
              "maxLength": 128
            }
          ]
        },
        "interpolation": {
          "enum": [
            "linear",
            "hold",
            "smoothstep",
            "cubicBezier",
            "legacySmoothstep"
          ]
        },
        "easing": {
          "type": "object",
          "required": [
            "x1",
            "y1",
            "x2",
            "y2"
          ],
          "properties": {
            "x1": {
              "type": "number",
              "minimum": 0,
              "maximum": 1
            },
            "y1": {
              "type": "number",
              "minimum": -2,
              "maximum": 3
            },
            "x2": {
              "type": "number",
              "minimum": 0,
              "maximum": 1
            },
            "y2": {
              "type": "number",
              "minimum": -2,
              "maximum": 3
            }
          },
          "additionalProperties": false
        },
        "meta": {
          "type": "object",
          "additionalProperties": {
            "type": [
              "string",
              "number",
              "boolean",
              "null"
            ]
          },
          "maxProperties": 12
        }
      },
      "additionalProperties": false
    },
    "track": {
      "type": "object",
      "required": [
        "id",
        "target",
        "valueType",
        "keyframes"
      ],
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 128
        },
        "enabled": {
          "type": "boolean"
        },
        "locked": {
          "type": "boolean"
        },
        "target": {
          "type": "object",
          "required": [
            "objectId",
            "property"
          ],
          "properties": {
            "objectId": {
              "type": "string",
              "minLength": 1,
              "maxLength": 180
            },
            "property": {
              "type": "string",
              "pattern": "^[a-zA-Z][a-zA-Z0-9]*$",
              "maxLength": 80
            }
          },
          "additionalProperties": false
        },
        "valueType": {
          "enum": [
            "number",
            "longitude",
            "angle",
            "color",
            "boolean",
            "enum",
            "vector2",
            "pathProgress",
            "path"
          ]
        },
        "preBehavior": {
          "enum": [
            "base",
            "first",
            "constant"
          ]
        },
        "postBehavior": {
          "enum": [
            "base",
            "last",
            "constant"
          ]
        },
        "preValue": {
          "anyOf": [
            {
              "type": "number"
            },
            {
              "type": "string",
              "pattern": "^#[0-9A-Fa-f]{6}$"
            },
            {
              "type": "boolean"
            },
            {
              "type": "array",
              "minItems": 2,
              "maxItems": 2,
              "items": {
                "type": "number"
              }
            },
            {
              "type": "object",
              "minProperties": 1,
              "maxProperties": 100,
              "additionalProperties": true
            },
            {
              "type": "string",
              "maxLength": 128
            }
          ]
        },
        "postValue": {
          "anyOf": [
            {
              "type": "number"
            },
            {
              "type": "string",
              "pattern": "^#[0-9A-Fa-f]{6}$"
            },
            {
              "type": "boolean"
            },
            {
              "type": "array",
              "minItems": 2,
              "maxItems": 2,
              "items": {
                "type": "number"
              }
            },
            {
              "type": "object",
              "minProperties": 1,
              "maxProperties": 100,
              "additionalProperties": true
            },
            {
              "type": "string",
              "maxLength": 128
            }
          ]
        },
        "keyframes": {
          "type": "array",
          "minItems": 0,
          "maxItems": 36000,
          "items": {
            "$ref": "#/$defs/keyframe"
          }
        }
      },
      "additionalProperties": false
    },
    "territory": {
      "type": "object",
      "required": [
        "id",
        "name",
        "type",
        "fill",
        "stroke",
        "opacity"
      ],
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 180
        },
        "name": {
          "type": "string",
          "minLength": 1,
          "maxLength": 150
        },
        "type": {
          "enum": [
            "country",
            "continent",
            "state"
          ]
        },
        "code": {
          "type": "string",
          "minLength": 1,
          "maxLength": 20
        },
        "parent": {
          "type": "string",
          "maxLength": 150
        },
        "geometry": {
          "type": "object"
        },
        "fill": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "stroke": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "opacity": {
          "type": "number",
          "minimum": 0,
          "maximum": 1
        },
        "start": {
          "type": "integer",
          "minimum": 0
        },
        "end": {
          "type": "integer",
          "minimum": 0
        }
      },
      "additionalProperties": true
    },
    "marker": {
      "type": "object",
      "required": [
        "id",
        "label",
        "lat",
        "lon"
      ],
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "label": {
          "type": "string",
          "maxLength": 120
        },
        "lat": {
          "type": "number",
          "minimum": -85,
          "maximum": 85
        },
        "lon": {
          "type": "number",
          "minimum": -180,
          "maximum": 180
        },
        "color": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "size": {
          "type": "number",
          "minimum": 0,
          "maximum": 100
        }
      },
      "additionalProperties": true
    },
    "route": {
      "type": "object",
      "required": [
        "id"
      ],
      "properties": {
        "id": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "from": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "to": {
          "type": "string",
          "minLength": 1,
          "maxLength": 120
        },
        "kind": {
          "enum": [
            "arrow",
            "line",
            "dashed"
          ]
        },
        "color": {
          "type": "string",
          "pattern": "^#[0-9A-Fa-f]{6}$"
        },
        "width": {
          "type": "number",
          "minimum": 0,
          "maximum": 100
        },
        "curve": {
          "type": "number",
          "minimum": -90,
          "maximum": 90
        },
        "path": {
          "type": "object"
        },
        "start": {
          "type": "integer",
          "minimum": 0
        },
        "end": {
          "type": "integer",
          "minimum": 0
        }
      },
      "additionalProperties": true
    }
  },
  "description": "Structural validation only. Semantic validation must check keyframe frames < scene.frames, unique IDs, property registry, type matching, cycles, and path geometry."
}

```


---

# Apêndice: contracts/scene-v2.example.json

```json
{
  "version": 2,
  "id": "scene:cartorig-example",
  "title": "Brasil e Venezuela — Keyframes",
  "fps": 24,
  "frames": 240,
  "countries": [],
  "territories": [
    {
      "id": "country:BRA",
      "name": "Brasil",
      "type": "country",
      "code": "BRA",
      "fill": "#2597BF",
      "stroke": "#2597BF",
      "opacity": 0.65
    },
    {
      "id": "country:VEN",
      "name": "Venezuela",
      "type": "country",
      "code": "VEN",
      "fill": "#D85E58",
      "stroke": "#D85E58",
      "opacity": 0.65
    }
  ],
  "markers": [
    {
      "id": "marker:caracas",
      "label": "Caracas",
      "lat": 10.4806,
      "lon": -66.9036,
      "color": "#F7CE81",
      "size": 5
    },
    {
      "id": "marker:brasilia",
      "label": "Brasília",
      "lat": -15.7939,
      "lon": -47.8828,
      "color": "#F7CE81",
      "size": 5
    }
  ],
  "routes": [
    {
      "id": "route:caracas-brasilia",
      "from": "marker:caracas",
      "to": "marker:brasilia",
      "kind": "arrow",
      "color": "#F7CE81",
      "width": 4,
      "curve": 22
    }
  ],
  "camera": {
    "base": {
      "lon": -61,
      "lat": -14,
      "zoom": 3.4,
      "bearing": 0
    }
  },
  "style": {
    "ocean": "#0D1E32",
    "land": "#243B52",
    "highlight": "#EFB26B",
    "accent": "#7AD6E0",
    "border": "#62809A"
  },
  "animation": {
    "version": 1,
    "tracks": [
      {
        "id": "track:camera.lon",
        "target": {
          "objectId": "camera:main",
          "property": "lon"
        },
        "valueType": "longitude",
        "preBehavior": "first",
        "postBehavior": "last",
        "keyframes": [
          {
            "id": "key:lon:0",
            "frame": 0,
            "value": -61,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lon:72",
            "frame": 72,
            "value": -66.9036,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lon:156",
            "frame": 156,
            "value": -70,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lon:239",
            "frame": 239,
            "value": -77.0365,
            "interpolation": "hold"
          }
        ]
      },
      {
        "id": "track:camera.lat",
        "target": {
          "objectId": "camera:main",
          "property": "lat"
        },
        "valueType": "number",
        "preBehavior": "first",
        "postBehavior": "last",
        "keyframes": [
          {
            "id": "key:lat:0",
            "frame": 0,
            "value": -14,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lat:72",
            "frame": 72,
            "value": 10.4806,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lat:156",
            "frame": 156,
            "value": 16,
            "interpolation": "smoothstep"
          },
          {
            "id": "key:lat:239",
            "frame": 239,
            "value": 38.9072,
            "interpolation": "hold"
          }
        ]
      },
      {
        "id": "track:camera.zoom",
        "target": {
          "objectId": "camera:main",
          "property": "zoom"
        },
        "valueType": "number",
        "preBehavior": "first",
        "postBehavior": "last",
        "keyframes": [
          {
            "id": "key:zoom:0",
            "frame": 0,
            "value": 3.4,
            "interpolation": "cubicBezier",
            "easing": {
              "x1": 0.42,
              "y1": 0,
              "x2": 0.58,
              "y2": 1
            }
          },
          {
            "id": "key:zoom:72",
            "frame": 72,
            "value": 4.5,
            "interpolation": "linear"
          },
          {
            "id": "key:zoom:156",
            "frame": 156,
            "value": 3.6,
            "interpolation": "cubicBezier",
            "easing": {
              "x1": 0,
              "y1": 0,
              "x2": 0.58,
              "y2": 1
            }
          },
          {
            "id": "key:zoom:239",
            "frame": 239,
            "value": 5.0,
            "interpolation": "hold"
          }
        ]
      },
      {
        "id": "track:territory.BRA.opacity",
        "target": {
          "objectId": "country:BRA",
          "property": "opacity"
        },
        "valueType": "number",
        "preBehavior": "constant",
        "preValue": 0,
        "postBehavior": "last",
        "keyframes": [
          {
            "id": "key:bra:10",
            "frame": 10,
            "value": 0,
            "interpolation": "linear"
          },
          {
            "id": "key:bra:40",
            "frame": 40,
            "value": 0.65,
            "interpolation": "hold"
          }
        ]
      },
      {
        "id": "track:route.progress",
        "target": {
          "objectId": "route:caracas-brasilia",
          "property": "progress"
        },
        "valueType": "pathProgress",
        "preBehavior": "constant",
        "preValue": 0,
        "postBehavior": "last",
        "keyframes": [
          {
            "id": "key:route:40",
            "frame": 40,
            "value": 0,
            "interpolation": "cubicBezier",
            "easing": {
              "x1": 0.42,
              "y1": 0,
              "x2": 0.58,
              "y2": 1
            }
          },
          {
            "id": "key:route:120",
            "frame": 120,
            "value": 1,
            "interpolation": "hold"
          }
        ]
      }
    ],
    "markers": [
      {
        "id": "tm:caracas",
        "frame": 72,
        "label": "Caracas",
        "color": "#7AD6E0"
      }
    ],
    "groups": [],
    "constraints": []
  }
}

```


---

# Apêndice: testes de contrato

Os três arquivos de teste em `tests/*.contract.test.cjs` são parte integral deste pacote, mas permaneceram separados para permitir execução futura. A matriz com **129 cenários** está em `tests/TEST_MATRIX.csv`.