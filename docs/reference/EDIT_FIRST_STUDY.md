# CartoRig Native — Investigação e Projeto de Engenharia **Edit-first**, DaVinci Resolve Studio 20

**Data-base do estudo:** 5 de novembro de 2026  
**Versão do documento:** EF-R1, pré-implementação  
**Plataforma-base:** DaVinci Resolve **Studio 20.x**, em particular alvo inicial de validação **20.3.2 no Windows 11 x64**; versões 21+ apenas como extensões opcionais e jamais como pressuposto.  
**Status:** estudo arquitetural com evidências documentais; nenhum plugin Edit-first foi compilado, instalado ou executado no host durante esta etapa. Não foram alterados repositórios do usuário.  
**Escopo herdado:** 465 `CR-RF`, 42 `KF/CAM/GEO/ROUTE/MG`, 20 `MAP`, 24 `ADV`, 129 casos da `TEST_MATRIX.csv`, requisitos P1/P2, segurança, licenciamento, persistência e experiências do CartoRig original.  
**Objetivo:** investigar viabilidade de realizar o trabalho cotidiano do plugin na **página Edit**, usando seu Viewer, Inspector, Effects Library, timeline e Keyframe/Curve Editor **do Resolve 20**, sem Electron, sem editor web sobreposto e sem depender de exportar PNG para editar.

> **Veredito preliminar com condições explícitas.** Um **CartoRig Edit-first nativo**, como gerador/effect OpenFX em C++ com dados geográficos próprios, é uma hipótese tecnicamente forte. A página Edit do Resolve 20 possui Curve Editor que aceita parâmetros OpenFX e o Resolve tem categoria de geradores/effects. **Não** está comprovado que todo o catálogo possa ser editado com seleção espacial completa, parâmetros independentes para objetos ilimitados e painel próprio dockável; essas são restrições de host. Um projeto correto precisa ter gates eliminatórios para interação OpenFX no Viewer, persistência e gestão de estado. A arquitetura final pode manter o Fusion como backend ou escape hatch, mas **não como rotina principal**.

## 0. Método, autoridade de fontes e significado de viabilidade

**Materiais de produto efetivamente usados:** catálogo `CartoRig_Catalogo_Integral_Requisitos_Funcionais_2026-11-05(1).md` (465 requisitos, registro do estado v0.3.3 candidata); `CartoRig_Especificacao_Completa_Animacoes_v1.0(1).md` (42 features e regras matemáticas); `TEST_MATRIX(1).csv` (129 linhas); `01-PRODUCT.md` a `12-FEATURE-PARITY-ROADMAP.md` presentes, exceto arquivos numerados não fornecidos; `CartoRig_Native_Especificacao_Mestra_2026-11-05.md`; `CartoRig_Native_Estudo_Engenharia_PreImplementacao_2026-11-05.md`. As duas últimas são projetos derivados e **não evidências independentes de compatibilidade do SDK**. Divergências de nome (`Neo Atlas Maps`/`CartoRig`), formato `.namap`/`.cartorig` e arquitetura (Electron/Fusion/Edit) são resolvidas explicitamente abaixo, não apagadas.

**Evidência:** `D20` = documentação oficial do Resolve/Fusion 20; `OFX` = especificação OpenFX (capacidade do padrão, não prova do host); `BASE` = pedido/requisito dos arquivos; `ENG` = proposta de engenharia demonstrável; `POC` = comportamento dependente de execução no Resolve 20; `LIC` = condicionante legal ou de licença. **Sem `POC` aprovado, a palavra 'viável' significa 'há caminho de engenharia plausível', e não 'funciona hoje'.**

**Definição de Edit-first:** usuário arrasta `CartoRig Map`/`CartoRig Map Overlay` para a timeline na Edit; configura scene/dados pelo Inspector e onde suportado pelo Viewer; anima propriedades no Keyframe/Curve Editor da Edit; vê o resultado no Viewer e renderiza pelo Deliver. O Fusion pode processar internamente, mas o usuário não precisa abrir a página Fusion para tarefas rotineiras. `Edit-first` **não exige** 100% de cada elemento da UI em um único Inspector nem autoriza simular um painel interno com truques de janela do Windows.

**Não confundir:** (1) gerador OFX independente de `MediaIn`; (2) efeito OFX aplicado a um clipe com imagem de entrada; (3) Fusion Generator publicado na Edit; (4) uma Fusion Composition comum; (5) aplicativo Workflow Integration Electron. Os objetos têm ciclo de vida, animação e capacidades de UI diferentes.

## 1. Resultados de pesquisa que alteram a escolha tecnológica

### 1.1 O Resolve 20 já tem Curve Editor nativo na Edit

O **DaVinci Resolve 20 New Features Guide**, páginas impressas 16–22, descreve nova interface Keyframe/Curve na Edit e Cut, edição de valores e tempo, handles Bézier, seleção de curvas e grupos, snap e parâmetros OpenFX/ResolveFX em `Display Selected Parameters`. Portanto **não é necessário recriar o editor de curvas HTML** para parâmetros que o OFX expose corretamente. Uma ressalva fundamental: a documentação prova o editor de curvas para parâmetros keyframable do host, **não** prova que trilhas arbitrárias guardadas em um JSON interno apareçam nesse editor, nem garante equivalência completa com o Spline Editor do Fusion.

### 1.2 O Resolve 20 suporta apresentação de Fusion Generators na Edit

O **Fusion 20.3 Reference Manual**, capítulo 'Node Groups, Macros, and Fusion Templates', descreve criar uma composição, gerar Macro, salvar no diretório `Fusion/Templates/Edit/Generators`, disponibilizar na Effects Library e expor parâmetros selecionados no Inspector da Edit. É um caminho **comprovado documentalmente** para fachada Edit-first com motor Fusion interno. O modo editável em profundidade continua dependendo do que a macro publica; uma macro não equivale a UI GIS dinâmica.

### 1.3 OpenFX define geradores, filtros, animação e overlays, mas o host decide suporte

O OpenFX Image Effect padrão prevê `Generator` (sem input obrigatório), `Filter` (uma imagem de entrada), `Transition` e outros contextos; a aplicação anfitriã anuncia os contextos suportados. A página Edit do Resolve aceita plugins OpenFX e possui controles de Viewer para plugins que os oferecem. A especificação `OfxInteract` define overlays e widgets customizados, **mas** condiciona sua disponibilidade às propriedades de suporte do host. `DrawSuite`/interact V2 depende da versão de API/suites disponibilizadas. Um plugin **nunca** deve assumir essas suites pelo fato de existir um cabeçalho moderno no SDK.

### 1.4 Parâmetros OFX NÃO são arbitrariamente criados durante uma sessão

`OfxParameterSuiteV1::paramDefine()` é permitido nos callbacks de descrição; os parâmetros são comuns às instâncias do plugin. Isso impede criar um novo slider do Curve Editor para cada novo país adicionado à mesma instância, em tempo de execução. O projeto precisa escolher entre: (A) parâmetros nativos fixos + scene graph interno; (B) instâncias separadas por objeto; (C) slots de objetos definidos antecipadamente; (D) pequenos controles expostos por macro com backend Fusion; ou uma combinação consciente dessas estratégias. O efeito visual pode ser completo mesmo quando a **edição nativa individual de parâmetros ilimitados** não é.

### 1.5 Persistência e GPU dependem de contratos de host

O OpenFX define parâmetros persistentes que o host salva/recarrega e render por tempo solicitado, com segurança de chamadas concorrentes e regiões parciais. Isso não valida automaticamente tamanho máximo de `string params`, importações enormes, suporte a formatos HDR, desenho de overlay ou OpenCL na instalação específica. Uma GPU AMD não transforma automaticamente um plugin OFX em plugin acelerado: disponibilidade de buffers/suites e interoperabilidade precisam ser constatadas.

## 2. Matriz de capacidade: host Resolve 20 vs hipótese de produto

| Capacidade | Evidência | Interpretação exata | Plano de contingência |
| --- | --- | --- | --- |
| Effects Library: mapa arrastável | D20/POC | Fusion Generator documentado; testar OFX Generator também | Generator Macro + OFX Filter sobre plano transparente se necessário |
| Inspector Edit com parâmetros | D20 | OFX/Fusion publicado; layout e widgets sujeitos ao host | Controls nativos estáveis e agrupados |
| Keyframe Editor e curvas Bézier na Edit | D20 | Parâmetros OFX marcados animáveis; certos tipos podem não animar | Usar números/posições/cores; fallback interno sinalizado |
| Overlay do plugin no Viewer Edit | OFX/POC | Suporte anunciado pelo host; eventos reais a testar | Inspector numérico + ferramenta de seleção alternativa |
| Mouse: picking de países | ENG/POC | Matemática implementável; entrada mouse/hit tests do host incertos | Busca geográfica sem picking como gate de UX |
| Inspector com lista dinâmica ilimitada | OFX: não | ParamDefine apenas no Describe | Scene graph + editor de seleção no Viewer; não prometer track por país |
| UI própria dockável na Edit | Não documentado | Não há contrato público geral de painel arbitrário | Sem painel; diálogos nativos pontuais apenas se permitidos |
| Cenas offline sem PNG intermediário | ENG/POC | Render OFX por frame é viável em princípio | Backend geográfico embarcado; fallback apenas diagnóstico |
| Gerenciar keyframes de objeto interno no Curve Editor | POC/limite | Só params OFX expostos podem aparecer | Instâncias/slots; aceitar limite ou replanejar |
| Import GeoJSON/CSV na interface Edit | POC | Padrão OFX não fornece file browser GIS completo | File parameter + importador interno ou diálogo nativo no Resolve |
| Atualizar cenas ao reabrir `.drp` | OFX/POC | Parâmetros persistem segundo padrão; dados grandes/sidecar a testar | Snapshot embutido quando viável + assets licenciados por manifest |
| Geometria 3D editável pela Edit | ENG/POC | OpenFX renderiza imagens 2D; engine 3D interna é possível | Renderer 3D in-plugin ou composição Fusion 3D oculta |
| Câmera e efeitos em 4K | ENG/POC | Depende de performance/cache/threads/GPU | Benchmarks com CPU primeiro e GPU opcional |
| Exportação Deliver e Color | D20/POC | Efeitos renderizam pela pipeline do host; alfa/cor específicos a testar | Validar 8/16/32f, alfa, HDR e render em background |

## 3. Comparação de arquiteturas e decisão preliminar

### 3.1 Arquitetura A — OFX Generator monolítico (candidata primária)

`CartoRig Map` é um plugin OpenFX compilado (C++), registrado como **Generator** caso o Resolve 20 aceite essa classe no ambiente Edit. O efeito calcula a cena localmente a cada tempo de render. A cena geográfica contém objetos variáveis, geometrias e curvas; parâmetros nativos fixos expõem `Camera Center`, `Zoom`, `Bearing`, preset, cor geral, visibilidade de grupos e controles de objeto selecionado. Cada render usa snapshot imutável de cena e valores OFX no tempo solicitado. **Vantagens:** uma instância por mapa, sem PNG, controle direto pela Edit, cópia/trim do clipe, bom cache, composição de todas as camadas no mesmo espaço de câmera. **Limites:** parâmetros individuais de N territórios/rotas no Curve Editor não surgem dinamicamente; edição espacial via overlay depende de host; o scene graph não deve viver apenas na memória do processo.

### 3.2 Arquitetura B — OFX Filter aplicado sobre clipe/Adjustment Clip

`CartoRig Overlay` é um plugin no contexto **Filter**; aceita frames de vídeo e compõe mapa/cartografia por alfa sobre a imagem. Mais apropriado para map overlays sobre filmagens, mini-mapas e inserções em material existente. **Atenção:** a transparência, máscaras, ordem de efeitos, dimensionamento, render cache e ajuste do próprio clipe do Resolve precisam ser testados. Um Filter sobre um fundo de cor é contingência caso o registro de Generator OFX não funcione no Resolve 20, **não uma evidência de equivalência**.

### 3.3 Arquitetura C — Fusion Generator + renderizador incorporado (candidata de risco reduzido)

Template da biblioteca da Edit contendo uma composição interna que invoca Fuse ou OpenFX e publica parâmetros relevantes no Inspector da Edit. Fluxo para o usuário permanece Edit-first, mesmo que o motor de imagens seja Fusion. **Vantagem:** a criação de Generator e o Inspector publicados são documentados para Fusion 20.3. **Limite:** controles acessíveis dependem da macro; objetos internos não se tornam automaticamente cada um um parâmetro do Curve Editor da Edit. É rota conservadora caso `OFX Generator` ou overlay direto falhe.

### 3.4 Arquitetura D — instâncias OFX por objeto sobre múltiplos clipes

Um Map Base e objetos separados (Route, Territory, Marker, Label) como Effects/Generators por track. **Vantagem:** cada instância tem parâmetros animáveis próprios na Edit. **Desvantagens graves:** sincronização exata de câmera/georreferência entre clipes e seus tempos locais, stacking, cortes/retime, cache, interdependência, opacidade/blends, gestão de dezenas de itens e transações da timeline. Sem contrato público de leitura consistente dos parâmetros animados de outra instância, não deve ser arquitetura padrão. Usar somente para layers independentes ou composições pequenas que comprovem sincronização.

### 3.5 Decisão condicionada

**Escolha preliminar:** A como motor+experiência padrão, B como modo Overlay e C como fallback de distribuição/Edit; D apenas para casos controlados. **Go/no-go** depende de um laboratório com Resolve Studio 20.x: visibilidade do OFX Generator na Effects Library, overlay do Viewer com eventos completos, animação real de tipos de parâmetros OFX no Curve Editor, persistência de dados e benchmark 4K. Se `A` falhar no registro, mas `C` passar e manter keyframes suficientes, preserva-se a meta **Edit-first** com Fusion oculto. Se a interação espacial for indisponível, o projeto permanece Edit-first para edição paramétrica, mas **não atende** integralmente à promessa 'editor GIS direto no Viewer'.

## 4. Arquitetura lógica proposta — produto Edit-first

```text
DA VINCI RESOLVE STUDIO 20 — PÁGINA EDIT
  Effects Library: CartoRig Map / CartoRig Overlay / CartoRig Route Presets
  Edit Timeline ── clipe CartoRig nativo
  Viewer ── frames de mapa e controles onscreen (se host suportar)
  Edit Inspector ── parâmetros publicados por OFX/Generator
  Keyframe + Curve Editor ── curvas dos parâmetros nativos expostos
        │
        ▼
[Host Adapter: OpenFX 1.x / Fusion Template opcional]
  - descoberta de host/contextos, lifecycle, params, caching, overlays
  - chamadas de render por tempo, threading, cancellation e ROI
        │
        ▼
[CartoRig Scene Runtime C++ ou core portável]
  - scene graph versionado, IDs geográficos, binding de propriedades
  - câmera/projeções + domínio de tempo + dependências sem ciclos
  - catálogo / asset manifest / importadores / consulta espacial
  - geometria, tesselação, simplificação topológica, labels
  - render 2D RGBA / dados 3D internos / qualidade e cor
        │
        ▼
[Saída ao host: pixels de resolução negociada + alfa/cores]
        │
        ▼
Deliver / cache / reabertura de projeto Resolve
```

**Separação obrigatória:** `geo-core` não sabe que existe Resolve; `scene-runtime` avalia frame e produz estados imutáveis; `renderer` recebe estado e tamanho; `ofx-host` adapta às suites e flags; `assets` gerencia dados; `ui-overlay` só usa callbacks do host e nunca escreve diretamente na cena durante `render()`. Todas as mutações passam por transação/undo quando documentado. O projeto deve compilar módulos com limites de ABI claros; não carregar DLL complexa dentro do callback de render a cada frame.

### 4.1 Artefatos por módulo

| Módulo | Responsabilidade | Gate de aceite |
| --- | --- | --- |
| core/scene | IDs, schema, migrations, objeto, grafo de dependências | Round-trip, diffs e snapshots |
| core/geo | CRS, WGS84, Mercator, geodésica, antimeridiano | Fixturas matemáticas e inversa |
| core/geometry | Polígonos, buracos, tessellation, topologia, LOD | Visual golden sem cracks |
| core/routes | Waypoints, arc-length, trim, morph, orientação | Distâncias e extremos exatos |
| core/animation | Curvas internas onde inevitáveis, constraints, timebase | Paridade frame a frame e mapeamento OFX |
| core/labels | Unicode shaping, colisão estável e prioridade | 50 labels e pan sem jitter |
| core/render | Pixéis/bit depth/alfa e blend por frame | 8/16/32f e render tile-safe |
| plugin/ofx | Lifecycle, contexts, params, overlays, cache/abort | Resolve20 host capability matrix |
| plugin/fusion-wrapper | Generator Macro de fallback e presets | Parâmetros na Edit sem aba Fusion |
| tools/import | GeoJSON/TopoJSON/CSV/DEM/shapes, validação | Erro seguro, hashes e licenças |
| assets/catalog | Datasets offline, índice busca, provedores licenciados | Sem rede e cache reprodutível |
| native-ui | Controles Edit + overlays, diálogos internos somente se necessário | Sem app web e sem docking inventado |
| qa/resolve20 | Projetos descartáveis, golden renders, capturas e logs | Matriz verificada em host real |

### 4.2 Contratos de domínio (sem implementar código)

`Scene {schemaVersion, sceneId, revision, timebase, output, cameraRig, objects[], layers[], styles, dataSources[], assets[], presetRefs[]}`. Cada objeto possui `stableId`, tipo, geometria/source, estilo, ordem z, parent, constraints, `nativeParamBindings` e/ou `internalAnimation`. Separar estado de cena (persistente) de estado UI (seleção, hover, viewport temporário), estado de render (buffers/cache) e estado de host (instância/identificadores de plugin). Não serializar ponteiros, handles, binários do Resolve ou segredos. Salvar alterações atômicas nos arquivos externos; versões futuras abertas read-only e sem sobrescrita.

`FrameContext {hostTime, frameRate, clipContext, renderScale, window, pixelAspectRatio, colorSpace, interactiveFlag}`. **Não** usar `Date.now()` nem reproduzir cronômetro próprio. O host pode solicitar frames fora de ordem, em diferentes threads ou escalas de preview; o render deve ser puro e idempotente para um estado fixo. Não recalcular um contador de frames incremental que dependa do frame anterior.

`GeometryFeature {datasetId, version, featureId, geom, bounds, topologyGroup, licenseRef}`; `GeoAnchor {lon,lat,optionalAltitude}`; `Route {waypoints, segmentType, distanceModel, trim, movingObject}`; `Camera {centerLonLat,zoom,bearing,pitch,projection}`. Criar IDs estáveis inclusive após importar arquivos e fazer join de indicadores. Câmera e todos os overlays devem utilizar a MESMA transformação, evitando deslocamentos em zoom/pan.

`EditBinding {pluginInstanceIdentity, sceneId, sceneHash, exposedParamRegistryVersion, selectedObjectId, nativeCurveOwnership, sourceHashes}`. Campos de seleção são UI, não necessariamente propriedades animáveis. `internalAnimation` só é permitido quando explicitamente identificado ao usuário como **não editável no Curve Editor da Edit**; não rotular como 'keyframe nativo' o que vive em JSON.

## 5. Problema central: objetos ilimitados e parâmetros OpenFX estáticos

A viabilidade integral de Edit-first depende muito mais deste problema do que do desenho de polígonos. O OpenFX exige lista estável de parâmetros definida na descrição do efeito; o CartoRig pode adicionar 1, 50 ou 500 objetos após a instância existir.

### Estratégia P — parâmetros publicados estáveis

Publicar no Inspector de Edit **todas as propriedades globais relevantes**: cena e estilo, zoom, center XY/longitude/latitude, bearing, projection, opções de grade/mapa-base, trim master, opacidade global, intensidade FX. Marcar tipos numéricos como animáveis quando o host suporta. Esse grupo é completamente compatível com a filosofia Edit-first e usa o Curve Editor 20.

### Estratégia S — objeto selecionado com parâmetros-proxy (alto risco semântico)

Manter `selectedObjectId` não animável, controles estáveis `position`, `size`, `color`, `opacity`, `trim`, etc. O Inspector mostra o objeto selecionado por overlay ou lista. **Limitação crítica:** a curva nativa desses parâmetros pertence ao slot/proxy, não ao `objectId`. Trocar de seleção pode reaproveitar a mesma curva e mudar outros objetos, salvo se houver um mecanismo transacional comprovado de curvas por objeto. Portanto **não aprovar** o uso de um proxy animável compartilhado como solução universal de animação de todos os objetos. Usar parâmetros-proxy apenas para edição estática ou para slots com `binding` imutável durante a animação; para o restante, `internalAnimation` claramente explicitado.

### Estratégia F — slots predefinidos

Definir um número fixo de objetos (`Route01..RouteN`, `Marker01..MarkerN`) com séries de parâmetros nativos por slot; binding objeto→slot é persistente, nunca reciclado silenciosamente após chaves existirem. Facilita Curve Editor nativo para um conjunto limitado. **Problemas:** dezenas/centenas de controles no Inspector, gerenciamento de slots vazios, overhead de host e UX. Não prometer objetos ilimitados ou performance sem testar N=8, 16, 32 e 64. Separar presets de uso comum de cenas grandes.

### Estratégia I — instâncias e clipes independentes

Cada objeto usa uma instância OFX própria e suas curvas. Resolve a limitação de parâmetros por instância, mas **não** sincroniza automaticamente parâmetros de câmera e tempo entre clipes. Usar apenas em overlays realmente independentes, com cópia de câmera congelada e política de conflito: alteração do mapa-base invalida clones, exige atualização explícita. Testar copy/paste/trim/retime/vídeos em diferentes track FPS. Sem isso, não aprovar como mecanismo principal.

### Estratégia B — geometria animada internamente com export nativo reduzido

Deixar o scene graph gerenciar todos os `N` objetos e animá-los por dados internos. Expor somente curvas globais ou de um conjunto fixo, claramente descritas. Esta entrega preserva resultado visual, mas **não atende ao requisito de edição de todas as curvas por objeto no Curve Editor nativo**. Para fechar a lacuna, só considerar (a) abrir a página Fusion opcionalmente para curvas de objetos, (b) uma UI auxiliar autorizada, (c) número de slots finito aceito pelo usuário ou (d) contrato de host novo/documentado. O estudo rejeita prometer equivalência com base em 'slider mágico'.

**Decisão proposta:** P para global + F para conjunto editorial pequeno (limite validado) + B para cenas extensas; I opcional; S restrita a edição estática ou canal fixo. O produto deve manter `exposedNative=true/false` por propriedade e mostrar no manual a diferença.

### 5.1 Teste eliminatório de curva por objeto

Criar 2 países A/B, ambos com animação de cor independente, e uma única instância `CartoRig Map`. Sem abrir Fusion e sem segunda janela, criar 3 keyframes distintos para cada um e verificar **seis curvas identificáveis** no Curve Editor da Edit, reabrir projeto e continuar editando. Se a proposta só permitir editar uma curva proxy ou abrir editor próprio, o requisito de curvas ilimitadas **falha**, embora o renderer funcione. Repetir com 32 objetos para delimitar suporte de slots.

## 6. Viewer Interacts na Edit — geometria e UX

### 6.1 Pipeline do gesto

1. Host desenha frame por `render` e, se habilitado, invoca overlay `interactDraw`. O overlay deve usar transformação de coordenadas correta (pixels canônicos, aspect ratio, zoom do Viewer e DPI), não posição de janela presumida.
2. `penDown` executa `hitTest` em spatial index do frame de visualização: handles têm prioridade sobre labels, depois routes, marcadores e polígonos; se múltiplos geobjetos se sobrepõem, mostrar mecanismo de desambiguação (ciclo de seleção), não escolher silenciosamente.
3. `penMove` opera preview transitório, mantém captura se host permitir, desenha guides sem bloquear host. Quando câmera é arrastada, `screenToGeo` deve estar coerente com pitch/projeção.
4. `penUp` valida nova geometria ou parâmetro, emite mutação atômica e notifica o host do redraw e do valor paramétrico. `Undo` deve registrar uma operação, não uma por pixel/movimento.
5. O render de fundo e o editor não compartilham ponteiros mutáveis sem sincronização. Viewport overlay continua funcional sob 1280×720, 1440p, 4K, escala Windows 100/125/150%, zoom do Viewer e monitores múltiplos.

### 6.2 Gestos esperados

- Clique num território: selecionar o feature correto usando Polygon/MultiPolygon com buracos, prioridades e câmera atual. `Shift` para seleção múltipla **somente se** o host encaminhar modificadores de forma consistente.
- Arrastar câmera e zoom ao redor do cursor: converter screen ↔ geográfico, respeitar antimeridiano e bearing; edição com Auto Key apenas quando modo ativo.
- Adicionar marcador: duplo clique ou modo inserção dedicado; não sequestrar permanentemente o playhead ou interações nativas do Viewer.
- Desenhar rota: pontos/waypoints e alças espaciais Bézier, tangente visível, snap geográfico opcional, atalhos delete/escape previsíveis.
- Seleção de rótulo: mover anchor offset e travar posição; não editar conteúdo de texto por callback de pintura/Render.
- Tipos não presentes no overlay: edição por Inspector e/ou importador, com diagnóstico visível.

### 6.3 Por que o overlay é um gate e não premissa

A especificação OFX registra `kOfxImageEffectPropSupportsOverlays` e `kOfxParamHostPropSupportsCustomInteract`; um host pode não disponibilizar esses recursos ou limitar eventos/métodos. A documentação do Resolve comprova existência de efeitos com onscreen controls, mas **não** uma API oficial de editor GIS genérico dockável. Primeiro experimento deve registrar suites, callbacks penDown/Move/Up, coordenadas, modifiers, redesenho e Undo em **Edit**, não apenas Fusion ou Color. Se falhar, o produto só pode prometer edição via Inspector/ações nativas, ou mudar o requisito de 100% Edit sem UI auxiliar.

### 6.4 Interface de busca/árvore

Nenhuma API pública geral permite inserir uma árvore HTML/Qt arbitrária como painel dockável da página Edit. Opções são: (i) parâmetros fixos e seleção por índice/IDs conhecidos; (ii) overlay temporário leve se eventos e desenho permitirem — não substitui um browser com text input completo; (iii) diálogo de script dentro do próprio Resolve (não dockável, sujeito à API e ao foco); (iv) edição de catálogo em ferramenta opcional da página Fusion. **Não afirmar** que XML de OFX define combo de milhares de países que se atualiza dinamicamente; combos têm semântica e suporte dependentes da declaração e do host.

## 7. Motor cartográfico: algoritmos, performance e exatidão

### 7.1 Coordenadas e câmera base

Dados recebidos em `EPSG:4326` e ordem **[lon, lat]**; longitude normalizada para `[-180,180)`; latitude física `[-90,90]`, mas projeção Web Mercator fixa clamp `±85.0511287798066` somente na projeção. Centro da tela `(W/2,H/2)`; bearing positivo sentido horário visual (documentar). `worldSize=256×2^zoom`; `mercatorX=(lon+180)/360`, `mercatorY=0.5-ln((1+sinφ)/(1-sinφ))/(4π)`. Projeção e inversa devem compor até tolerância definida. Escolher a cópia de mundo mais próxima para antimeridiano; `lon 179°→-179°` percorre 2°, não 358°.

### 7.2 Enquadramento e paths

`fitBounds` deve lidar com pontos degenerados, largura/altura/padding, regions multipolygon, rotas, entidades em ambos lados do dateline e bearing. Fly-to usa trajetória espacial + zoom intermediário por uma função controlada, não simples linear lon/lat. `CameraFollow` resolve posição de target+offset no mesmo frame e não atualiza scene; speed constante usa arc-length em domínio geodésico ou tela conforme propriedade declarada.

### 7.3 Geometria e topologia

GeoJSON Polygon/MultiPolygon com buracos, ilhas, enclaves, winding e degenerados; validação de vértices e polígonos autointersectantes. Simplificação multi-LOD deve preservar fronteiras compartilhadas e evitar cracks; considerar topo compartilhada por dataset, não simplificar isoladamente duas bordas. Clipping em viewport/antimeridiano; sistema de tile spatial index (R-tree). Arquivo malicioso, NaN, número extremo, SVG/HTML injetado e path traversal devem ser rejeitados.

### 7.4 Rotas e movimento

Waypoints WGS84, distância geodésica, great-circle e curvas projetadas com `distanceModel` explícito; comprimento acumulado/normalização reprodutível em cada frame; `trimStart`/`trimEnd` independentes; moving object posicionado por comprimento, orientação pela tangente numérica robusta, trail por intervalo de tempo/arc-length; curvas de easing alteram a função de progresso, não distorcem a geometria-base. Morph de rotas exige correspondência e reamostragem robusta e política de fechamento/antimeridiano.

### 7.5 Labels e estilos

Strings Unicode, português com acentos, text shaping por biblioteca compatível e fontes instaladas; evitar rasterizar letras em bitmap fixo e ampliar; testar fallback de fonte. Collision detection com prioridades, hysteresis temporal para evitar salto em animação, override manual persistente. Estilos cores em RGBA com conversão sRGB/linear correta; transparência straight/premultiplied testada sobre preto e branco, sem halos.

### 7.6 Backend 2D, CPU e GPU

Fase POC: CPU C++ de qualidade (Skia ou render 2D equivalente, benchmarking/ABI/licença) com draw per frame e cache incremental; in-memory tessellation e tiles por zoom/dataset. OFX trabalha com `renderWindow` e `renderScale`; deve respeitar stride, pixel aspect, bit depth, ROI, fila fora de ordem, solicitações canceladas e concorrência. Só implementar GPU (OpenCL ou outra suite que o Resolve 20 efetivamente oferecer) depois do inventário de host; **não presumir CUDA** em RX 9070 AMD nem acesso direto à GPU usada pelo Resolve. Ter fallback CPU completo é requisito de confiabilidade. `Metal` não se aplica a Windows AMD. Render e caches são threadsafe; sem rede durante `render()`.

### 7.7 Cor e alfa

Estabelecer espaço interno linear premultiplicado **ou** outra convenção documentada e converter nas bordas; comparar sRGB, DaVinci YRGB Color Managed, Rec.709 e timeline HDR com PNG de referência; preservar alfa e máscaras. Não usar valores RGB numéricos como aparência final sem considerar gerenciamento de cor e o estágio do OFX na pipeline. Não assumir que uma tecnologia de cor adicionada no Resolve 21 está presente no Resolve 20.

## 8. Persistência, portabilidade, tempo e projeto Resolve

### 8.1 Snapshot da cena e fonte da verdade

Um efeito Edit-first precisa reabrir a partir do projeto Resolve e dos ativos geográficos autorizados. `kOfxParamPropPersistant` e parâmetros normais OFX fornecem persistência de controles; **não** é contrato de banco ilimitado. Três planos de dados: (1) parâmetros nativos pequenos e animáveis no projeto do Resolve; (2) representação canônica do scene graph, versionada, com hash; (3) datasets grandes, tiles/DEM/licenças via asset store com caminhos relativos ou identificadores content-addressed. Testar se é viável carregar `sceneSnapshot` compacto em string OFX persistente, seus limites e reabertura; se não, sidecar relinkable é obrigatório. Um caminho sidecar pode quebrar em outra máquina. O comportamento após `.drp`, backup, Project Library, duplicação e export deve ser testado.

### 8.2 Identidade e copy/paste

`SceneId` estável não é o mesmo que `InstanceId`: duplicar o clipe no Resolve deve criar nova instância, que poderá compartilhar dataset imutável, mas deve ter política explícita sobre editar o mesmo scene graph (linked copy) ou fork no primeiro commit. O editor não pode apagar assets compartilhados por outra cópia. `revision/hash` permite detectar edição concorrente e conflitos; snapshots e idempotency keys garantem ações repetidas sem duplicatas.

### 8.3 Timebase e curves

Adotar tempo racional do host (24, 25, 30 e, após avaliação, 23.976/29.97/59.94); converter `kOfxPropTime` sem arredondar cedo; definir `clipStart`, `clipLocalTime`, `projectTime` e retime. Trim de início desloca intervalos; speed change/retime e reverse devem dar comportamento previsível, sem salto de fly-to. Animar propriedades em OFX através de `paramGetValueAtTime` permite curvas host-owned; animações internas da cena usam o mesmo tempo de entrada. O renderer não depende de ordem de chamadas. Exportar e reabrir preserva limites de animação.

### 8.4 Undo e concorrência

Nunca manipular banco/arquivo do usuário dentro de callback de render; gestos de overlay fazem preview efêmero e commit atomizado. Verificar se o host oferece agrupamento de Undo para interações; se não, evitar criar 100 alterações paramétricas por arrasto e limitar transação a `penUp`, documentando comportamento. Operações import/export canceláveis com arquivos temporários e rollback no namespace. Nunca modificar timeline alheia sem consentimento.

### 8.5 Sistemas com múltiplas instâncias

Um `renderer` poderá ter caches globais read-only por dataset hash, mas **não** singleton mutável de cena selecionada. Render simultâneo de instâncias A/B deve usar snapshots separados. Testar duas timelines, render cache, UI thumbnail, playback e Deliver concorrentes. Evitar `static` C++ global de seleção ou camera compartilhada entre clipes.

## 9. Estratégia de recursos 2.5D/3D sob Edit-first

**Necessário separar três níveis distintos:**

- **2D:** projeção ortográfica/Mercator etc, coropléticos, linhas vetoriais, overlays e animações, tudo no render OFX.
- **2.5D:** câmera inclinada, extrusão e parallax com depth/malha própria; um OFX pode produzir **imagem final 2D**, mas não cria automaticamente objetos 3D editáveis em nós Fusion. Pitch, picking de edifícios e geometria oculta exigem ray-casting e depth buffer internos.
- **3D de verdade:** globo, DEM mesh, edifícios, sombra/atmosfera, LOD, import/controle de dados 3D. Duas estratégias: (A) renderizador 3D próprio integrado ao efeito OFX e render final em Edit; (B) Fusion 3D interno publicado por Generator, mantendo controle superficial na Edit. Nem A nem B garantem edição da topologia de cada edifício na interface Edit; seriam capacidades algorítmicas distintas das capacidades de interface.

**Renderizador OFX 3D próprio:** preservar profundidade, oclusão, iluminação e textos ancorados, com controles globais nativos no Inspector. Evitar dependência de OpenGL contexto host não garantido: comparar CPU fallback, OpenCL suportado e API gráfica apenas se contrato do Resolve 20 for observado. **DEM e satélite** exigem direitos de distribuição/caching para audiovisual; importar DEM/ortofotos licenciados e construir terreno com tiles LOD, normais, skirts para costuras. **Globo:** converter WGS84 em esfera/elipsoide, visibilidade/horizonte e transição entre projeções; não interpolar linearmente mapas 2D sem correção de tesselação/topologia.

**Decisão:** plataforma Edit-first não proíbe 3D real; apenas impede afirmar que os controles ricos de edição de malha do Fusion estarão todos disponíveis no Viewer/Inspector da Edit. Os requisitos `ADV-101..108` continuam no produto, mas com gates específicos de engine e UX 3D.

## 10. Catálogo de UX Edit-first — fluxos verificáveis

**Fluxo E1 — Inserção instantânea:** Edit > Effects Library > CartoRig > `CartoRig Map` > arrastar para V2. Clip próprio com transparência (sem arquivo PNG). Inspector `Source & Style`, `Camera`, `Territories`, `Routes`, `Markers`, `Animation`, `Data`, `Diagnostics` ou equivalente dentro dos controles possíveis no host. O nome, subgrupos e visibilidade dependem do API/Inspector e são itens de teste, não promessas de markup arbitrário.

**Fluxo E2 — Seleção Brasil e Venezuela:** ativar modo Select no efeito; clicar países no Viewer **se overlay POC passa**, com desambiguação; aplicar duas cores e salvar seleção. Se overlay falha, buscar pelo controle/diálogo interno oficialmente disponível; medir ações e aceitar que experiência difere do editor original. Nunca 'clicar Brasil' usando máscara falsa ou overlay que só mostra pixels sem selecionar ID.

**Fluxo E3 — Map animation:** mover playhead Edit para f0/f60/f120, criar keyframes em Center Lon/Lat/Zoom/Bearing pelo Inspector; abrir Curve Editor Edit 20 e editar tangentes. O valor de câmera de render deve seguir os parâmetros nativos exatos; não uma timeline duplicada.

**Fluxo E4 — Duas rotas independentes:** adicionar rota Brasília→Caracas e rota adicional, selecionar cada objeto e animar seus trims em tempos diferentes. Demonstrar no Edit Curve Editor as curvas que se promete como nativas. Se apenas uma curva global for possível, classificar como recurso parcial (visual completo, edição por objeto fora do Curve Editor).

**Fluxo E5 — Path edit visual:** clicar waypoint, arrastar handle Bézier no Viewer, ver preview sem atraso excessivo, pressionar Undo para devolver uma operação. Se `Interact` não dá eventos/persistência, aceitar fallback paramétrico e registrar falha do requisito UX.

**Fluxo E6 — Coroplético CSV:** importar tabela com ISO3/valores, normalizar, join, aplicar escala e legenda; selecionar países no Viewer e medir valor; animação por ano/coluna de dados via param nativo onde possível.

**Fluxo E7 — Offline:** sem internet e com cache limpo, gerar Brasil/Venezuela/capitais de dataset embutido, sem bloquear o host e sem endpoints terceiros.

**Fluxo E8 — Salvar e reabrir:** fechar Resolve, abrir projeto, encontrar a mesma cena, mesmas curvas, mesmos objetos, sem referenciar paths temporários ou process memory.

**Fluxo E9 — Copiar/duplicar:** copiar clip CartoRig, alterar cor/camera em uma cópia e verificar política de forks/linked copy; nenhuma alteração silenciosa à outra instância.

**Fluxo E10 — Retime:** cortar início do mapa, alongar duração, aplicar speed ramp e reverse se suportado, checar mapeamento de keyframes e eventos. Não assumir que host OFX entrega tempo monotônico.

**Fluxo E11 — Overlays em vídeo:** aplicar `CartoRig Overlay` a clipe real/adjustment clip, preservar vídeo e alfa, cor correta, preview e Deliver consistentes.

**Fluxo E12 — Grande cena:** importar 2.000 municípios e 10.000 linhas CSV, navegar pelo mapa, selecionar 50 regiões, desenhar em 4K com limitação controlada de cache/memória, sem travar UI.

**Fluxo E13 — Modo 3D:** selecionar DEM, pitch 35°, extrusão, sombra e rotação, medir coerência de picking e imagem render final; se só parâmetros globais forem editáveis na Edit, documentar esse escopo.

**Fluxo E14 — Recuperação:** apagar/corromper um asset de teste, abrir projeto e obter erro acionável + Relink; não perder arquivo original, nem travar render de outros clipes.

**Fluxo E15 — Entrega:** render via Deliver para teste ProRes/DNxHR/H.264 conforme capacidades locais, preservar alfa onde codec/config suportam, comparar frame golden e timecode com preview.

## 11. Laboratório de SDK (Resolve 20) — POCs eliminatórias e observacionais

Cada POC gera uma ficha `{id, ResolveVersionFull, WindowsBuild, StudioStatus, GPUdriver, APIheaders/suites, procedure, expected, observed, screenshots, logs, drp, assets, outcome, decisionADR}`. **Não** aceitar 'passou no Node ou no SDK genérico' como validação do host. Projetos e timelines sempre descartáveis. Gates são qualitativos/funcionais antes de performance.

### EF-POC-01 — Inventário do Developer local 20.3.2

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Anotar versão OpenFX, scripts, Templates, README e exemplos. **Se falhar:** Sem docs locais: não assumir ABI/API. **Prioridade:** eliminatória.

### EF-POC-02 — Carga de bundle OFX no Resolve Studio 20

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Carrega sem crash e aparece na Effects Library. **Se falhar:** Sem carga: rever ABI/build/deps. **Prioridade:** eliminatória.

### EF-POC-03 — Contexto OFX Generator

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Arrastar sem mídia, criar imagem sobre transparência. **Se falhar:** Se falhar: Fusion Generator Macro (C). **Prioridade:** eliminatória.

### EF-POC-04 — Contexto OFX Filter

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Aplicar a vídeo e gerar overlay RGBA. **Se falhar:** Se falhar: efeito Fusion no Edit. **Prioridade:** eliminatória.

### EF-POC-05 — Inspector agrupado e param types

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Números, cores, pontos, strings, paths e buttons funcionam. **Se falhar:** Reformular UI para tipos realmente expostos. **Prioridade:** eliminatória.

### EF-POC-06 — Curve Editor da Edit recebe param OFX

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Três keys + Bézier independente de lon/zoom/opacidade. **Se falhar:** Se falhar: rota C ou macro. **Prioridade:** eliminatória.

### EF-POC-07 — Tangent/curve fidelity

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Valores renderizados correspondem ao valor do host no tempo. **Se falhar:** Não duplicar interpolação. **Prioridade:** eliminatória.

### EF-POC-08 — Persistência dos params nativos

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Abrir/fechar `.drp`, recuperar keys e valores. **Se falhar:** Sem persistência: bloqueia produto. **Prioridade:** eliminatória.

### EF-POC-09 — String param grande

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** 1/16/64/256 KB salvos; duplicar, export project e reabrir. **Se falhar:** Sidecar+manifest se limite insuficiente. **Prioridade:** eliminatória.

### EF-POC-10 — Overlay capability flag

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Inspecionar `SupportsOverlays` e suite real. **Se falhar:** Se falso, sem seleção Viewer OFX. **Prioridade:** eliminatória.

### EF-POC-11 — Eventos mouse overlay na Edit

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** PenDown/Move/Up/Modifier + focus + redraw. **Se falhar:** Fallback paramétrico; requisito UX parcial. **Prioridade:** eliminatória.

### EF-POC-12 — Overlay em DPI/zoom/Pixel Aspect

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Acerto de hit-test em 100/125/150% e 16:9/9:16. **Se falhar:** Corrigir matriz antes de mapa. **Prioridade:** eliminatória.

### EF-POC-13 — Custom Parameter Interact

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Widget próprio no Inspector recebe evento. **Se falhar:** Sem UI rica no Inspector. **Prioridade:** eliminatória.

### EF-POC-14 — Overlay com keyframe e Undo

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Um drag muda um param e um Undo retorna antes. **Se falhar:** Commit no penUp ou outra semântica. **Prioridade:** eliminatória.

### EF-POC-15 — Seleção multipolígono com buracos

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Picking Brasil, ilha, fronteira, região sobreposta. **Se falhar:** Ajustar index & priority. **Prioridade:** eliminatória.

### EF-POC-16 — Declaração de parâmetros fixa

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Tentativa de criar novas curvas após instância deve ser recusada/medida. **Se falhar:** Escolher P/F/I/B definitivamente. **Prioridade:** eliminatória.

### EF-POC-17 — Slots por objeto

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** 8/16/32/64 slots no Inspector + Curve Editor. **Se falhar:** Definir limite nativo real. **Prioridade:** eliminatória.

### EF-POC-18 — 2 clips sincronizados

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Câmera base e rota em clips distintos, edits/retime/copy. **Se falhar:** Se falhar, proibir D como padrão. **Prioridade:** eliminatória.

### EF-POC-19 — Fusion Generator Macro com OFX interno

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Arrastar da Edit e usar curvas publicadas sem ir ao Fusion. **Se falhar:** Plano C certificado. **Prioridade:** eliminatória.

### EF-POC-20 — Eventos de mudança de cena

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Carregar arquivo/scene, repaint e persistência sem congelar UI. **Se falhar:** Escolher import/snapshot. **Prioridade:** eliminatória.

### EF-POC-21 — Tempo local e retime

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Trim, reverse, speed change, 24/25/30 e drop frame. **Se falhar:** Definir time model. **Prioridade:** eliminatória.

### EF-POC-22 — Render chamadas fora de ordem

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Render f120,f0,f40 e comparar golden. **Se falhar:** Proibir estado temporal incremental. **Prioridade:** de qualificação.

### EF-POC-23 — Threading e instâncias simultâneas

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** 2 instâncias render concurrently sem data race. **Se falhar:** Fixar isolamento de estados. **Prioridade:** de qualificação.

### EF-POC-24 — ROI/tile render

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Half/quarter/full e tiles dão mesmo pixel within tolerance. **Se falhar:** Definir tile/ROI policy. **Prioridade:** de qualificação.

### EF-POC-25 — Bit-depth e alfa

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** RGBA8/16/float conforme capacidades, check halos. **Se falhar:** Definir alpha contract. **Prioridade:** eliminatória.

### EF-POC-26 — OCIO/Color Managed

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Rec709, DaVinci YRGB CM e HDR fixture. **Se falhar:** Color interface e warnings. **Prioridade:** de qualificação.

### EF-POC-27 — GPU AMD OpenCL

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Host expõe suite/buffers compatíveis e não falha. **Se falhar:** CPU obrigatório como fallback. **Prioridade:** de qualificação.

### EF-POC-28 — 4K complexidade

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Medir RAM/CPU/latência para 1/50/200 shapes e 10k linhas. **Se falhar:** Definir budgets/cache/LOD. **Prioridade:** de qualificação.

### EF-POC-29 — Dataset offline e imports

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** CSV/GeoJSON de grande volume sem redes. **Se falhar:** Import fora de render. **Prioridade:** de qualificação.

### EF-POC-30 — Labels Unicode

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Português acentuado, textos longos, fontes missing. **Se falhar:** Fallback robusto. **Prioridade:** de qualificação.

### EF-POC-31 — Ports/asset relink

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Export `.drp`, mover para segunda pasta, relink. **Se falhar:** Contrato de portabilidade. **Prioridade:** eliminatória.

### EF-POC-32 — Duplicar clip e forks

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Alterar um duplicate não modifica outros inadvertidamente. **Se falhar:** Clonar IDs/persistência. **Prioridade:** de qualificação.

### EF-POC-33 — Severidade falhas

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Asset corrupto/IO, plugin missing, versão antiga. **Se falhar:** Não crashar host. **Prioridade:** de qualificação.

### EF-POC-34 — Deliver & Render Cache

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Concordância de frame com Edit Viewer em render e cache. **Se falhar:** Sem diferença de estado. **Prioridade:** eliminatória.

### EF-POC-35 — 2.5D depth e picking

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Pitch30/60, extrusão e raycast estáveis. **Se falhar:** Escolher backend 3D. **Prioridade:** de qualificação.

### EF-POC-36 — DEM/terreno LOD

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Costuras, normas e ortofotos licenciadas. **Se falhar:** ADRs 3D. **Prioridade:** de qualificação.

### EF-POC-37 — Globo e dateline

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Projeção ortográfica/esfera e oclusão corretos. **Se falhar:** ADRs de globe. **Prioridade:** de qualificação.

### EF-POC-38 — Limite de cenas multitrack

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Empilhar 30/100 objetos, medir UI/temps. **Se falhar:** Proibir I para grandes cenas se degrada. **Prioridade:** de qualificação.

### EF-POC-39 — Segurança de input

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** GeoJSON malicioso e zip/paths/traversal rejeitados. **Se falhar:** Fail-safe. **Prioridade:** de qualificação.

### EF-POC-40 — Instalação/desinstalação

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Instala somente arquivos do produto, limpa sem perder projetos. **Se falhar:** Checklist release. **Prioridade:** de qualificação.

### EF-POC-41 — Integração da UI auxiliar nativa

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Se admitida, diálogo interno funciona sem outro processo. **Se falhar:** Se ausente, reduzir seleção e busca. **Prioridade:** de qualificação.

### EF-POC-42 — Live editing sem Fusion

**Protocolo:** Em um projeto descartável, produzir uma fixture mínima que isole esta hipótese, registrar logs e capturas de Viewer/Inspector/Curve Editor, exportar `.drp` e verificar reabertura quando aplicável. **Aceite:** Completar cenário mapa 4K BRA/VEN rota câmera e curves na Edit. **Se falhar:** Gate de visão do produto. **Prioridade:** eliminatória.

## 12. Metas de qualidade e definição de pronto (não resultados medidos)

- **Corretude:** mesma cena, frame, dataset, renderer e parâmetros → mesmo estado geométrico e imagem dentro de tolerância definida; golden images em 720p/1080p/4K e escalas do host.
- **Tempo:** 24/25/30 FPS inicialmente; 23.976/29.97/59.94 precisam timebase rational e POC. Não anunciar 'FPS nativo ilimitado' antes de teste de trim/retime.
- **Desempenho:** orçamento inicial de UX sob interação (meta experimental: resposta visual perceptível <200 ms em cenas P0 após cache aquecido; preview e 4K medidos separadamente); não prometer reprodução 4K60 para qualquer cena/GPU. Benchmark por 50, 500 e 5.000 regiões, datasets de 10k linhas e labels em densidade alta.
- **Memory:** monitorar RSS, VRAM, caches por `sceneHash`, limites configuráveis e expulsão LRU; cache entre cenas só para datasets imutáveis.
- **Confiabilidade:** cada erro de asset, schema, fonte ou GPU produz mensagem recuperável; nunca abortar Resolve; preservação de arquivos originais e edição não destrutiva.
- **Acessibilidade:** usar controles nativos do host, nomes completos/units e atalhos sem interceptar timeline global; overlays desenham seleção distinguível sem depender só de cor.
- **Compatibilidade:** Resolve 20 Studio Windows testado, versão exata e driver no relatório; macOS/Linux/Resolve 21 não são suportados sem port/build/teste separado; a versão Free é experimental até prova.
- **Segurança:** pacote sem Electron, sem servidor local e sem telemetria por padrão; não executar JS/Lua de cenas/GeoJSON; isolamento de imports, checksums e licenças.
- **Definition of Done:** especificação → teste unit/contract → plugin loaded in real host → UI/keyframe/Viewer E2E → reabertura do `.drp` → Deliver golden → teste de falha/rollback → documentação/compatibility matrix. Nunca contar só testes unitários como certificação Resolve.

## 13. Dependências e licenciamento: escolhas sujeitas a prova

| Dependência | Licença/fonte (preliminar) | Uso pretendido | Condição para adoção |
| --- | --- | --- | --- |
| OpenFX SDK | ASWF/openfx | API padrão C, samples/support | Build Windows, host subset e distribuição revisados |
| CartoRig Geometry Core | C++ próprio + biblioteca geodésica | Projeção/geo/rotas independentes do host | Golden tests e licença |
| Natural Earth | Domínio público | Base países offline | Provenance/versionamento, fronteiras contestadas |
| PROJ | MIT/X | CRS adicionais | Não necessário em todo render; cuidar de DLL/data |
| GDAL/OGR | MIT com dependências diversas | Import pesado de formatos GIS | Somente import offline, SBOM/ABI/execução segura |
| GeographicLib | MIT | Geodésia, azimute, distância | Alvos numéricos |
| Clipper2 | Boost Software License | Booleanos poligonais e offsets | Limites e topologia |
| GEOS | LGPL | Topologia/repair/index | Revisão compliance antes de linkar |
| Skia ou similar | Licença do pacote/deps a auditar | Rasterização vetorial / shaping | Benchmark, ABI e GPU optional |
| HarfBuzz/FreeType | Licenças distintas | Shaping/fontes | Não redistribuir fontes licenciadas |
| SQLite | Public domain em regra | Catálogo/índices/caches opcionais | DB não acessado por callback render desnecessariamente |
| OSM / satellite provider | ODbL/termos específicos | Tiles, ruas, 3D e satélite | Proibir bulk dos endpoints comunitários; direitos de video/cache |

### 13.1 Distribuição e instalador Windows

Instalar bundle OFX na localização documentada da instalação; não sobrescrever diretórios Blackmagic e não empacotar binários proprietários não autorizados. Registrar identificador único e versão major compatível. Fornecer uninstall que remove só os arquivos do plugin, não cenas/caches de trabalho do usuário por padrão. Empacotar manifest de assets, licenças, SBOM, hashes e logs de diagnóstico; drivers/GPU não serão alterados pelo instalador. Integração com Codex/MCP deve permanecer opcional apenas para desenvolvimento, nunca requisito do runtime.

## 14. Roadmap de engenharia **após** testes, sem comprometer implementação nesta etapa

| Gate | Resultado exigido | Se reprovar |
|---|---|---|
| **G0 — Edit-first certificável** | EF-POC-02/03/05/06/08/10/11/19; mapa nativo e parâmetros reais no Edit | Redesenhar UI/arquitetura; não produzir milhares de linhas sem gate |
| **G1 — Core geo 2D confiável** | CRS/projection/topology/markers/routes determinísticos e offline | Ajustar bibliotecas e contratos |
| **G2 — State & time** | `.drp`, duplicação, trim/retime, curvas e rollback funcionam | Adotar sidecar/fixed slot/macro mais restrita |
| **G3 — UX geográfica** | Viewer select/path edit; se impossível, decisão formal de fallback aceitável | Não prometer 100% dos gestos |
| **G4 — Features 42 P0/P1** | Motor, controles e curvas por feature com aceites individuais | Marcar parcial; não simular botões |
| **G5 — Dados/dataviz 2D** | CSV/GeoJSON/choropleth/labels, licença, cache, desempenho | Limitar dataset e informar |
| **G6 — 2.5D/3D** | Terrain, extrusion, globe, satellite benchmarks/rights | Backlog não bloqueante do 2D |
| **G7 — Release** | 129 testes convertidos + 465 trace + Win real + deliver | Bloquear release |

**Ordem recomendada de spikes:** primeiro provar que um **OFX Generator** funciona e é animável na Edit 20; imediatamente provar overlay `penDown/move/up`, serialização, tipos de parâmetro e clip duplication; só depois comprometer-se com renderer C++ completo. Um Fuse antes do OFX pode reduzir risco de desenho, mas não responde a pergunta central sobre a página Edit.

## 15. Bibliografia verificável e separação da evidência

1. **Blackmagic Design — DaVinci Resolve 20 New Features Guide**, Cut and Edit (páginas impressas 16–22): https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_20_New_Features_Guide.pdf . Prova do editor Keyframe/Curve nativo e seleção de parâmetros OpenFX. Confirmado via abertura e captura do PDF; **não comprova** o comportamento de nosso plugin ainda inexistente.
2. **Blackmagic Design — Fusion 20.3 Reference Manual**, capítulo 6 sobre Fusion Templates/Edit Generators, pp. 177–182: https://documents.blackmagicdesign.com/UserManuals/FusionManual.pdf . Prova do mecanismo Generator Macro na Edit; documento foi inspecionado por extração textual do PDF. Captura de página via ferramenta de pesquisa indisponível para esse PDF grande; demais conclusões dependem também do guia Resolve 20.
3. **Blackmagic Design — The Visual Effects Guide to DaVinci Resolve 20**, capítulo 'Saving a Template' e uso do Inspector Edit: https://documents.blackmagicdesign.com/UserManuals/DaVinci-Resolve-20-Fusion-Visual-Effects.pdf . Confirma workflow de template.
4. **Academy Software Foundation — OpenFX Image Effect Contexts**: https://openfx.readthedocs.io/en/main/Reference/ofxImageEffectContexts.html . Enumera generator/filter/transition e contratos de clips; NÃO implica que Resolve suporta automaticamente todos eles.
5. **Academy Software Foundation — OpenFX Effect Parameters**: https://openfx.readthedocs.io/en/main/Reference/ofxParameter.html . `paramDefine` na descrição, persistência e avaliação temporal.
6. **Academy Software Foundation — OpenFX Interacts**: https://openfx.readthedocs.io/en/main/Reference/ofxInteracts.html . Overlay e parâmetro customizável são opcionais pelo host.
7. **Academy Software Foundation — OpenFX Rendering**: https://openfx.readthedocs.io/en/main/Reference/ofxRendering.html . Render por tempo, abort, threading e GPU condicionados.
8. **Academy Software Foundation — OpenFX Headers/Support**: https://github.com/AcademySoftwareFoundation/openfx . Cabeçalhos de contexto/host e samples; ainda é necessário verificar versão efetivamente negociada com Resolve 20.
9. **Arquivos primários de produto do usuário**: catálogo 465, specs 42, `TEST_MATRIX.csv`, MAP/ADV/P0/P1/P2, documentos de arquitetura e estudos anteriores na pasta desta análise. A extensão do catálogo **não prova capacidades do host**.

**Fontes de versões 21+ não são autoridade para prometer recursos exclusivos na versão 20.** Em particular, Multi-Inspector e integração USD de versões 21 não devem aparecer como dependências obrigatórias.

## 16. Plano por funcionalidade — **42 features de animação**, uma por uma

Esta seção preserva as **42 IDs originais e os critérios conceituais**, mas define como seria a execução e a UI na página Edit. O status que consta no catálogo é o da versão **original**, não do Edit-first. `POC` nas limitações significa requisito que **não deve ser declarado entregue** sem teste real.

### KF-01 — **Keyframes múltiplos por propriedade:** Criar, substituir, excluir e avaliar três ou mais keys na mesma trilha.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** OFX numeric param values host-owned; internal track only for nonexposed objects. **Superfície para o editor:** Edit Inspector + Keyframe/Curve Editor. **Dependência/risco de SDK:** Cross-clip/hidden-object animation not auto-native. **Teste de aceite novo:** 3 keys of zoom edit/render/reopen correctly. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-02 — **Timeline multicamadas:** Régua comum, trilhas por objeto/propriedade, seleção e playhead.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Do not recreate HTML timeline; use Edit Keyframes + selected param menus. **Superfície para o editor:** Edit Keyframes panel and clip track. **Dependência/risco de SDK:** No arbitrary object rows for internal scene properties. **Teste de aceite novo:** At least camera/selected route visible, synced playhead. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-03 — **Auto Keyframe:** Registrar propriedade/pose somente com o modo ativo; alteração pelo preview da câmera.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.1. **Estratégia de implementação Edit-first:** Use Inspector keyframing and overlay penUp to set one value at current OFX time. **Superfície para o editor:** Edit Inspector; overlay if host permits. **Dependência/risco de SDK:** Host undo/auto-key semantics must be tested. **Teste de aceite novo:** Off does not create key; on creates exactly one at fN. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-04 — **Graph Editor profissional:** Gráfico de valores e edição Bézier limitada existem; ainda faltam curvas de velocidade completas e manipulação multicanal avançada.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.2–v0.4.0. **Estratégia de implementação Edit-first:** Expose numeric curve channels natively; show time/value and handles. **Superfície para o editor:** Resolve 20 Edit Curve Editor. **Dependência/risco de SDK:** Velocity graphs and multichannel editing differ from Fusion Spline; test. **Teste de aceite novo:** Handles and speed ramp change output, not cosmetic line. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-05 — **Easing individual completo:** Linear, Smoothstep, Hold e Bézier por segmento existem; experiência plena Ease In/Out/InOut e tangentes avançadas permanece parcial.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.0–v0.4.0. **Estratégia de implementação Edit-first:** Host interpolation for exposed params; custom segment evaluator for internal tracks. **Superfície para o editor:** Edit Curve Editor. **Dependência/risco de SDK:** Not guaranteed to preserve custom cubicBezier(x1,y1,x2,y2) exactly. **Teste de aceite novo:** Linear/ease/hold and advanced curve golden values. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-06 — **Trilhas independentes:** Zoom/posição/opacidade/progresso separados sem sobrescrever outro canal.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Dedicated param IDs per camera channel and fixed per-object slots. **Superfície para o editor:** Edit Curve parameter selector. **Dependência/risco de SDK:** Dynamic N tracks not supported with single OFX instance. **Teste de aceite novo:** Zoom edit leaves longitude/color unchanged. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-07 — **Copiar, colar e duplicar keyframes:** Colagem relativa com IDs próprios, validação de limites e Undo.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Use host copy/paste for native curves; command engine for scene-only keys. **Superfície para o editor:** Edit Keyframe/Curve Editor. **Dependência/risco de SDK:** Internal track copying will not appear as host native rows. **Teste de aceite novo:** Key offsets/values correct after paste/reopen. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-08 — **Mover e escalar grupos de keyframes:** Movimento múltiplo e comando de escala no motor; retiming visual completo ainda pendente.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.0–v0.4.0. **Estratégia de implementação Edit-first:** Retime native param keys in Edit Curve; remap internal timebase for data clips. **Superfície para o editor:** Edit Curve Editor. **Dependência/risco de SDK:** Retiming selected sets not synchronized across distinct clip instances. **Teste de aceite novo:** No collisions/out-of-range after retime and clip trim. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-09 — **Snap e marcadores:** Snap configurável, playhead, marcadores temporais e keys.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Use Edit Curve snap/host markers; map custom sync markers via stable time domain. **Superfície para o editor:** Edit Curve + timeline markers. **Dependência/risco de SDK:** Not guaranteed to support snap to arbitrary geoevent. **Teste de aceite novo:** Keys snap as documented and marker time preserved. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### KF-10 — **Undo/Redo:** Comandos reversíveis de edição e poses atômicas.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Host native undo for param and overlay mutations; snapshots for external files. **Superfície para o editor:** Edit Undo/Redo. **Dependência/risco de SDK:** OFX file import cannot assume grouped host undo. **Teste de aceite novo:** One gesture one undo; data file rollback intact. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-11 — **Câmera multiponto por keyframes:** Trilhas de lon/lat/zoom aceitam múltiplas poses; não inclui trajetória espacial Bézier.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Center lon/lat, zoom and bearing exposed; internal path computed at any time. **Superfície para o editor:** Edit Inspector + Curve Editor. **Dependência/risco de SDK:** Unwrapping longitude interpolation must not depend on host scalar wrap. **Teste de aceite novo:** 3+ poses exact at keyed frames, antimeridian shortest path. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-12 — **Trajetória Bézier espacial da câmera:** Editar alças geográficas e caminho espacial, distinto do Bézier temporal do Graph Editor.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Separate spatial Bezier path from temporal easing; evaluate then expose path progress. **Superfície para o editor:** Viewer overlay handles + Edit Curve for progress. **Dependência/risco de SDK:** OFX overlay event completeness unverified. **Teste de aceite novo:** Path goes through points and handles remain editable after reopen. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-13 — **Fly-to cinematográfico:** Zoom de altitude intermediária e deslocamento geográfico suave entre locais distantes.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Geo fly-to with zoom apex, lat/long path, easing and cinematic profiles. **Superfície para o editor:** Edit preset + keyframed progress/zoom. **Dependência/risco de SDK:** One plugin control cannot create arbitrary host keys silently. **Teste de aceite novo:** Travel no pop, end center/zoom exact. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-14 — **Bearing / rotação da câmera:** Animar direção do mapa, preservando referências e legibilidade de rótulos.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Bearing native numeric param, rotate projected geometry about center. **Superfície para o editor:** Edit Inspector + Viewer. **Dependência/risco de SDK:** Label upright offsets must compensate rotation. **Teste de aceite novo:** 0/90/180° and zoom keep anchors precise. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-15 — **Zoom ancorado:** Manter coordenada geográfica escolhida fixa sob a âncora da viewport.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Hold inverse-projected geographic anchor under fixed screen pixel. **Superfície para o editor:** Viewer gesture + anchor param. **Dependência/risco de SDK:** Mouse pivot needs correct overlay coordinate and scale. **Teste de aceite novo:** Anchor drift under zoom below tolerance. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-16 — **Auto Frame / Fit Bounds completo:** Centralização de territórios existe; falta enquadramento amplo de estados, rotas e antimeridiano.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.1–v0.4.0. **Estratégia de implementação Edit-first:** Compute multi-feature geobounds including route padding and dateline. **Superfície para o editor:** Edit Fit button (if supported) + Inspector result params. **Dependência/risco de SDK:** A dynamic button cannot inject custom host keys without POC. **Teste de aceite novo:** All selected features fully framed on output. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-17 — **Velocidade geográfica constante:** Percorrer caminho por distância geográfica ou de tela, opção explícita.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Arc-length lookup table geodesic or screen model persistently selected. **Superfície para o editor:** Edit speed/progress numeric curves. **Dependência/risco de SDK:** Host curves change time law; geographic constant-speed needs reparameterization. **Teste de aceite novo:** Equal time intervals travel equal distance under selected metric. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### CAM-18 — **Camera Follow:** Seguir objeto/marcador em movimento com offset previsível.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.4.0. **Estratégia de implementação Edit-first:** Constraint camera target to evaluated moving object plus offset in same frame. **Superfície para o editor:** Edit Follow toggle/target selector. **Dependência/risco de SDK:** Dynamic target choice and cyclic constraints need safe schema. **Teste de aceite novo:** Camera holds object and avoids feedback cycles. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-19 — **Cor animada de território:** Interpolar RGB/space explícito por keyframes mantendo extremos exatos.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Per-object color property; fixed slots native or internal scene track. **Superfície para o editor:** Edit Inspector/Curve if dedicated slot. **Dependência/risco de SDK:** Per-country unlimited color curves impossible in one static OFX parameter set. **Teste de aceite novo:** RGB endpoints/alpha exact in defined color space. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-20 — **Opacidade territorial por keyframe:** Trilha de opacidade com múltiplos keys 0..1; além do fade legado.

**Origem/estado no CartoRig antigo:** ✅ Implementado, marco v0.3.0. **Estratégia de implementação Edit-first:** Opacity 0..1 per territory, premultiplied alpha in render. **Superfície para o editor:** Edit Inspector/Curve if slot. **Dependência/risco de SDK:** Dynamic object-specific curve exposure limited. **Teste de aceite novo:** Fade correct on black and white. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-21 — **Stroke Reveal de fronteiras:** Desenhar perímetro de Polygon/MultiPolygon progressivamente.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Polyline ring arc-length, holes/islands separate reveal order. **Superfície para o editor:** Edit Reveal Progress param/Curve. **Dependência/risco de SDK:** Complex multi-poly coverage and winding policy needed. **Teste de aceite novo:** Reveal traces exact boundary without teleport. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-22 — **Fill Reveal territorial:** Preenchimento radial/direcional com clipping real do polígono.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Fill reveal masks clipped against polygon and holes. **Superfície para o editor:** Edit Reveal Mode + Progress param. **Dependência/risco de SDK:** Overlay clipping and feather require CPU/GPU backend. **Teste de aceite novo:** No pixel fills outside selected regions. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-23 — **Pulsação de território:** Pulse de opacidade/borda reprodutível e controlável.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Analytic pulse(time,period,phase) evaluated at requested frame. **Superfície para o editor:** Edit amplitude/frequency params. **Dependência/risco de SDK:** Clip retime and out-of-order render must remain deterministic. **Teste de aceite novo:** Pulses repeat after reopening. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-24 — **Espessura animada da fronteira:** Controlar stroke width com keyframes em unidades definidas.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Stroke width pixel/world units and border join rules. **Superfície para o editor:** Edit width numeric param/Curve. **Dependência/risco de SDK:** Geometry overlap vs adjacent regions. **Teste de aceite novo:** Thickness changes without cracks. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-25 — **Glow animado:** Animar intensidade/raio de brilho com orçamento de render.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Glow generation using bounded kernel/blur and alpha contract. **Superfície para o editor:** Edit radius/intensity params. **Dependência/risco de SDK:** 4K GPU/CPU perf; color management. **Teste de aceite novo:** Intensity zero matches source exactly. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-26 — **Scale/Pop:** Escala/overshoot de região, marcador ou rótulo.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Scale/Pop transform about georeferenced or screen-space pivot. **Superfície para o editor:** Edit scale/overshoot curve. **Dependência/risco de SDK:** Avoid breaking anchor alignment for zoom. **Teste de aceite novo:** Overshoot and return align at extremes. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### GEO-27 — **Presets de destaque:** Aplicar e editar keyframes/efeitos de destaque como uma operação.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Versioned presets apply multiple properties and scene curves as transaction. **Superfície para o editor:** Edit preset button/picker. **Dependência/risco de SDK:** Presets cannot magically add dynamic param names. **Teste de aceite novo:** One click template; undo restores all. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-28 — **Rotas multiponto:** Trajetória com três ou mais waypoints.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Waypoint list with geometry segments and named points; cache metric. **Superfície para o editor:** Viewer path edit + data scene. **Dependência/risco de SDK:** UI for unbounded waypoint list needs overlay/dialog. **Teste de aceite novo:** 3+ waypoints drawn, trim continuous. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-29 — **Path Editor Bézier:** Editar handles espaciais e tangentes da rota.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Bezier spatial tangents with editable controls and snapping. **Superfície para o editor:** Viewer Overlay Interact. **Dependência/risco de SDK:** Fails if pen events unsupported on Edit. **Teste de aceite novo:** Handles change path, not just temporal easing. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-30 — **Trim Path Start/End independentes:** Progresso de revelação atual existe; faltam controles simultâneos independentes de início e fim do traço.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.1–v0.5.0. **Estratégia de implementação Edit-first:** Separate trimStart/trimEnd values; same path distance table. **Superfície para o editor:** Edit two numeric curves. **Dependência/risco de SDK:** Binding two params for 100 routes needs slot strategy. **Teste de aceite novo:** Trim interval exact including start>end invalid. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-31 — **Moving Object:** Mover ícone separado pela distância acumulada no caminho.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Moving object evaluates position at path distance, not frame index. **Superfície para o editor:** Edit Object Progress parameter. **Dependência/risco de SDK:** Icon source, fonts and crop license. **Teste de aceite novo:** Object center always on route. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-32 — **Orient Along Path:** Orientação do ícone pela tangente da trajetória e offset.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Orientation uses tangent with angle unwrap and user offset. **Superfície para o editor:** Edit Orient switch/rotation offset. **Dependência/risco de SDK:** Degenerate short segments and dateline. **Teste de aceite novo:** No 180° flips at curved junction. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-33 — **Trailing Line:** Criar rastro de comprimento/tempo ajustável.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Trail window by time or distance from moving object. **Superfície para o editor:** Edit Trail Length/Opacity params. **Dependência/risco de SDK:** Host retime nonmonotonic. **Teste de aceite novo:** Trail follows mover without lag. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-34 — **Dashed Motion:** Linha tracejada estática existe; deslocamento animado do padrão não.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.1–v0.5.0. **Estratégia de implementação Edit-first:** Dash phase animates independently of route reveal. **Superfície para o editor:** Edit Dash Phase numeric curve. **Dependência/risco de SDK:** Zoom-dependent dash scale must be declared. **Teste de aceite novo:** Dashes move at defined speed independent of route. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-35 — **Route Morphing:** Transformar rotas com reamostragem de geometrias.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Align direction of paths and resample by arc-length for morph. **Superfície para o editor:** Edit Morph progress curve. **Dependência/risco de SDK:** Topologies with different waypoint counts. **Teste de aceite novo:** Morph endpoints exact, no large jumps. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### ROUTE-36 — **Velocidade variável por segmento:** Keys de progresso com Bézier temporal existem; editor completo por segmentos/waypoints não.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.0–v0.5.0. **Estratégia de implementação Edit-first:** Piecewise timing function per waypoint/segment with speed profiles. **Superfície para o editor:** Edit Curve progress for active route. **Dependência/risco de SDK:** Generic global curve not enough for all routes. **Teste de aceite novo:** Segment change continuous and speed-ramp visible. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-37 — **Presets cinematográficos:** Presets simples de easing existem; Fly-in, Fly-out, Country Reveal e câmera completa ainda não.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.1–v0.5.0. **Estratégia de implementação Edit-first:** Pack versioned camera/highlight/route preset scene graph entries. **Superfície para o editor:** Edit Preset/Inspector. **Dependência/risco de SDK:** One-click applying many native keyframes needs host semantic POC. **Teste de aceite novo:** Preset reproducible across projects. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-38 — **Parent & Constraints:** Vínculos objetos/câmera, hierarquia e detecção de ciclos.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Graph constraints with parent transform/geoanchor and cycle rejection. **Superfície para o editor:** Edit Parent/Constraint controls. **Dependência/risco de SDK:** Inspector dynamic target selection may require imported catalog picker. **Teste de aceite novo:** Child follows parent without drift or cycles. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-39 — **Grupos e animação em cascata:** Selecionar objetos e aplicar stagger por frame/ordem definida.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Stagger scheduling by object order/time with stable IDs. **Superfície para o editor:** Edit Group control and Start/Delay. **Dependência/risco de SDK:** Cannot display unlimited per-object curves natively. **Teste de aceite novo:** 10-object cascade stable under project reopen. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-40 — **Marcadores de sincronização:** Marcadores temporais simples existem; integração com narração/áudio e eventos ampliados ainda não.

**Origem/estado no CartoRig antigo:** 🟨 Parcial, marco v0.3.1–v0.4.0. **Estratégia de implementação Edit-first:** Timeline markers as primary; scene sync references timecode IDs. **Superfície para o editor:** Edit timeline markers. **Dependência/risco de SDK:** No automatic audio features assumed in v20. **Teste de aceite novo:** Cue markers align frame-accurately with route/camera. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-41 — **Loop, Ping-Pong e Hold de animações:** Repetição temporal e inversão configuráveis de trechos; Hold isolado de interpolação já existe.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Analytic loop/pingpong/hold mapping of host time to local intervals. **Superfície para o editor:** Edit Loop/Mode/Period params. **Dependência/risco de SDK:** Host and internal curves could conflict; clear precedence. **Teste de aceite novo:** Out of order same image for repeated frame. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

### MG-42 — **Expressions seguras:** AST restrita sem `eval`, ciclos e budgets de execução.

**Origem/estado no CartoRig antigo:** ⬜ Planejado, marco v0.5.0. **Estratégia de implementação Edit-first:** Restricted typed AST expression DSL with budgets and graph cycle detection. **Superfície para o editor:** Edit expression preset/text only if safe. **Dependência/risco de SDK:** Do not evaluate user JS/Lua; not necessarily native host expression. **Teste de aceite novo:** Bad expression errors without freeze and deterministic output. A prova deverá comparar f0, fN/2 e fN com imagem golden, salvar projeto, fechar e reabrir, e verificar que o recurso funciona **sem acionar uma janela Electron nem abrir obrigatoriamente Fusion**. Não classificar como 'curva nativa' quando sua propriedade estiver apenas em animação serializada interna.

## 17. Plano por requisito de produto — **MAP-001..020**

Os documentos `01-PRODUCT.md` e a especificação Native anterior misturam 'criar composição Fusion' com o resultado desejado. Sob Edit-first, **resultados comportamentais são conservados**, mas os mecanismos (nós/PNG/Editor externo) são explicitamente substituídos quando equivalentes na Edit.

### MAP-001 — Criar cena com nome, resolução, fps, totalFrames, estilo

**Critério original:** Novo arquivo válido no schema; defaults 3840x2160, 24, 240. **Adaptação operacional Edit-first:** Gerador contém schema versionado; timebase e resolução do host; preset inicial e fallback offline. Inspector controla variáveis globais, cena é serializada com hash.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-002 — Buscar países, capitais e cidades presentes no catálogo offline

**Critério original:** `Brasil` retorna BRA, `Venezuela` VEN; resultados ambíguos exigem escolha. **Adaptação operacional Edit-first:** Index local Unicode/ISO3 com desambiguação tipada. Busca por texto no Inspector só se host suportar widget adequado; senão diálogo nativo pontual ou lista limitada. Não inventar painel dockável.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-003 — Adicionar destaque de país/fronteira com cor/opacidade

**Critério original:** Camada isolada e nomeada, sem alterar mapa-base. **Adaptação operacional Edit-first:** Render de fill/stroke por featureId; seleção via overlay apenas após POC. Preservar cobertura de polígonos e alfa.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-004 — Inserir marcador geoancorado e rótulo

**Critério original:** Posição acompanha câmera; tamanho aparente de marcador/rótulo estável. **Adaptação operacional Edit-first:** Ponto WGS84 e label Unicode screen-size; cada frame projeta anchor com câmera nativa; hit test e drag quando possível.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-005 — Criar rota de duas ou mais coordenadas com revelação

**Critério original:** Visibilidade de 0% no frame inicial e 100% no final, sem teleporte. **Adaptação operacional Edit-first:** Polylines com 2+ pontos, arco/distância e trim animável; para muitas rotas prever slots/editing não nativo.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-006 — Câmera com pan, zoom, bearing e keyframes

**Critério original:** Frames de início/fim e intermediários determinísticos; dateline sem giro longo. **Adaptação operacional Edit-first:** Center/zoom/bearing expostos em parâmetros OFX; transição geo coerente; 3+ keys no Curve Editor Edit.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-007 — `fitToFeatures` com padding

**Critério original:** Todos pontos/área enquadrados sem cortar margem, exceto limitações explícitas. **Adaptação operacional Edit-first:** FitBounds determinístico com margens/antimeridiano/rotação; resultado transferido a parâmetros nativos com operação atômica.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-008 — Estilos escuro/claro + paleta editável

**Critério original:** Alterar cor da terra/água/contorno sem regenerar scene ID. **Adaptação operacional Edit-first:** Paletas versionadas e controles nativos para água/terra/borda; não alterar feature IDs.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-009 — Preview frame-accurate e reprodução

**Critério original:** Frame N do preview corresponde ao render N, tolerância visual definida. **Adaptação operacional Edit-first:** Render OFX recebe tempo solicitado; comparação preview/Deliver em fN; reprodução do host, sem timer próprio.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-010 — Salvar, reabrir e versionar `.namap.json`

**Critério original:** Round-trip sem perda; recurso ausente reportado, sem crash. **Adaptação operacional Edit-first:** Cena embutida quando viável + manifest/sidecar portável; testes `.drp`/reopen/relink, não confiar em paths absolutos.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-011 — Gerar composição Fusion com nodes organizados

**Critério original:** MediaOut ligado, nomes estáveis, camadas editáveis conforme matriz. **Adaptação operacional Edit-first:** Se caminho OFX, dispensa Nodes Fusion visíveis para o usuário; o critério se transforma em efeito nativo com capas editáveis. Para modo C, Macro com nós organizados.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-012 — Inserir no projeto/timeline e reabrir

**Critério original:** Composição legível no Resolve Studio e visível na timeline. **Adaptação operacional Edit-first:** Arraste para timeline Edit sem abrir Fusion; import/export e reopen do Resolve são provas; não criar clipe via spawn Lua externo.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-013 — Atualização idempotente

**Critério original:** Duas atualizações iguais não duplicam nodes/clipes/assets. **Adaptação operacional Edit-first:** Diff scene hash com identidade de instância; aplicar somente quando mudou, sem duplicar dados/efeitos.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-014 — Exportar para uso no Resolve com alfa

**Critério original:** Render local 4K de mapa/camadas, alfa correto, assets relativos. **Adaptação operacional Edit-first:** Delivers pelo host com alfa e cor; export extra por arquivo é opcional e autenticado; não gerar PNG sequencial como pré-requisito.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-015 — Undo/redo no editor e cancelamento

**Critério original:** Ações reverterem estado; cancelamento não deixa cena corrompida. **Adaptação operacional Edit-first:** Use Undo host para params e manipulação; snapshots para scene file; cancelamento não corrompe dados.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-016 — Diagnóstico e erros compreensíveis

**Critério original:** Sem Studio ou sem timeline: erro acionável; export standalone continua disponível. **Adaptação operacional Edit-first:** Diagnostics no Inspector/comando nativo; version/capabilities/assets; descrição não deve afirmar Studio sem teste.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-017 — Preset `Neo Atlas Dark`

**Critério original:** Resultado visual repetível, cores configuráveis, assets próprios. **Adaptação operacional Edit-first:** Preset dark independente da marca editorial, tokens declarativos, contraste e defaults versionados.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-018 — Transparência sobre fontes e atribuições

**Critério original:** Cada scene registra dataset e licença; créditos quando exigidos. **Adaptação operacional Edit-first:** Dataset/version/sha/license/credits em manifest e botão de informação; não ocultar fronteiras controvertidas.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-019 — Atualizar sem destruir edições não gerenciadas

**Critério original:** Nós de usuário preservados; conflitos sinalizados, sem sobrescrita silenciosa. **Adaptação operacional Edit-first:** Plugins OFX não gerenciam nodes Fusion em modo A; preservar outros efeitos/clipes. Em modo C respeitar namespace de nodes.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

### MAP-020 — Projeto offline-first

**Critério original:** Cena de países + capitais e export funcionam sem rede. **Adaptação operacional Edit-first:** Natural Earth e catálogo de capitais offline, sem rede nas chamadas de render nem APIs pagas obrigatórias.. **Verificação:** reproduzir caso no Viewer e Inspector da Edit 20, conferir resultado no Curve Editor quando animável, testar reabertura de `.drp`, checar falha segura e registrar limitações do host em um ADR.

## 18. Expansão geográfica e 3D — **ADV-001..016 / ADV-101..108**

Os 24 ADV são aspirações funcionais documentadas e exigem níveis diferentes de maturidade. 2D/raster por frame não é equivalência de edição 3D por nó. A matriz abaixo contém o mecanismo interno, a superfície de UI Edit e a principal prova que deverá ser realizada.

### ADV-001 — Importação GeoJSON

**Contrato original:** `importGeoJSON(input, limits): FeatureCollection`, CRS WGS84 documentado; validado. **Resultado original esperado:** `Polygon/MultiPolygon/Point/LineString`, buracos, dateline e JSON malicioso. **Mecanismo proposto:** Parser GeoJSON isolado com limites Polygon/MultiPolygon/LineString/Point; CRS e topologia. **Como seria editado na página Edit:** Importador de arquivo pelo host se suportado; sem editor web. **Gate principal:** Huge files e geometria maliciosa. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-002 — Import CSV/TSV

**Contrato original:** Mapper guiado de colunas lon, lat, ISO3, valores, labels e locale. **Resultado original esperado:** Amostra 10k linhas, duplicidades e encoding BOM, sem swap lon/lat. **Mecanismo proposto:** CSV/TSV com parser RFC4180-aware, BOM, locale, schema mapper, ISO3 join. **Como seria editado na página Edit:** File input/diálogo; visualização em overlay só se comprovada. **Gate principal:** 10k linhas, injection e ambiguidade lon/lat. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-003 — Estatística por país/região

**Contrato original:** join por ISO3/featureID e escala linear/quantis, missing=estilo explícito. **Resultado original esperado:** Ordem/valores e choropleth fixtures idênticos após reopen. **Mecanismo proposto:** Choropleth: quantile/linear/log scales, missing style, legend. **Como seria editado na página Edit:** Selector de atributo e estilo global no Inspector. **Gate principal:** Curvas por país dinâmicas não aparecem sem slots. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-004 — Fontes geográficas múltiplas

**Contrato original:** Catalog adapters (Natural Earth / arquivo próprio / provedor licenciado), provenance. **Resultado original esperado:** Trocar dataset mantém IDs se possível, apresenta diff de fronteiras. **Mecanismo proposto:** Versioned catalog adapters, source attribution and source diff. **Como seria editado na página Edit:** Dataset picker/manifest. **Gate principal:** Licenças e fronteiras divergentes. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-005 — Pesquisa avançada

**Contrato original:** resultados tipados países/ADM1/cidades/POI, score e desambiguação. **Resultado original esperado:** `São Paulo` município vs estado não seleciona sozinho. **Mecanismo proposto:** Fuzzy search normalized typed autocomplete/disambiguation. **Como seria editado na página Edit:** Native dialog ou text param se host permitir. **Gate principal:** Sem browser dockável garantido. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-006 — Recurso desenhado no mapa

**Contrato original:** cliques criam linha, polígono e ponto WGS84 editáveis no editor. **Resultado original esperado:** round-trip, edição vértices, distância e snap desativável. **Mecanismo proposto:** Point/line/polygon manual geometry persisted WGS84; screenToGeo. **Como seria editado na página Edit:** Viewer overlay pen events + handles. **Gate principal:** Principal POC para criação/edit visual. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-007 — Estilos extensos

**Contrato original:** paleta, stroke, camadas hidrografia/rodovias, labels e presets. **Resultado original esperado:** toggle isolado não altera georreferência nem outros layers. **Mecanismo proposto:** Styles for hydrology, roads, borders, palette, labels. **Como seria editado na página Edit:** Inspector colors/groups. **Gate principal:** Complexidade de layers e licença de dados. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-008 — Labels inteligentes

**Contrato original:** evitar overlap previsivelmente, prioridade e idiomas; override manual persistente. **Resultado original esperado:** 50 labels, collisions <= baseline e estabilidade por frame. **Mecanismo proposto:** Temporal label collision solver with priority, hysteresis, manual override. **Como seria editado na página Edit:** Inspector label settings; drag overlay. **Gate principal:** Font/render stability and jitter. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-009 — Animação de rotas avançada

**Contrato original:** pontos intermediários, curvas por waypoints, ritmo, trace, ícone móvel. **Resultado original esperado:** objeto permanece sobre trajetória em todo frame. **Mecanismo proposto:** Multisegment route geodesic/projection, mover, trace. **Como seria editado na página Edit:** Viewer path editor + Curve. **Gate principal:** Full route editing may require custom overlay. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-010 — Linhas de conexão

**Contrato original:** mesh one-to-many/many-to-many, sem duplicações. **Resultado original esperado:** N pontos geram cardinalidade esperada, limite de desempenho. **Mecanismo proposto:** Graph of connections one-to-many/many-to-many with stable edges. **Como seria editado na página Edit:** Inspector global weights and group settings. **Gate principal:** N² explosion and path overlap. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-011 — Máscaras de água/terra

**Contrato original:** land/water shapes independentes por região. **Resultado original esperado:** water holes sem preencher lagos, compositing 4K correto. **Mecanismo proposto:** Distinct land/water masks with holes, clip and z order. **Como seria editado na página Edit:** Inspector toggles and blending. **Gate principal:** Topological water holes and color alpha. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-012 — Diretório de templates

**Contrato original:** presets de cena, intro, zoom, foco, rotas, highlight, legenda. **Resultado original esperado:** importar preset não sobrescreve IDs ou assets alheios. **Mecanismo proposto:** Versioned preset catalog and dependency-aware application. **Como seria editado na página Edit:** Effects Library presets and Inspector. **Gate principal:** Preset writes N dynamic keys, needs transaction. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-013 — API local de automação

**Contrato original:** CLI versionado e/ou IPC segura para criar cenas por JSON. **Resultado original esperado:** batch 100 cenas sem abrir editor, recursos autorizados. **Mecanismo proposto:** CLI/batch data validation independent of host. **Como seria editado na página Edit:** Script inside Resolve or offline nonruntime tool. **Gate principal:** User demanded no companion runtime; automation optional. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-014 — Provedores externos

**Contrato original:** conectores opcionais, quotas, caching, consentimento e licenças para vídeo. **Resultado original esperado:** simular 401/429/cache-expired/offline/limite de tiles. **Mecanismo proposto:** Licensed providers with quotas, cache, user consent. **Como seria editado na página Edit:** File/URL options in settings only with explicit permission. **Gate principal:** No third-party public tile bulk/download. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-015 — Temas a partir de imagem

**Contrato original:** extrair paleta local de imagem autorizada e mapear para tokens. **Resultado original esperado:** resultados reproduzíveis, cores acessíveis, sem exportar imagem para servidor. **Mecanismo proposto:** Local image palette extraction, deterministic token mapping. **Como seria editado na página Edit:** Import picker; theme presets. **Gate principal:** Data-source privacy and reproducibility. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-016 — Distância/escala/rosa dos ventos

**Contrato original:** geodésica, projeção da escala e visibilidade. **Resultado original esperado:** 100/1000km de referência e variação latitude corretas. **Mecanismo proposto:** Geodesic scalebar, north arrow, distance/unit and lat-specific corrections. **Como seria editado na página Edit:** Inspector size/visibility. **Gate principal:** Mercator scale varies latitude. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-101 — Câmera 2.5D

**Contrato original:** pitch/heading, matriz de view/projeção, clipping e picking. **Resultado original esperado:** anchors corretos em 0/30/60° e reversão de tela p/ geo. **Mecanismo proposto:** Camera matrices 2.5D pitch/heading, raycasting and depth. **Como seria editado na página Edit:** Edit Inspector angles; overlays if host. **Gate principal:** Picking when pitched and high DPI. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-102 — Terreno de elevação

**Contrato original:** DEM licenciado, malha LOD, normais, luz/sombra. **Resultado original esperado:** panorâmica com altitude validada, bordas sem fissura. **Mecanismo proposto:** DEM source, terrain LOD mesh normals/culling/shading. **Como seria editado na página Edit:** Edit Inspector scale/light; assets manifest. **Gate principal:** GPU/dataset rights and memory. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-103 — Satélite/imagens híbridas

**Contrato original:** provider com licença de audiovisual, cache permitido. **Resultado original esperado:** render 4K sem tiles faltando, atribuição obrigatória. **Mecanismo proposto:** Satellite raster + vector hybrid compositing with licensed tiles. **Como seria editado na página Edit:** Edit source/style controls. **Gate principal:** Commercial audiovisual/cache license required. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-104 — Extrusão de prédios/regiões

**Contrato original:** alturas e base de dados de edifícios, escala de câmera. **Resultado original esperado:** extrusão correta em coordenadas/referência de altura. **Mecanismo proposto:** Building footprints→extrusion, height source, occlusion and LOD. **Como seria editado na página Edit:** Edit global height/style params. **Gate principal:** Large datasets, no node-per-building promised. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-105 — Rotas sobre terreno

**Contrato original:** amostragem 3D de altitude, offset e oclusão. **Resultado original esperado:** trajetória acompanha superfície nas cenas documentadas. **Mecanismo proposto:** Route samples on DEM with altitude smoothing & occlusion. **Como seria editado na página Edit:** Edit route and terrain controls. **Gate principal:** Terrain gaps and speed/timing. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-106 — Globo ou projeções alternadas

**Contrato original:** globo esfera, Mercator/ortográfica, transições. **Resultado original esperado:** regiões polares e antimeridiano corretos nos extremos. **Mecanismo proposto:** Spherical globe projection with culling, pole/dateline and transitions. **Como seria editado na página Edit:** Edit projection & blend controls. **Gate principal:** High-risk tessellation and interaction. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-107 — Finalização avançada

**Contrato original:** múltiplos materiais, sombras e atmosfera com workflow de compositor. **Resultado original esperado:** render reproduzível, controle de qualidade e desempenho. **Mecanismo proposto:** Materials shadows atmospherics physically coherent and color managed. **Como seria editado na página Edit:** Edit style/light/global params. **Gate principal:** Full 3D node-level editing not guaranteed in Edit. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

### ADV-108 — Dataviz em movimento

**Contrato original:** linhas estatísticas animadas, séries temporais, particles opcionais. **Resultado original esperado:** leitura correta de data/fps, valores sem extrapolação. **Mecanismo proposto:** Time series joins, animated legends, lines, bars, values and particles. **Como seria editado na página Edit:** Edit property anims and dataset selector. **Gate principal:** Per-cell curves not auto-native. O teste requer cena com dados reais ou fixture determinística, reprodução no Viewer da Edit, benchmark onde cabível, relink/reopen, auditoria de licença quando houver dados externos e comparação do quadro final no Deliver.

## 19. Requisitos adicionais P1/P2, FUT e critérios transversais

- **P1 do documento de produto:** GeoJSON/TopoJSON/CSV, geocoding remoto opt-in, coropléticos, temas, partículas/rotas, fontes vetoriais extras, editor avançado de curvas e batches — preservados por módulos de import, imagem e animação. Os controles que não couberem na Edit são explicitados como limites de interface, não retirados da engine.
- **P2:** pitch/terreno/globo, satélite licenciado, extrusão, malhas, render distribuído e edição bidirecional. O Edit-first pode apresentar imagem final 3D, mas a edição *de cada componente 3D em ferramentas do Fusion* não é prometida pela interface Edit. Render distribuído precisa de reprodutibilidade, datasets deployáveis e licença.
- **Outros históricos `FUT`:** devem permanecer como ideias, nunca virar compromisso do release inicial sem aprovação e provas; especialmente import de tudo em tempo real, geração de assets por IA e 'plugin idêntico ao GeoLayers'.
- **Suporte a regiões contestadas:** dataset, versão, política de disputa e metadados sempre visíveis; cartografia de documentários não deve afirmar que fonte representa verdade jurídica única.
- **Internacionalização e acessibilidade:** UI portuguesa, contraste, teclado, nomes e unidades; scripts/tooltips da interface só quando host permite; não sequestrar atalhos globais do Resolve.
- **Segurança:** arquivo de cena nunca contém código executável arbitrário ou tokens; datasets licenciados; no downloads automáticos de tiles comunitários; log local e telemetria off por padrão.

## 20. Rastreabilidade integral dos **465 CR-RF** ao Edit-first

**Regra de classificação:** `E` = entregar comportamento usando UI nativa da Edit; `C` = entregar por motor cartográfico C++ exposto na Edit; `A` = adaptar fluxo antigo para mecanismo nativo mantendo resultado; `H` = depende de capability/prova no host; `X` = implementação antiga **não migrada** porque seria duplicação (Electron/HTML/timeline/PNG obrigatório); `Q` = qualidade/segurança/teste. Cada linha herda o texto original do inventário para auditoria. `X` **não significa perder a capacidade**: o comportamento-alvo equivalente é indicado.

A conversão por família é esta:

- **01 — cena** (`E/C`): Host params + Scene immutable snapshot + `.drp`/sidecar com hash; arquivos .cartorig legados migráveis, não substituir projeto Resolve.

- **02 — host instalação** (`A/H`): WorkflowIntegration.node/Electron deixam de existir; OFX bundle e Generator template com detection do Resolve20 e testes reais.

- **03 — catálogo GeoJSON** (`C/H`): Índice geo offline, importadores, seleção e busca via Inspector/overlay ou diálogo comprovado.

- **04 — territórios** (`C/E/H`): Render e estilos per feature; overlay para picking, slots para curvas nativas por objeto.

- **05 — marcadores/labels** (`C/E/H`): Geoanchor + text shaping + parâmetros; drag no Viewer condicionado.

- **06 — rotas** (`C/E/H`): Arc-length, Trim, morph, mover e controles tempo com native params limitados.

- **07 — camera** (`C/E`): Centro, zoom, bearing via OFX params e matemática independente.

- **08 — preview** (`A/E/H`): Preview feito no viewer do Resolve; play/stop/navegação são do host.

- **09 — motor temporal** (`C/E`): Host curves para params nativos; engine interna só para composição de objetos dinâmicos e constraints.

- **10 — timeline** (`A/E/H`): Eliminar timeline HTML; usar Edit Keyframe/Curve Editor 20 e rastrear limitações per-object.

- **11 — workspaces UI** (`A/H/X`): Eliminar standard/focus HTML, usar Edit/Viewer/Inspector; sem painéis dockáveis inventados.

- **12 — Graph/Dope Sheet** (`A/E/H`): Curve Editor 20 substitui Graph HTML para params expostos; hidden tracks não aparecem magicamente.

- **13 — PNG render** (`A/C`): Render por quadro dentro do OFX; export opcional como artefato, sem PNG seq obrigatória.

- **14 — export manager** (`A/X`): Não há import manager PNG obrigatório; usar assets/scene registries e clips do projeto.

- **15 — Fusion bridge** (`A/H`): Substituir fuscript + Lua Loader por OFX Generator / Macro, fallback apenas quando certificado.

- **16 — QA/licensing** (`Q`): Mapas corretos, erros, telemetry off, CI, host real e provenance.

### 01. Produto, projeto e ciclo de vida da cena

**Tratamento geral:** Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0001 | Criar um projeto cartográfico editável a partir de uma cena de exemplo offline. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0002 | Criar e manter título/nome da cena. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0003 | Permitir reutilizar cena de exemplo Brasil–Venezuela como ponto de partida. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0004 | Configurar FPS em 24, 25 ou 30 quadros por segundo. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0005 | Configurar duração em número inteiro de quadros, de 1 a 480 no motor atual. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0006 | Exibir duração equivalente em segundos e/ou timecode. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0007 | Navegar pelo projeto de quadro 0 até `frames - 1`. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0008 | Manter título, FPS, duração, aparência, regiões, marcadores, rotas, câmera e animações no modelo de cena. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0009 | Salvar cena editável em arquivo JSON da extensão `.cartorig.json`. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0010 | Abrir cenas salvas por caixa de diálogo do host. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0011 | Rejeitar versão de cena inválida ou estrutura sem os campos obrigatórios. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0012 | Carregar cenas legadas `version: 1` e migrá-las em memória para `version: 2`. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0013 | Salvar o modelo de cena v2 validado sem perder trilhas de animação. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0014 | Não modificar o arquivo legado de origem durante a simples abertura/migração. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0015 | Manter serialização determinística do modelo v2. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0016 | Preservar ID e referencial de objetos entre trilhas, marcadores e rotas. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0017 | Validar referências de rotas a IDs de marcadores existentes. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0018 | Validar campos de FPS, frames, câmera, cores e opacidade antes de salvar/exportar. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0019 | Limitar o arquivo JSON de cena aceito pelo host a até 2 MB. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0020 | Respeitar os limites atuais de 100 países no campo legado, 180 territórios, 300 marcadores e 300 rotas. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0021 | Rejeitar IDs duplicados de marcadores. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0022 | Permitir renomear e personalizar a cena sem regenerar os dados-base. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0023 | Atualizar as referências de preview e ferramentas após abrir outra cena. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0024 | Encurtar a duração preservando, no novo último quadro, o valor avaliado da câmera e das rotas. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0025 | Impedir que o encurtamento deixe keyframes fora do intervalo final de quadros. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0026 | Rejeitar operações com valores numéricos não finitos (`NaN`/`Infinity`). | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |
| CR-RF-0027 | Manter o projeto independente dos PNGs renderizados: JSON é fonte editável, PNG é saída. | E/C | Scene canônica versionada com dados pequenos persistidos no host e assets externos com relink. |

### 02. Instalação, inicialização e integração do host

**Tratamento geral:** Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0028 | Distribuir a interface como Workflow Integration para DaVinci Resolve Studio Windows. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0029 | Instalar com `Install.cmd`/`Install.ps1` por PowerShell, fechando o Resolve antes. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0030 | Copiar os arquivos do plugin para o caminho de integração do Resolve sob `com.cartorig.maps`. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0031 | Procurar `WorkflowIntegration.node` em caminhos conhecidos do SDK/instalação. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0032 | Solicitar caminho do módulo nativo quando a detecção automática falhar. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0033 | Usar o `WorkflowIntegration.node` fornecido pela instalação do usuário, sem redistribuí-lo. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0034 | Registrar a integração de workflow com identidade e manifesto CartoRig. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0035 | Instalar o script Lua de fallback no menu `Workspace → Scripts → Utility` do Resolve. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0036 | Disponibilizar opção de instalação manual para diagnóstico. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0037 | Desinstalar apenas os componentes instalados pela identidade CartoRig. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0038 | Exigir confirmação explícita `REMOVER` na desinstalação. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0039 | Preservar arquivos de cena e sequências exportadas fora da pasta do plugin ao desinstalar. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0040 | Inicializar interface local em Electron/Chromium com dados cartográficos básicos offline. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0041 | Exibir e atualizar status de conexão com o Resolve e identificação da timeline, quando disponível. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0042 | Não exigir Node.js/npm como pré-requisito para uso normal no Resolve. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0043 | Oferecer preview independente em navegador para recursos que não precisam da ponte IPC. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0044 | Desativar recursos dependentes de host quando a ponte Electron/Resolve não estiver presente. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0045 | Aplicar isolamento de contexto e expor API limitada via `contextBridge`/preload. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0046 | Manter Node integration desabilitada na página de interface. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0047 | Impedir navegação arbitrária da janela e manter CSP de recursos locais. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0048 | Solicitar downloads geográficos apenas sob ação explícita do usuário. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0049 | Preservar preferência manual de `External scripting: Local`, sem ativá-la automaticamente. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0050 | Não exigir conta, login ou autenticação de provedor de mapas para os recursos offline. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0051 | Não enviar telemetria nem dados do usuário automaticamente. | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |
| CR-RF-0052 | Certificar a compatibilidade real com Resolve Studio 20.x/21.x em matriz de instalações Windows (os testes Lua atuais são simulados). | A/H | Converter em OFX bundle / startup no Resolve Studio 20; ignorar integração Electron/Workflow e testar ABI. |

### 03. Catálogos, pesquisa geográfica e GeoJSON

**Tratamento geral:** Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0053 | Carregar catálogo offline básico com aproximadamente 173 feições geográficas simplificadas. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0054 | Localizar países pelo nome via pesquisa textual. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0055 | Normalizar acentos e caixa na busca de nomes. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0056 | Adicionar países encontrados à seleção cartográfica. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0057 | Identificar países por código ISO-3 do conjunto de dados. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0058 | Disponibilizar seleção por continente, país, estado/província e cidade como categorias de UI. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0059 | Agrupar países por continente a partir do catálogo local. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0060 | Adicionar um continente como conjunto de países, e não como polígono continental único. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0061 | Pesquisar e adicionar múltiplos países à composição. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0062 | Impedir entrada de códigos de países inexistentes. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0063 | Pesquisar capitais/cidades básicas do catálogo offline como pontos. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0064 | Preencher coordenadas de marcador a partir de uma cidade selecionada. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0065 | Mostrar a indisponibilidade de estados/províncias não carregados. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0066 | Oferecer download opcional de estados/províncias Natural Earth. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0067 | Oferecer download opcional de cidades Natural Earth. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0068 | Buscar dados extras somente por endereços HTTPS previamente autorizados. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0069 | Armazenar dados extras sob cache local CartoRig/geodata. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0070 | Carregar novamente dados opcionais do cache sem novo download. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0071 | Importar arquivo local `GeoJSON FeatureCollection` compatível. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0072 | Aceitar geometrias `Polygon` válidas para fronteiras. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0073 | Aceitar geometrias `MultiPolygon` válidas para fronteiras. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0074 | Aceitar feições `Point` para cidades. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0075 | Validar coordenadas WGS84 (longitude/latitude em graus) e anéis de polígonos. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0076 | Garantir ou reconstruir fechamento válido de anéis poligonais quando necessário. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0077 | Descartar pontos inválidos de anéis recuperáveis e rejeitar geometrias insanáveis. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0078 | Rejeitar estrutura que não seja `FeatureCollection`. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0079 | Limitar complexidade e tamanho dos dados GeoJSON importados. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0080 | Disponibilizar carregamento de geometrias por ID via IPC do host. | X/A | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0081 | Rejeitar consulta a categorias de dados geográficos não autorizadas. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0082 | Rejeitar identificadores geográficos com formato/comprimento inválido. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0083 | Persistir geometria de regiões selecionadas no projeto para manter portabilidade. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0084 | Permitir usar dados de países sem rede ou API comercial de mapas. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0085 | Cobrir globalmente limites administrativos municipais como polígonos (cidades atuais são pontos). | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0086 | Suportar SHP, GeoPackage e outros formatos geográficos sem conversão externa para GeoJSON WGS84. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |
| CR-RF-0087 | Consultar e mostrar dados de geocodificação de endereços em serviço externo. | C/H | Core geo e catálogo offline; consulta/arquivo no Inspector ou overlay apenas com host POC. |

### 04. Territórios, seleção, aparência e composição visual

**Tratamento geral:** Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0088 | Criar território destacado ao selecionar país/região compatível. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0089 | Selecionar diversos territórios simultaneamente na mesma cena. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0090 | Remover território destacado da composição. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0091 | Mostrar nome, tipo e identificação do território selecionado. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0092 | Editar cor de preenchimento individual do território. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0093 | Editar cor da borda individual do território. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0094 | Editar opacidade final do território no intervalo 0–1. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0095 | Definir quadro inicial do aparecimento do destaque. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0096 | Definir quadro final da transição de aparecimento (fade). | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0097 | Permitir aparecimento instantâneo quando início e fim coincidem. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0098 | Calcular opacidade intermediária conforme o tempo da cena. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0099 | Ocultar o destaque antes do quadro inicial. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0100 | Manter a opacidade configurada depois da transição. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0101 | Editar o estilo global do oceano. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0102 | Editar o estilo global da massa terrestre. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0103 | Editar estilo padrão de novos territórios destacados. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0104 | Editar estilo global das fronteiras. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0105 | Editar cor padrão de rotas e pontos. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0106 | Manter estilos individuais independentes dos padrões globais após serem atribuídos. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0107 | Desenhar linhas de grade geográfica no mapa base. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0108 | Controlar ordem de renderização, priorizando regiões continentais/países/subdivisões. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0109 | Desenhar apenas geometrias disponíveis e válidas, sem criar polígonos fictícios. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0110 | Renderizar destaques em camada `highlights` independente da base. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0111 | Preservar estilo da cena ao salvar/abrir projeto JSON. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0112 | Permitir reverter alterações de cor pelos controles antigos usando histórico de Undo. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |
| CR-RF-0113 | Preservar keyframes avançados de opacidade: controles legados não podem sobrescrever trilhas de 3+ keys ou Bézier. | C/E/H | Render territórios nativos por frame; estilos em scene + Curve Edit para slots quando possível. |

### 05. Marcadores, cidades e rótulos

**Tratamento geral:** Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0114 | Criar marcador com latitude e longitude decimais. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0115 | Criar marcador selecionando cidade pré-cadastrada. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0116 | Usar duplo clique no mapa para preencher coordenadas de um marcador. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0117 | Definir nome/rótulo de texto do marcador. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0118 | Definir cor individual do ponto. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0119 | Definir tamanho/raio individual do ponto. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0120 | Exibir ponto na localização projetada no mapa. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0121 | Exibir rótulo legível próximo ao ponto, conforme regras atuais do SVG. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0122 | Manter marcadores diferentes na mesma cena. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0123 | Selecionar marcadores existentes como origem e destino de rota. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0124 | Remover marcador e impedir rotas com referências inválidas no resultado validado. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0125 | Persistir marcadores no JSON editável. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0126 | Não aceitar coordenadas vazias ou fora dos intervalos geográficos válidos. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0127 | Escapar caracteres especiais de rótulos ao produzir SVG. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0128 | Renderizar marcadores e rótulos na camada raster `markers` quando exportação separada. | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |
| CR-RF-0129 | Criar rótulos vetoriais editáveis como Text+ nativo no Fusion (atualmente ficam rasterizados). | C/E/H | Marcadores geoancorados e rótulos no rasterizador; Viewer overlay condicionado ao host. |

### 06. Rotas e setas animadas — funcionalidade atual

**Tratamento geral:** Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0130 | Criar rota entre dois marcadores distintos da mesma cena. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0131 | Selecionar explicitamente marcador de origem. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0132 | Selecionar explicitamente marcador de destino. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0133 | Oferecer rota como linha contínua. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0134 | Oferecer rota com estilo tracejado. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0135 | Oferecer seta animada com ponta direcional. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0136 | Definir cor individual da rota. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0137 | Definir espessura em pixels da rota. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0138 | Definir curvatura percentual da rota entre dois pontos. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0139 | Definir quadro inicial da animação de revelação da rota. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0140 | Definir quadro final da animação de revelação da rota. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0141 | Não renderizar a rota antes de seu quadro inicial. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0142 | Revelar progressivamente o traçado conforme avanço dos quadros. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0143 | Fazer a ponta da seta acompanhar a fração revelada do traçado. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0144 | Projetar a rota como curva quadrática sobre o mapa 2D. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0145 | Permitir múltiplas rotas na mesma cena. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0146 | Manter intervalos temporais diferentes entre rotas. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0147 | Salvar e abrir rotas com o projeto. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0148 | Usar trilha `progress` independente para keyframes de progresso na cena v2. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0149 | Preservar animação de rota ao alterar duração da cena, avaliando o novo último frame. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0150 | Rejeitar origem/destino inexistentes e intervalos fora da duração. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0151 | Rejeitar curvaturas de magnitude incompatível com os limites validados. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0152 | Renderizar todas as rotas na camada raster `routes` na exportação separada. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0153 | Evitar que o painel antigo de Início/Fim substitua trilhas de rota com easing/keyframes avançados. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |
| CR-RF-0154 | Controlar geometricamente uma rota com três ou mais waypoints e alças espaciais independentes. | C/E/H | Rota com arc-length e controles de progressão/estilo; binds nativos conforme slots limitados. |

### 07. Câmera, cartografia 2D e navegação

**Tratamento geral:** Câmera matemática nativa; animar canais independentes no Curve Editor Edit.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0155 | Controlar câmera por longitude do centro em graus. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0156 | Controlar câmera por latitude do centro em graus. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0157 | Controlar câmera por zoom numérico de 0 a 7. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0158 | Definir quadro/pose inicial e final de câmera no modo legado. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0159 | Interpolar poses de câmera com suavização temporal. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0160 | Usar o arco longitudinal curto ao atravessar o antimeridiano. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0161 | Restringir latitude à faixa válida da projeção Mercator adotada. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0162 | Projetar geometria geográfica no plano 2D da viewport. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0163 | Converter coordenadas de pixels do mapa em longitude/latitude para operações interativas. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0164 | Disponibilizar botões de aproximar e afastar zoom. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0165 | Permitir explorar a câmera temporariamente sem escrever keyframes quando Auto Key está desativado. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0166 | Arrastar com mouse para deslocar mapa horizontalmente no sentido natural. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0167 | Arrastar com mouse para deslocar mapa verticalmente no sentido natural (corrigido v0.3.3). | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0168 | Permitir gesto de zoom pela roda do mouse. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0169 | Permitir voltar/recentralizar câmera ao estado de referência. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0170 | Enquadrar automaticamente territórios selecionados pelo comando simples `Centralizar territórios`. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0171 | Copiar posição/zoom da câmera atual para pose inicial ou final. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0172 | Criar poses intermediárias de longitude, latitude e zoom via keyframes v2. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0173 | Registrar os três canais de câmera em um único comando reversível. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0174 | Manter a câmera atual no preview sincronizada ao quadro ativo. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0175 | Interromper reprodução ao iniciar arraste que exija editar/explorar câmera. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0176 | Preservar poses intermediárias quando a pose extrema é alterada. | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0177 | Permitir rotação/bearing da câmera durante a renderização do mapa (atualmente não suportado). | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |
| CR-RF-0178 | Permitir caminho espacial Bézier editável para a câmera (não confundir com easing temporal). | C/E | Câmera matemática nativa; animar canais independentes no Curve Editor Edit. |

### 08. Prévia, reprodução e interação com mapa

**Tratamento geral:** Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0179 | Exibir preview cartográfico atualizado de cada frame da cena. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0180 | Exibir nome da cena e coordenadas/zoom da câmera. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0181 | Reproduzir sequencialmente os quadros no preview. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0182 | Pausar reprodução. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0183 | Retornar ao primeiro quadro. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0184 | Navegar para quadros por régua, timeline e controles temporais. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0185 | Sincronizar valor de frame exibido e renderização de mapa. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0186 | Usar resultados do mesmo avaliador para preview e exportação SVG/PNG. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0187 | Exibir mudanças nos destaques, rotas e câmera durante a reprodução. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0188 | Atualizar preview ao selecionar ou modificar keyframe. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0189 | Exibir notificações de sucesso, estado e erro ao usuário. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0190 | Oferecer preview estático sem Resolve para edição que não precisa de escrita em disco pelo host. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0191 | Permitir a interação com a superfície do mapa para pan, zoom e ponto de marcador. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0192 | Preservar a câmera do frame atual ao alternar modos de workspace. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0193 | Manter apenas uma instância do mapa mesmo com preview flutuante no modo Foco. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |
| CR-RF-0194 | Reproduzir áudio/narração com waveform sincronizada à timeline para animar por falas. | A/E/H | Usar Viewer/Playhead/transport do Resolve; overlay só para edição espacial aprovada. |

### 09. Motor de animação, formato v2 e interpolação

**Tratamento geral:** Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0195 | Representar animação por trilhas (`tracks`) vinculadas a objeto e propriedade específicos. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0196 | Permitir mais de dois keyframes em uma propriedade. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0197 | Manter keyframes ordenados por frame inteiro. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0198 | Impedir dois keyframes distintos no mesmo quadro e mesma trilha, substituindo valor quando aplicável. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0199 | Definir chave por ID único, quadro, valor, modo de interpolação e parâmetros quando presentes. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0200 | Avaliar cada quadro de forma determinística, independente de relógio e DOM. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0201 | Permitir interpolação temporal Linear. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0202 | Permitir interpolação temporal Hold/Step. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0203 | Permitir interpolação temporal Smoothstep. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0204 | Preservar Smoothstep legado para equivalência de cenas antigas. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0205 | Permitir interpolação temporal cubic Bézier com controle `x1/y1/x2/y2`. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0206 | Rejeitar Bézier inválida com coordenadas de controle temporal fora do domínio permitido. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0207 | Respeitar valores exatamente nos extremos dos segmentos. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0208 | Avaliar adequadamente zero, um e três ou mais keyframes. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0209 | Implementar comportamento antes do primeiro keyframe (base/constante/preValue, conforme trilha). | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0210 | Implementar comportamento depois do último keyframe. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0211 | Não modificar o objeto-fonte durante avaliação. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0212 | Permitir trilhas independentes para longitude, latitude e zoom de câmera. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0213 | Permitir trilha independente de opacidade de território. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0214 | Permitir trilha independente de progresso de rota. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0215 | Permitir habilitar/desabilitar trilha de animação no contrato. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0216 | Impedir escrita em trilha bloqueada por comandos de edição. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0217 | Rejeitar valor incompatível com tipo da propriedade. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0218 | Validar IDs de objeto/trilha antes de comando. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0219 | Expor operações `keyframe.upsert`, exclusão, movimento, cópia e alteração de easing. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0220 | Expor operação de escala temporal de grupos (`keyframes.scale`) no motor — sem afirmar UI completa de retiming. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0221 | Executar alterações de cena com comandos e inversas para Undo. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0222 | Migrar câmera legada inicial/final preservando a curva visual anterior. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0223 | Migrar fades territoriais e progresso de rotas anteriores sem mudança visual perceptível. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0224 | Garantir comparação SVG de cenas antigas e convertidas em testes de regressão. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0225 | Serializar e validar modelo `version:2` para salvar e renderizar. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0226 | Empacotar bundle do motor localmente para Electron, sem CDN. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0227 | Evitar recomputação baseada em parâmetros secretos/aleatórios em avaliação. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |
| CR-RF-0228 | Expor todos os tipos já previstos no catálogo (`color`, `vector2`, `angle`, etc.) como propriedades efetivamente editáveis na interface — tipos definidos não significam efeitos implementados. | E/C | Timebase OFX + parâmetros host-owned e scene tracks para propriedades não expostas; avaliar sem timer HTML. |

### 10. Timeline, keyframes e comandos de edição

**Tratamento geral:** Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0229 | Exibir timeline de animação com uma régua temporal compartilhada. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0230 | Exibir trilha por propriedade animável de cada objeto. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0231 | Agrupar trilhas de câmera, regiões e rotas por objeto. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0232 | Expandir e recolher grupos de propriedades. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0233 | Identificar propriedades por nomes legíveis em português. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0234 | Representar keyframes visíveis como losangos nas trilhas. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0235 | Diferenciar visualmente keyframe selecionado. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0236 | Posicionar playhead no quadro correspondente na régua. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0237 | Clicar na régua para navegar ao quadro. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0238 | Arrastar continuamente o playhead com botão esquerdo pressionado (v0.3.3). | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0239 | Arrastar na área vazia de trilha para navegar continuamente sem exigir ponto específico. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0240 | Reservar Shift+arrastar para seleção temporal por intervalo. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0241 | Permitir selecionar keyframe individual com clique. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0242 | Permitir selecionar vários keyframes por Shift+clique. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0243 | Permitir selecionar keyframes dentro de um intervalo temporal. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0244 | Permitir mover keyframes arrastando horizontalmente. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0245 | Permitir mover conjunto selecionado por comando atômico. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0246 | Rejeitar movimento de keyframes para quadros fora da cena. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0247 | Rejeitar colisão temporal com keyframe existente na trilha. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0248 | Criar keyframe da propriedade selecionada no quadro atual. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0249 | Excluir keyframes selecionados sem afetar trilhas não relacionadas. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0250 | Navegar até keyframe anterior/próximo de trilha selecionada. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0251 | Copiar keyframes e offsets relativos. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0252 | Colar keyframes usando quadro atual como âncora temporal. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0253 | Rejeitar colagem em quadros ocupados ou fora da duração. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0254 | Exibir zoom horizontal da timeline. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0255 | Preservar scroll/zoom horizontal compartilhado nas trilhas. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0256 | Permitir aumentar verticalmente a área da timeline. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0257 | Oferecer Snap a frames/keyframes próximos, marcadores e playhead. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0258 | Permitir ligar/desligar Snap. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0259 | Criar marcador temporal no frame atual. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0260 | Manter Auto Key visível e ativável. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0261 | Com Auto Key, criar keyframe ao mudar uma propriedade animável pelo inspetor. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0262 | Com Auto Key, registrar câmera no fim de arraste do mapa. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0263 | Com Auto Key, registrar alteração de zoom pelos botões da câmera. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0264 | Consolidar gesto contínuo de roda do mouse em uma única gravação de pose. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0265 | Sem Auto Key, não criar poses ao apenas navegar pelo mapa. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0266 | Registrar câmera manualmente com latitude, longitude e zoom na mesma ação. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0267 | Reverter pose completa de câmera com um único Undo. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0268 | Fornecer Undo/Redo para alterações de keyframes, easing e demais ações cobertas pelo histórico. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0269 | Fornecer atalho `Ctrl+K` para registrar pose da câmera. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0270 | Fornecer atalho `Espaço` para reproduzir/pausar quando fora de campos de texto. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0271 | Fornecer setas esquerda/direita para caminhar 1 frame e Shift+setas para 10 frames. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0272 | Fornecer `Home` e `End` para primeiro e último frame. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0273 | Fornecer `Ctrl+Z`/`Ctrl+Y`, copiar/colar e exclusão via atalhos. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0274 | Respeitar foco de input/textarea/select ao decidir consumir atalhos globais. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0275 | Exibir inspector contextual com valor, quadro, propriedade e interpolação. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0276 | Permitir editar frame de keyframe selecionado por campo numérico. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0277 | Permitir alterar valor numérico de keyframe selecionado. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0278 | Permitir escolher interpolação individual por segmento. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0279 | Permitir editar valor-base da propriedade via opção avançada. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0280 | Manter estado de seleção coerente após criar/colar/registrar pose. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0281 | Apresentar instruções de uso/atalhos no editor. | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |
| CR-RF-0282 | Oferecer retiming visual em escala com alças de conjunto e seleção ampla (o motor já suporta operação de escala, mas a interface ainda é limitada). | E/H | Usar Keyframe/Curve Editor Edit 20 em vez da timeline HTML; verificar paridade gestual/temporal. |

### 11. Workspaces, navegação, Inspector e preview flutuante

**Tratamento geral:** Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0283 | Oferecer Modo Padrão com mapa grande e timeline inferior. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0284 | Oferecer Modo Foco com timeline maximizada na área útil da janela. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0285 | Oferecer único botão `Expandir timeline` para entrar no Modo Foco. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0286 | Oferecer `Restaurar layout` para retornar ao Modo Padrão. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0287 | Permitir restaurar modo padrão com Esc fora de diálogo modal. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0288 | Disponibilizar atalho de troca de layout configurado pelo editor (`Ctrl+Shift+F`). | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0289 | Preservar uma única instância de mapa, timeline e Inspector ao trocar modo. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0290 | Preservar quadro/playhead atual entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0291 | Preservar keyframes e trilha selecionados entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0292 | Preservar zoom e posição de rolagem entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0293 | Preservar grupos de propriedades abertos/recolhidos entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0294 | Preservar flags Auto Key e Snap entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0295 | Preservar histórico Undo/Redo entre os modos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0296 | Não modificar a cena nem criar entrada de histórico só por alternar layout. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0297 | Permitir árvore pesquisável de objetos e propriedades no Modo Foco. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0298 | Filtrar trilhas por termo buscado na árvore. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0299 | Sincronizar escolha da árvore com timeline, Inspector e Graph Editor. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0300 | Oferecer colunas de objetos, edição central e Inspector no Modo Foco. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0301 | Oferecer painel Inspector ao lado da timeline no layout refinado. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0302 | Alternar entre Graph Editor e Dope Sheet na parte inferior. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0303 | Disponibilizar preview flutuante do mapa no Modo Foco. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0304 | Permitir mostrar/ocultar preview flutuante. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0305 | Permitir reposicionar preview flutuante arrastando barra de título. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0306 | Permitir redimensionar preview flutuante. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0307 | Restaurar o preview ao mapa principal no Modo Padrão. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0308 | Oferecer comando `Enquadrar cena` para ajustar a escala da duração. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0309 | Oferecer comando `Enquadrar seleção` para ajustar o foco temporal dos keyframes selecionados. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0310 | Mostrar timecode de frame por FPS em `HH:MM:SS:FF` sem drop-frame. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0311 | Manter comandos reais de salvar/exportar acessíveis nos layouts adequados. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0312 | Manter botão `Gerar no Fusion` acessível no rodapé do Modo Foco. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0313 | Apresentar ligação real com os botões existentes de playback, Snap, Auto Key e edição. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0314 | Usar nomes/identificação de objetos existentes em vez de controles meramente ilustrativos. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0315 | Aplicar padrão de layout desktop nas resoluções testadas 1280×720, 1672×941 e 2560×1440. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0316 | Eliminar menu superior Animação quando apenas duplicava a expansão (v0.3.3). | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0317 | Eliminar botões sem ação de Exportação no menu superior e lateral sem remover os comandos reais. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0318 | Remover cartões duplicados de seleção de layouts de trabalho. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0319 | Posicionar ações úteis do cabeçalho próximo ao título Timeline Focus em vez de centralizadas arbitrariamente. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |
| CR-RF-0320 | Fornecer certificação visual pixel a pixel contra as imagens de referência em Windows/Resolve, com DPI e fontes do host real. | A/H/X | Substituir modos padrão/foco HTML pelo workspace Edit; Inspector do host, sem painel dockável próprio. |

### 12. Graph Editor, Dope Sheet e curvas de velocidade atuais

**Tratamento geral:** Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0321 | Exibir gráfico das amostras reais calculadas pelo avaliador da trilha selecionada. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0322 | Exibir eixos de tempo (frame) e valor no Graph Editor. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0323 | Exibir playhead sobre o gráfico sincronizado com a timeline. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0324 | Plotar pontos reais de keyframe da trilha. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0325 | Selecionar keyframe da trilha ao clicar perto de seu ponto na curva. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0326 | Exibir curva representativa para propriedades numéricas, longitude e progresso de rota suportados. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0327 | Respeitar interpolação Hold/Step no gráfico de valores. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0328 | Alternar Graph Editor/Dope Sheet sem alterar a cena. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0329 | Listar keyframes reais da trilha selecionada no Dope Sheet. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0330 | Selecionar keyframe pelo Dope Sheet, sincronizando tempo e Inspector. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0331 | Exibir miniatura de easing temporal no Inspector. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0332 | Oferecer interpolação Linear, Hold, Suave, Suave (legado) e Bézier avançada. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0333 | Oferecer presets de easing temporal Entrada, Saída e Suave. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0334 | Expor alças Bézier temporais (`x1/y1/x2/y2`) no editor quando aplicáveis. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0335 | Permitir arrastar diretamente as duas alças no mini-editor Bézier. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0336 | Permitir no Graph Editor arrastar alças de um segmento numérico (v0.3.3). | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0337 | Permitir arrastar o trecho selecionado da curva de interpolação para alterar speed ramp (v0.3.3). | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0338 | Persistir as alterações de easing no keyframe de saída do segmento, e não somente no desenho. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0339 | Atualizar prévia/curva após alterar valores Bézier. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0340 | Agrupar cada gesto Bézier em uma única entrada de Undo. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0341 | Desfazer/refazer a edição de speed ramp. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0342 | Cancelar gesto de edição sem gravar alteração. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0343 | Rejeitar entradas ou alças que produzam curva temporal inválida. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0344 | Oferecer editor profissional de curvas de velocidade com visualização `valor x tempo` e `velocidade x tempo` alternativas. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0345 | Oferecer controle completo de tangentes e pesos por keyframe de vários canais simultaneamente. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |
| CR-RF-0346 | Oferecer retiming avançado direto no Graph Editor em trechos múltiplos. | E/H | Curve Editor 20 substitui Graph; curvas internas não são editáveis nativamente sem binding/slot. |

### 13. Renderização SVG e exportação PNG/frames

**Tratamento geral:** Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0347 | Gerar mapa vetorial intermediário SVG para o frame avaliado. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0348 | Rasterizar SVG no preview/exportação para PNG. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0349 | Exportar imagem estática do frame selecionado. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0350 | Oferecer saída HD 1280×720. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0351 | Oferecer saída Full HD 1920×1080. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0352 | Oferecer saída UHD 3840×2160. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0353 | Exportar sequências com FPS da cena 24, 25 ou 30. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0354 | Exportar de 1 a 480 quadros por cena no limite atual. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0355 | Oferecer exportação com quatro camadas separadas. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0356 | Gerar camada `base` com oceano, terras, fronteiras e grade. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0357 | Gerar camada `highlights` com destaques territoriais. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0358 | Gerar camada `routes` com linhas/setas. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0359 | Gerar camada `markers` com pontos e textos. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0360 | Oferecer exportação alternativa de camada única `composite`. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0361 | Gerar arquivos com padrão `map_0000.png`, `map_0001.png`, etc. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0362 | Criar diretório individual por título de cena e timestamp. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0363 | Gerar arquivo `scene.cartorig.json` junto à sequência. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0364 | Gerar `export.json` com FPS, largura, altura, total e lista de camadas. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0365 | Gerar `CREDITOS.txt` para atribuição de dados cartográficos. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0366 | Exibir progresso do render e opção de cancelamento. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0367 | Não declarar concluída uma exportação cancelada. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0368 | Preservar diretório parcial e registrar `INCOMPLETO.txt` quando cancelada. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0369 | Validar índices de quadro no IPC antes da gravação. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0370 | Validar lista de camadas permitidas no IPC. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0371 | Validar integridade do PNG recebido antes de gravar no disco. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0372 | Validar dimensões de PNG segundo resolução escolhida. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0373 | Evitar sobrescrever frames já gravados com o mesmo índice/camada. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0374 | Impedir finalização sem completar os PNGs esperados. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0375 | Preservar transparência das camadas raster destinadas à composição. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0376 | Assegurar que caracteres de rótulos sejam escapados para não gerar SVG inválido. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0377 | Exportar sequências acima de 480 quadros com chunks e retomada após interrupção. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |
| CR-RF-0378 | Renderizar apenas quadros afetados por mudanças de keyframe, sem repetir o material idêntico. | A/C | Render OFX por quadro no host, não pré-render de PNG; export de imagem vira opcional. |

### 14. Gerenciador de sequências exportadas

**Tratamento geral:** Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0379 | Oferecer comando de abrir `Gerenciar sequências exportadas / importar no Fusion`. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0380 | Solicitar pasta principal de exportações por seletor de diretório. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0381 | Aceitar seleção direta da pasta de uma única exportação. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0382 | Descobrir exports nas subpastas imediatas da pasta escolhida. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0383 | Não varrer recursivamente diretórios arbitrariamente profundos. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0384 | Limitar quantidade de exports descobertos por busca. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0385 | Exibir lista de cenas/exportações encontradas. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0386 | Pesquisar cenas da lista por nome/título. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0387 | Exibir título, nome da pasta e metadados disponíveis. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0388 | Exibir resolução, FPS e duração derivada de frames/FPS. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0389 | Exibir número e tipos de camadas da exportação. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0390 | Exibir primeira imagem de cada camada quando houver `nativeImage` disponível. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0391 | Combinar as prévias das camadas na interface quando possível. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0392 | Distinguir exportação válida de manifest malformado na listagem. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0393 | Validar formato e tamanho de `export.json`. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0394 | Validar campos de FPS, dimensões, total de frames e lista de camadas. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0395 | Validar existência de todos os PNGs esperados em cada camada. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0396 | Validar assinatura PNG, chunk de início `IHDR`, largura/altura e fim `IEND`. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0397 | Rejeitar PNG ausente, truncado, simbólico/arquivo não regular ou com dimensão divergente. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0398 | Exibir erro específico de camada e frame quando a sequência é incompleta. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0399 | Bloquear importação enquanto a exportação selecionada não passou na validação. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0400 | Revalidar exportação imediatamente antes da importação no Fusion. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0401 | Não modificar timeline nem projeto ao apenas listar/inspecionar sequências. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0402 | Permitir cancelar seleção ou fechar gerenciador sem importar. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0403 | Exigir ação explícita `Confirmar importação no Fusion`. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0404 | Usar identificadores opacos de exportação em vez de aceitar caminho arbitrário enviado pela UI. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0405 | Impedir tentativa de importar uma exportação fora do diretório autorizado na sessão. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |
| CR-RF-0406 | Reaproveitar PNGs já exportados sem renderizar novamente. | A/X | Substituir gerenciador de sequências por scene/asset registry e Timeline Media Pool; preservar recuperação, não UI PNG. |

### 15. Integração DaVinci Resolve / Fusion

**Tratamento geral:** Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0407 | Oferecer botão `Gerar no Fusion` para renderizar e iniciar inserção da composição. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0408 | Exigir uma exportação válida antes de tentar inserção. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0409 | Preparar arquivo `.comp` de fallback ao gerar exportação. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0410 | Gerar composição com Loader para cada sequência/camada. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0411 | Gerar nós Merge para combinar quatro camadas com ordenação prevista. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0412 | Gerar saída `MediaOut` para composição. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0413 | Evitar Merge desnecessário quando há camada única composite. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0414 | Definir referências relativas/seguras às sequências para arquivo `.comp`. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0415 | Gerar arquivo de job/instruções do executor Lua. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0416 | Localizar `fuscript.exe` em caminhos oficiais do Resolve no Windows. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0417 | Permitir override verificável de localização de `fuscript.exe` em instalações personalizadas. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0418 | Executar script Lua para tentar criar Fusion Composition na timeline ativa. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0419 | Criar e conectar loaders/merges/media output por API Lua quando disponível. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0420 | Usar `Composition.Lock/Unlock` para evitar diálogos Open File durante criação de Loaders. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0421 | Garantir Unlock também em caminhos de falha/erro. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0422 | Oferecer alternativa de invocação pelo menu Scripts → Utility. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0423 | Oferecer fallback manual importando `CartoRig.comp` para composição vazia. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0424 | Oferecer alternativa de importar sequências PNG manualmente pelo Media Pool. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0425 | Informar caminho dos arquivos de fallback quando inserção automática não puder ser confirmada. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0426 | Interpretar registro estruturado de resultado Lua `OK\|IMPORTED`. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0427 | Interpretar estado parcial `PARTIAL` quando clipe foi criado sem completar os nós. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0428 | Não tratar erro de processo ou ausência de confirmação Lua como sucesso. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0429 | Distinguir confirmação do Lua do mero exit code do executável. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0430 | Impedir repetição da mesma tentativa/job idempotente pelo script Lua. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0431 | Permitir importar novamente a mesma exportação após excluir clipe da timeline (v0.2.9). | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0432 | Permitir importar cópia intencional da mesma exportação em outra timeline. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0433 | Exigir confirmação extra quando existe importação anterior OK, parcial ou incerta. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0434 | Não bloquear permanentemente o reuso porque `cartorig-fusion-result.txt` antigo existe. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0435 | Criar ID de tentativa e diretório isolado em `cartorig-imports/<id>`. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0436 | Registrar resultados de tentativas diferentes sem sobrescrever histórico. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0437 | Rejeitar importações simultâneas ou duplo clique concorrente. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0438 | Cancelar tentativa antes de iniciar sem criar job. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0439 | Preservar PNGs diante de falha, cancelamento ou inserção parcial do Fusion. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0440 | Validar caminhos de pastas/nomes antes de gerar referência de Loader ou script. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0441 | Conservar alternativa raster de quatro camadas como contrato principal do Fusion. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0442 | Converter keyframes cartográficos em ferramentas/nós nativos Fusion editáveis na timeline do Resolve, por propriedade suportada. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0443 | Confirmar automaticamente existência atual de um clipe inserido na timeline quando a API disponível permitir consulta confiável. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |
| CR-RF-0444 | Certificar no Resolve Windows real duração/clipe, Loader, Merge, MediaOut e sincronização de FPS para versões 20/21. | A/H | Inserção e edição via OFX Generator/Filter ou Macro; remover ponte Lua externa/Loader PNG. |

### 16. Comportamentos de erro, acessibilidade e documentação funcional

**Tratamento geral:** Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante.

| ID | Requisito original resumido | Destino | Conversão para Edit-first |
| --- | --- | --- | --- |
| CR-RF-0445 | Fornecer mensagens de erro legíveis ao rejeitar exportação ou cena inválida. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0446 | Não abrir diálogo do host ao apenas inspecionar metadados de exportação. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0447 | Rejeitar entrada de cena com rotas apontando para IDs ausentes. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0448 | Rejeitar dimensões de exportação divergentes dos presets disponíveis. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0449 | Proteger paths e arquivos envolvidos em exportação/importação contra nomes perigosos. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0450 | Exibir estados de conexão e status da exportação em vez de presumir sucesso. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0451 | Permitir desfazer alterações após edição visual de câmera, fade e keyframes. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0452 | Impedir que arraste de alça Bézier cancelado crie alteração de cena. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0453 | Fornecer foco visível e títulos acessíveis aos principais controles de keyframes. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0454 | Oferecer `aria-label`/títulos para mapa, trilhas e botões conforme implementação atual. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0455 | Manter documentação de instalação, funcionamento e solução de problemas em português. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0456 | Documentar limitações de precisão da cartografia e atribuições de dados. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0457 | Preservar avisos de terceiros e licença MIT do código. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0458 | Separar recursos confirmados por teste automatizado de integração ainda não certificada no Resolve real. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0459 | Oferecer testes `npm test`, `npm run test:contracts` e `npm run test:lua` para o código. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0460 | Oferecer testes em Chromium em múltiplos tamanhos de viewport. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0461 | Executar workflow GitHub Actions em PR/push com Node, Lua e Chromium (branch v0.3.3). | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0462 | Registrar screenshots/relatórios de QA como artefatos de CI. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0463 | Executar verificação de sintaxe dos módulos JS e bundle determinístico no workflow. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0464 | Publicar evidência automatizada de comparação pixel a pixel com referências de design reproduzíveis. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |
| CR-RF-0465 | Automatizar E2E real de DaVinci Resolve Studio Windows com SDK e vídeo renderizado. | Q | Migrar regra para QA/segurança e host E2E Resolve20; Chromium pode deixar de ser relevante. |

## 21. Matriz de **129 casos de teste** — conversão explícita para a Edit 20

O resultado esperado do teste de origem é preservado como requisito funcional quando continua pertinente; quando o caso original valida DOM/PNG/Lua externo, transforma-se o **mecanismo de execução** para OFX/Viewer/Edit/Deliver. TDD de matemática continua independente do host, mas cada aceite de UI exige execução real no Resolve Studio 20. O pré-requisito `Setup` original é mantido como texto histórico, não como protocolo necessariamente aplicável no novo produto.

### T-KF01-01 — KF-01 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Track zoom com keys f0/f10/f20 e busca em f15. **Resultado original esperado:** Avaliar segmento correto; f15 interpolado entre f10 e f20. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF01-02 — KF-01 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Adicionar dois keys no mesmo frame 10. **Resultado original esperado:** Upsert substitui, não duplica. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF02-01 — KF-02 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Câmera, Brasil e rota com tracks visíveis. **Resultado original esperado:** Trilhas hierárquicas em ordem estável e seleção consistente. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF02-02 — KF-02 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Expandir/colapsar centenas de trilhas durante reprodução. **Resultado original esperado:** Nenhuma seleção perdida; render não altera foco. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF03-01 — KF-03 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Auto Keyframe ON + mover zoom no f37. **Resultado original esperado:** Criar key zoom f37; lon/lat preservados. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF03-02 — KF-03 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Auto Keyframe OFF + propriedade animada. **Resultado original esperado:** Não alterar track silenciosamente; solicitar ação explícita. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF04-01 — KF-04 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Editar handle temporal do Graph Editor. **Resultado original esperado:** Curva e valor do inspector refletem easing da trilha. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF04-02 — KF-04 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Mover handle x para fora de [0,1]. **Resultado original esperado:** Rejeitar valor ou limitar visualmente com feedback. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF05-01 — KF-05 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Keys f0=0 f10=1 com easing InOut. **Resultado original esperado:** Valor em f5=0.5; endpoints exatos. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF05-02 — KF-05 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Tipo enum com interpolação cúbica. **Resultado original esperado:** Erro sem render ou coerção. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF06-01 — KF-06 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Alterar key de camera.zoom sem mudar lon. **Resultado original esperado:** Só zoom muda na avaliação do mesmo frame. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF06-02 — KF-06 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Track duplicado para mesmo target/property. **Resultado original esperado:** Cena rejeitada pela validação. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF07-01 — KF-07 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Copiar keys f10/f20 e colar no f40. **Resultado original esperado:** Criar keys f40/f50 com IDs novos. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF07-02 — KF-07 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Colar em frame que excede duração. **Resultado original esperado:** Falha atômica; nenhum key parcial. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF08-01 — KF-08 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Mover 3 keys +7 frames mantendo ordem. **Resultado original esperado:** Todos deslocados em 7, easing preservado. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF08-02 — KF-08 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Retime cria colisão com key existente. **Resultado original esperado:** Rejeitar sem sobrescrever valores. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF09-01 — KF-09 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Arrastar key próximo de marker f40 com Snap ON. **Resultado original esperado:** Key encaixa no f40 dentro da tolerância visual. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF09-02 — KF-09 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Arrastar com Alt/snap temporariamente OFF. **Resultado original esperado:** Nenhum snap automático. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF10-01 — KF-10 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Aplicar preset multi-track e Undo. **Resultado original esperado:** Voltar snapshot anterior integralmente. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-KF10-02 — KF-10 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Nova alteração após Undo, depois Redo. **Resultado original esperado:** Redo invalidado; estado íntegro. **Execução Edit-first:** Executar no Edit Keyframe/Curve Editor para parâmetros OFX; se interno, marcar explicitamente não-nativo e testar engine. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM11-01 — CAM-11 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Quatro poses f0/f72/f156/f239. **Resultado original esperado:** Passar por cada pose exatamente. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM11-02 — CAM-11 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Uma propriedade sem key intermediário. **Resultado original esperado:** Manter interpolação dessa propriedade independente. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM12-01 — CAM-12 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Caminho Bézier geográfico com 2 handles. **Resultado original esperado:** Pontos de início/fim exatos, tangente contínua. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM12-02 — CAM-12 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Handles com latitude >85. **Resultado original esperado:** Rejeitar/normalizar por contrato. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM13-01 — CAM-13 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Fly-to de Caracas a Washington. **Resultado original esperado:** Pico de afastamento sem NaN; último frame exato. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM13-02 — CAM-13 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Duração 1 frame / destino igual origem. **Resultado original esperado:** Sem divisão por zero nem salto. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM14-01 — CAM-14 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Bearing de 350 para 10 shortest. **Resultado original esperado:** Percorrer 20 graus e passar por 0. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM14-02 — CAM-14 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Rotação contínua de 350→730. **Resultado original esperado:** Manter volta completa no modo continuous. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM15-01 — CAM-15 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Zoom com âncora em Caracas e pixel [300,400]. **Resultado original esperado:** Projeção da âncora não desloca mais de 1 px. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM15-02 — CAM-15 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Âncora inválida lat 100. **Resultado original esperado:** Rejeitar sem mover câmera. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM16-01 — CAM-16 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** FitBounds Brasil+Venezuela 16:9. **Resultado original esperado:** Territórios encaixados no padding. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM16-02 — CAM-16 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Bounds vazio ou região inexistente. **Resultado original esperado:** Erro amigável sem alterar pose. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM17-01 — CAM-17 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Bezier com arc-length LUT e uniformScreen. **Resultado original esperado:** Passos de distância semelhantes por fração. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM17-02 — CAM-17 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Trajetória com comprimento zero. **Resultado original esperado:** Resultado constante sem divisão por zero. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM18-01 — CAM-18 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Camera Follow seguindo ícone na rota. **Resultado original esperado:** Centro segue alvo com offset declarado. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-CAM18-02 — CAM-18 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Câmera segue objeto dependente da própria câmera. **Resultado original esperado:** Detectar ciclo e bloquear. **Execução Edit-first:** Executar com câmera OFX, Viewer da Edit e curvas host-owned; conferir antimeridiano e timebase. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO19-01 — GEO-19 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Preencher país #000000 → #FFFFFF em 10 quadros. **Resultado original esperado:** Endpoints exatos, midpoint em sRGB linear-light. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO19-02 — GEO-19 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Hex inválido ou canal NaN. **Resultado original esperado:** Rejeitar antes de render. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO20-01 — GEO-20 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Opacity 0→0.65→0.3 em três keys. **Resultado original esperado:** Valores por key e interpolações corretos. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO20-02 — GEO-20 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Opacity -1 ou 2. **Resultado original esperado:** Clamp/reject por política, sem alpha inválido. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO21-01 — GEO-21 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Stroke reveal sobre MultiPolygon com ilhas. **Resultado original esperado:** Perímetro aparece em distância cumulativa. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO21-02 — GEO-21 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Anel inválido com 2 coordenadas. **Resultado original esperado:** Erro de geometria sem SVG inválido. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO22-01 — GEO-22 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Fill reveal radial com hole central. **Resultado original esperado:** Hole permanece transparente. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO22-02 — GEO-22 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Reveal em polígono vazio. **Resultado original esperado:** Sem vazamento de preenchimento. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO23-01 — GEO-23 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Pulse periodFrames=20 min=.2 max=.8. **Resultado original esperado:** Resultado repetível em f10 e f30. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO23-02 — GEO-23 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Período 0 ou negativo. **Resultado original esperado:** Validação rejeita. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO24-01 — GEO-24 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Stroke width 1→8 entre f0/f20. **Resultado original esperado:** Frame20 exatamente 8px normalizados. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO24-02 — GEO-24 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Espessura negativa. **Resultado original esperado:** Rejeitar sem gerar SVG. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO25-01 — GEO-25 · visual · P0

**Cenário legado:** caminho-feliz. **Setup original:** Glow strength animado em país. **Resultado original esperado:** Preview e export final incluem brilho correto. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO25-02 — GEO-25 · visual · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Glow extremo em 4K. **Resultado original esperado:** Limitar recurso ou exibir erro explícito. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO26-01 — GEO-26 · visual · P0

**Cenário legado:** caminho-feliz. **Setup original:** Pop marker escala 0→1.2→1. **Resultado original esperado:** Âncora permanece fixa. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO26-02 — GEO-26 · visual · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Scale NaN/negativa. **Resultado original esperado:** Rejeitar entrada. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO27-01 — GEO-27 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Aplicar preset Border Trace ao Brasil. **Resultado original esperado:** Tracks criados com IDs estáveis; Undo único. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GEO27-02 — GEO-27 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Aplicar novamente ao mesmo alvo sem confirmar. **Resultado original esperado:** Não duplicar efeitos silenciosamente. **Execução Edit-first:** Executar por região com imagem OFX e parâmetros nativos onde houver binding fixo. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE28-01 — ROUTE-28 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Rota com Caracas→Belém→Brasília. **Resultado original esperado:** Três waypoints e curva válida. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE28-02 — ROUTE-28 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Somente um waypoint. **Resultado original esperado:** Rejeitar rota sem dois pontos. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE29-01 — ROUTE-29 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Arrastar alça de Bézier em waypoint central. **Resultado original esperado:** Atualizar path sem mover outros pontos. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE29-02 — ROUTE-29 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Alça inválida/arrastar fora limites. **Resultado original esperado:** Erro reversível e sem mutação parcial. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE30-01 — ROUTE-30 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Trim start=0.25 end=0.75. **Resultado original esperado:** Mostrar metade intermediária do comprimento. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE30-02 — ROUTE-30 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Trim start=.9 end=.1 sem allowWrap. **Resultado original esperado:** Rejeitar sem render. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE31-01 — ROUTE-31 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** MovingObject progress 0/.5/1. **Resultado original esperado:** Objeto nos extremos e midpoint por arco. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE31-02 — ROUTE-31 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Rota degenerada ou sem geometria. **Resultado original esperado:** Erro claro, sem NaN. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE32-01 — ROUTE-32 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** OrientAlongPath numa curva direita. **Resultado original esperado:** Heading coincide com tangente local + offset. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE32-02 — ROUTE-32 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Tangente nula em trecho plano. **Resultado original esperado:** Fallback estável ao último ângulo válido. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE33-01 — ROUTE-33 · visual · P0

**Cenário legado:** caminho-feliz. **Setup original:** Trailing Line length=.2, progress=.6. **Resultado original esperado:** Renderizar segmento de .4 a .6. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE33-02 — ROUTE-33 · visual · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Comprimento negativo. **Resultado original esperado:** Rejeitar antes de rasterizar. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE34-01 — ROUTE-34 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Dashed offset 0→20 em 24 frames. **Resultado original esperado:** Dash se desloca, path fixo. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE34-02 — ROUTE-34 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** DashOffset não-finito. **Resultado original esperado:** Erro de input. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE35-01 — ROUTE-35 · geo · P0

**Cenário legado:** caminho-feliz. **Setup original:** Morph entre paths amostrados com 64 pontos. **Resultado original esperado:** Geometria finita, endpoints preservados. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE35-02 — ROUTE-35 · geo · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Paths vazios/com diferentes direções sem regra. **Resultado original esperado:** Rejeição ou fallback documentado. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE36-01 — ROUTE-36 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Dois segmentos duração 20/40 frames. **Resultado original esperado:** Progresso em cada trecho obedece tempo próprio. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-ROUTE36-02 — ROUTE-36 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Segmentos excedem duração da animação. **Resultado original esperado:** Erro com índice do segmento. **Execução Edit-first:** Executar em Geometry Core + efeito Edit; Viewer Interact obrigatório onde gestos forem exigidos. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG37-01 — MG-37 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Aplicar Fly In 48 frames ao país. **Resultado original esperado:** Gera keyframes editáveis e mesma pose final. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG37-02 — MG-37 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Preset com target removido. **Resultado original esperado:** Falha atômica; nenhuma trilha órfã. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG38-01 — MG-38 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Parent marker B em A com offset fixo. **Resultado original esperado:** B acompanha A na ordem topológica. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG38-02 — MG-38 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Ciclo A→B→C→A. **Resultado original esperado:** Validação rejeita. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG39-01 — MG-39 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** Stagger 4 países por 3 frames. **Resultado original esperado:** Offsets 0/3/6/9 preservam ordem. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG39-02 — MG-39 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Stagger estoura duração. **Resultado original esperado:** Rejeitar transação sem keys parciais. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG40-01 — MG-40 · ui · P0

**Cenário legado:** caminho-feliz. **Setup original:** Criar marker f100 com rótulo Narração. **Resultado original esperado:** Aparece na régua e snap funciona. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG40-02 — MG-40 · ui · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Marker no frame -1 ou >=frames. **Resultado original esperado:** Rejeitar antes de salvar. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG41-01 — MG-41 · unit · P0

**Cenário legado:** caminho-feliz. **Setup original:** PingPong em [10,20]. **Resultado original esperado:** Sequência reverte sem frame duplicado no endpoint. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG41-02 — MG-41 · unit · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Loop de range com start=end. **Resultado original esperado:** Resultado constante; sem modulo zero. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG42-01 — MG-42 · security · P0

**Cenário legado:** caminho-feliz. **Setup original:** Expression clamp(sin(time)*.5+.5,0,1). **Resultado original esperado:** Valor finito no frame sem IO. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MG42-02 — MG-42 · security · P0

**Cenário legado:** erro-ou-borda. **Setup original:** Expression process.exit/Function/fetch. **Resultado original esperado:** Parser nega execução arbitrária. **Execução Edit-first:** Executar scene graph/constraints + Curve Edit para parâmetros expostos; salvar/reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-001 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar fixture v1 Brasil-Venezuela sem alterar input. **Resultado original esperado:** Cena v2 válida, mesmo conteúdo cartográfico. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-002 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Comparar câmera nos 120 frames do exemplo v1. **Resultado original esperado:** Erro <=1e-10 em lon/lat/zoom. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-003 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Comparar progresso das rotas em todos os frames. **Resultado original esperado:** Mesmo valor por frame dentro de 1e-10. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-004 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar uma cena de frames=1. **Resultado original esperado:** Sem key duplicado ou divisão por zero. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-005 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar rota start=end. **Resultado original esperado:** Criar degrau visível no frame inicial. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-006 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar território fade start=end. **Resultado original esperado:** Opacidade inteira aparece no frame correto. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-007 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar longitude 179→-179. **Resultado original esperado:** Continuidade do menor arco igual ao algoritmo legado. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-008 — MIG · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar JSON malformado. **Resultado original esperado:** Erro com path, documento original intacto. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-009 — MIG · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Salvar cena migrada como arquivo novo. **Resultado original esperado:** Novo arquivo v2, v1 original preservado. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-MIG-010 — MIG · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Abrir v2 sem migração. **Resultado original esperado:** Não reescreve keyframes nem IDs. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-001 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Export de 1 frame e 4 camadas. **Resultado original esperado:** Gerar quatro PNG válidos e manifest COMPLETE. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-002 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Cancelar export após lote 24. **Resultado original esperado:** Status CANCELLED, não COMPLETE; PNGs existentes preservados. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-003 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Retomar job com hash idêntico. **Resultado original esperado:** Não re-renderizar lotes completos. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-004 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Retomar job com hash diferente. **Resultado original esperado:** Bloquear resume e avisar incompatibilidade. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-005 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Export >9999 frames. **Resultado original esperado:** Usar 6 dígitos sem colisão de nomes. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-006 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Export v1 de 4 dígitos. **Resultado original esperado:** Importador antigo lê e valida PNGs. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-007 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Export v2 de 6 dígitos. **Resultado original esperado:** Importador novo lê e valida PNGs. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-008 — IPC · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Frame PNG incompleto com extensão .part. **Resultado original esperado:** Não considerar frame completo. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-009 — IPC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Path traversal /.. em export/import. **Resultado original esperado:** Rejeitar acesso fora da pasta. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-IPC-010 — IPC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Symlink malicioso nos diretórios de export. **Resultado original esperado:** Não seguir para fora da raiz sem verificação. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-001 — NATIVE · lua · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Lua gera composição raster de 4 layers. **Resultado original esperado:** Quatro Loader, três Merge, MediaOut conectado. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-002 — NATIVE · lua · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Falha depois de criar Fusion clip. **Resultado original esperado:** Status PARTIAL e Unlock garantido. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-003 — NATIVE · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** User apaga clip e reinsere mesma export. **Resultado original esperado:** Nova tentativa com confirmação, sem re-render. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-004 — NATIVE · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Native capability ausente. **Resultado original esperado:** Fallback PNG explícito e correto. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-005 — NATIVE · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Native support apenas opacity. **Resultado original esperado:** Apenas propriedade suportada vira spline nativa; outras raster. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-006 — NATIVE · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Testar versão Resolve 20 Studio Windows. **Resultado original esperado:** Não declarar aprovado sem executar no Resolve real. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-007 — NATIVE · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Testar versão Resolve 21 Studio Windows. **Resultado original esperado:** Não declarar aprovado sem executar no Resolve real. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-FUS-008 — NATIVE · integration · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Dupla confirmação simultânea. **Resultado original esperado:** Máximo uma tentativa ativa, nenhum clip duplicado involuntário. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GOLD-001 — GOLD · visual · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Preview SVG v1 em f0/f60/f119. **Resultado original esperado:** Snapshot equivalente após migração. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GOLD-002 — GOLD · visual · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** PNG HD gerado via novo avaliador. **Resultado original esperado:** Imagem equivalente ao legado nas cenas sem features novas. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GOLD-003 — GOLD · visual · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Bearing 0°,45°,90° em PNG. **Resultado original esperado:** Transform geométrico correto e labels opcionais legíveis. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GOLD-004 — GOLD · visual · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Polygon com buraco e fill reveal. **Resultado original esperado:** Buraco não preenchido. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-GOLD-005 — GOLD · visual · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Antimeridiano com rota/território. **Resultado original esperado:** Nenhum traço atravessa tela inteira. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-PERF-001 — PERF · performance · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** 500 tracks com 5000 keys, 1000 frames de avaliação. **Resultado original esperado:** Registrar p50/p95 e hardware, sem regressões graves. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-PERF-002 — PERF · performance · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** 36k frames export batch-size 24. **Resultado original esperado:** RAM mantém limite configurado e arquivos válidos. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-PERF-003 — PERF · performance · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** 100 trilhas expandidas no UI. **Resultado original esperado:** Scrubbing sem travar interação e foco acessível. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-SEC-001 — SEC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** AST expression com eval/Function/fetch. **Resultado original esperado:** Rejeitar sem efeitos colaterais. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-SEC-002 — SEC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Constraint com referência inexistente. **Resultado original esperado:** Erro antes de render. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-SEC-003 — SEC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** AST 1025 nós ou 17 níveis. **Resultado original esperado:** Rejeitar pelo budget de complexidade. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-SEC-004 — SEC · security · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Track target __proto__ ou constructor. **Resultado original esperado:** Rejeitar ao validar propriedade. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-SEC-005 — SEC · unit · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** NaN e Infinity em keyframe. **Resultado original esperado:** Rejeitar sem serializar. **Execução Edit-first:** Verificar pertinência do cenário e adaptar o mecanismo para OFX/Edit; preservar regra matemática. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-E2E-001 — E2E · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Migrar cena antiga, editar zoom, salvar/reabrir. **Resultado original esperado:** Preservar keys, sem mudança no arquivo original. **Execução Edit-first:** Reescrever fluxo como plugin nativo na página Edit (sem PNG sequencial ou Fusion manual); golden Deliver e reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-E2E-002 — E2E · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Tour Brasil/Venezuela/Caribe/Washington. **Resultado original esperado:** Quatro poses e zoom individual exibidos corretamente. **Execução Edit-first:** Reescrever fluxo como plugin nativo na página Edit (sem PNG sequencial ou Fusion manual); golden Deliver e reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-E2E-003 — E2E · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Dois routes + object along path e territory fade. **Resultado original esperado:** Preview 120 frames corresponde ao Fusion raster. **Execução Edit-first:** Reescrever fluxo como plugin nativo na página Edit (sem PNG sequencial ou Fusion manual); golden Deliver e reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

### T-E2E-004 — E2E · e2e · P0

**Cenário legado:** regressao-ou-integracao. **Setup original:** Export cancel/restart sem re-render. **Resultado original esperado:** Manifest correto, timeline importa sequência válida. **Execução Edit-first:** Reescrever fluxo como plugin nativo na página Edit (sem PNG sequencial ou Fusion manual); golden Deliver e reabrir. **Evidência:** teste automatizado matemático quando possível e captura/report do Resolve 20 real para UI, persistência, alfa ou integração.

## 22. Critérios de decisão final, riscos não negociáveis e aceite do produto

### 22.1 O que pode ser prometido com segurança após o laboratório

- Mapas e camadas geográficas **renderizados dentro do Resolve** sem pipeline de PNG obrigatório; confirmação depende da carga/registro e performance do OFX Generator ou Macro.
- Parâmetros expostos no Inspector e animados pelo Curve Editor 20, pois a capacidade existe no host; **somente para os parâmetros que efetivamente aparecem**.
- Dados, animações avançadas, geodesia, rótulos e visualização de dados por algoritmo próprio; não há impeditivo matemático, mas há esforço/performance/UX/licenciamento a certificar.
- Uso cotidiano Edit-first se prova de fonte, scene, keyframes, Viewer/Inspector e Deliver for satisfatória.

### 22.2 O que **não** pode ser prometido antes de novos dados

- Painel próprio dockável na Edit (sem API pública identificada).
- Seleção interativa GIS ilimitada no Viewer (OFX overlays dependem de host/versão/eventos).
- Keyframes nativos ilimitados para cada propriedade de qualquer número de objetos dinâmicos numa única instância OFX (restrição formal de parâmetros definidos em `Describe`).
- Scene graph inteiro embutido em `.drp` independentemente de tamanho; strings/sidecar precisam de testes.
- GPU AMD/CUDA/metal automaticamente acelerando OFX no Resolve 20.
- Equivalência total de recursos 3D em Edit sem expor o grafo Fusion.
- Plugin `OFX Generator` idêntico ao `Fusion Generator` em todas as versões; a base Resolve20 exige teste específico.

### 22.3 Riscos P0 e mitigação

| Risco | Consequência | Mitigação formal |
|---|---|---|
| OFX Generator indisponível no fluxo exato do Resolve20 | Produto não aparece como clip sem mídia | Fusion Generator Macro com OFX/Fuse interno (`C`) |
| Viewer overlay não capta todos os eventos | Path/territory visual editing parcial | Desenho paramétrico + reconsiderar UI nativa auxiliar/escopo |
| Param definitions não dinâmicas | Curvas por objetos ilimitados não nativas | Slots limitados + scene track interno + honestidade funcional |
| Dados não persistem com clipe | Perda de trabalho | Params persistentes + scene snapshot/sidecar/relink e backup |
| OFX host time muda sob trim/retime | Keyframes e trajetórias deslocados | Modelo hostTime/localTime e regressões |
| GPU/render threads instáveis | Freeze/crash no Resolve | CPU fallback, render puro, testes de stress e ABI |
| Composição/cor/alfa errados | Mapa inconsistente entre Viewer/Deliver | Validação de cores, alpha, pixel aspect e ROIs |
| Dataset/tiles sem direitos de produção | Uso editorial/comercial irregular | Provedor licenciado com cache/attribution; default offline livre |
| 3D complexo sem interface editável | Não equivale a compositor 3D completo | Delimitar Edit rendering vs Fusion 3D editability |

### 22.4 Veredito para autorização de código

**Aprovação condicional:** desenvolvimento de um **laboratório de compatibilidade Edit-first Resolve Studio 20.x** e não de um renderizador completo. Se `EF-POC-02/03/06/08/10/11/19/42` passarem, a abordagem OpenFX primary é a recomendação principal. Se falharem Generator ou overlay, manter **Edit-first** com Macro/Fusion Generator onde possível e registrar exatamente quais critérios da UX permanecem não cumpridos. Se o requisito absoluto for **todos** os 465 comportamentos replicados literalmente, incluindo workspace HTML/dockable ilimitado e Curve Editor com canais infinitos por objeto, o projeto será **inviável sob as APIs públicas identificadas** sem renegociar essa expectativa. A alternativa é preservar **todo o conjunto de capacidades geográficas e narrativas** com superfícies nativas equivalentes, limites explícitos e prioridades verificadas.

**Não realizar implementação do CartoRig nesta fase:** estudo concluído em desenho; testes executáveis, instalação e alterações de repositório somente mediante etapa de implementação separadamente autorizada.


## 23. Quadro de viabilidade comparativa das 42 features — execução vs interface Edit 20

**Legenda de avaliação (não é status de implementação):** `D` = há caminho direto documentado para os controles publicados (ainda precisa de POC do produto); `A` = algoritmo viável, mas capacidade de edição/quantidade de objetos depende de adaptação; `H` = componente essencial depende de teste de eventos/UI ou SDK do host; `L` = limitação estrutural conhecida do OpenFX para curvas por objeto dinâmico. A coluna `Resultado visual` considera a engenharia do efeito, não certifica performance em 4K.

| Feature | Render/função visual | Edição na Edit 20 | Risco dominante |
|---|---|---|---|
| `KF-01` | D | D | Curvas apenas de parâmetros publicados |
| `KF-02` | D | A/L | Lista de tracks não corresponde a objetos internos ilimitados |
| `KF-03` | D | H | Auto Key via overlay e host Undo |
| `KF-04` | D | D/L | Curve Editor 20 não lista curvas internas |
| `KF-05` | D | A | Paridade exata de curvas cúbicas legadas |
| `KF-06` | D | D/L | Controles nativos fixos |
| `KF-07` | D | D/L | Pasta de curves internas diferente do host |
| `KF-08` | D | D/L | Retime de múltiplas instâncias |
| `KF-09` | D | D/A | Marcadores do host e eventos internos |
| `KF-10` | D | H | Undo atômico de arquivo/overlay |
| `CAM-11` | D | D | Longitude com unwrap |
| `CAM-12` | D | H | Handles espaciais no Viewer |
| `CAM-13` | D | A | Gerar múltiplos canais de câmera |
| `CAM-14` | D | D | Texto upright/georreferência |
| `CAM-15` | D | H | Mouse anchored transform |
| `CAM-16` | D | H | Aplicar resultado fit bounds a params/keys |
| `CAM-17` | D | A | Timming de distância vs curva host |
| `CAM-18` | D | A/H | Escolha dinâmica de alvo e ciclos |
| `GEO-19` | D | A/L | Curva individual de cor por objeto |
| `GEO-20` | D | A/L | Curva individual de opacidade por objeto |
| `GEO-21` | D | A/L | Controles por perímetro/objeto |
| `GEO-22` | D | A/L | Máscara de região associada a control nativo |
| `GEO-23` | D | A/L | Fase/amplitude por país |
| `GEO-24` | D | A/L | Espessura de fronteira por região |
| `GEO-25` | D | A/L | Glow de cada região em 4K |
| `GEO-26` | D | A/L | Pivot/pop por região |
| `GEO-27` | D | A/H | Aplicar preset multi-key com undo |
| `ROUTE-28` | D | H | Criar/editar waypoints na tela |
| `ROUTE-29` | D | H | Overlay handles e pen capture |
| `ROUTE-30` | D | A/L | 2 curvas por rota dinâmica |
| `ROUTE-31` | D | A/L | Progresso de mover por rota |
| `ROUTE-32` | D | A/L | Ângulo dependente da curva |
| `ROUTE-33` | D | A/L | Trail por rota e host reverse |
| `ROUTE-34` | D | A/L | Dash phase individual |
| `ROUTE-35` | D | A/L | Morph entre dois paths internamente |
| `ROUTE-36` | D | A/L | Curvas de velocidade distintas por trecho |
| `MG-37` | D | A/H | Aplicar pacote de keyframes/presets |
| `MG-38` | D | A/H | Parent select e dependency graph |
| `MG-39` | D | A/L | N tracks de stagger individual |
| `MG-40` | D | D/A | Eventos e marcadores da timeline |
| `MG-41` | D | A | Tempo não monotônico/reverse/loop |
| `MG-42` | D | A/H | Sandbox AST e inputs de expressões |

**Interpretação:** 42/42 têm mecanismo plausível para produzir o resultado visual, mas **não** são 42/42 comprovadas como edições por curva nativa de todo objeto. A limitação L é mais severa quando se exige um número arbitrário de canais por objeto dentro da mesma instância. Se essa exigência for indispensável, definir limite de slots ou escolher UI que aceite controles próprios, explicitando que isso deixa de ser o Curve Editor puro da Edit.

## 24. Provas adicionais sobre OpenFX Generator e automação do Resolve 20

O histórico dos manuais Resolve já documentava **geradores e transições OpenFX na Edit**; fabricantes de plugins também descrevem seus geradores OpenFX utilizáveis na Edit 20. Uma cópia pública da Scripting API 20.2 registra `Timeline.InsertOFXGeneratorIntoTimeline(generatorName)`; isso fortalece a expectativa de que geradores OFX sejam um caminho do host 20. **Mesmo assim**, documentação de API e funcionalidade de plugins comerciais **não certificam** a ABI, a instalação nem os overlays do CartoRig que ainda será construído.

Referências complementares:

- Cópia da documentação de Scripting API Resolve 20.2 (não fonte oficial hospedada pela Blackmagic): https://gist.github.com/Moyf/7d7ade9eafb75a197141bfcc4cd650f0 . Confrontar com a versão local `Help > Documentation > Developer`.
- Exemplo de fornecedor de plugins OpenFX, registrando filtros, geradores e transições no Resolve 20: https://fxfactory.com/help/davinciresolve/ . É evidência operacional secundária, não garantia do SDK.
- Manual Blackmagic de geração anterior documenta geradores OpenFX na Edit: https://documents.blackmagicdesign.com/UserManuals/DaVinci_Resolve_11_Reference_Manual.pdf?_v=1427701531000 . Útil apenas como prova histórica, não para decidir comportamento exato do 20.3.2.

**Regra para automação:** a API de scripting que insere um OFX generator não é prova de que ela permita editar qualquer parâmetro OpenFX, animar todas as propriedades ou anexar UI à página Edit. Evitar projetar automação destrutiva em cima de métodos inferidos, sobretudo inserção em tracks específicas e movimentação de clipes. Cada chamada precisa ser registrada no arquivo de capabilities e testada no Resolve 20.

## 25. Ordem de validação final e condição de não autoengano

Antes de começar um novo repositório, executar **os 8 gates do caminho crítico** com uma fixture mínima: (1) bundle OFX aceito pelo Resolve 20; (2) gerador colocável na Edit; (3) render alfa sobre clipe real; (4) parâmetros no Inspector e Curve Editor 20; (5) overlay mouse no Viewer Edit; (6) save/reopen + `.drp`; (7) clip duplicate/trim/retime; (8) 4K render sem crash. Se 1–4 e 6 passarem, há produto **Edit-first paramétrico**. Se 5 passar, há base para a experiência **GIS interativa**. Se a exigência central for **curvas OFX nativas por qualquer número de objetos geográficos**, a restrição formal de `paramDefine` permanece; o gate 17 de slots/múltiplas instâncias definirá limites mensuráveis, não sua eliminação.

**Parecer final:** estudar e prototipar o caminho **C++ OpenFX Generator primário + OFX Filter Overlay + Fusion Generator Macro de contingência** é a decisão mais defensável para um CartoRig cujo ambiente de trabalho principal seja a página Edit do **Resolve Studio 20**. É uma mudança real de arquitetura em relação ao plano Fusion-first, porém preserva os requisitos geográficos, de animação, de qualidade e de segurança sem criar uma falsa promessa de painel nativo dockável ou curvas ilimitadas geradas dinamicamente.