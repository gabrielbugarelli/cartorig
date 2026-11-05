# CartoRig — Catálogo integral de requisitos funcionais e funcionalidades

**Inventário mestre de produto · Edição 2026-11-05 · base de auditoria: código CartoRig v0.3.3 (branch de estabilização com as sete revisões) e histórico completo do MVP.**

> **Escopo da palavra “todos”.** Este inventário consolida os comportamentos identificáveis no código, README, CHANGELOG, testes automatizados, especificação aprovada das 42 features e decisões registradas na conversa. Não é uma garantia de existência de funcionalidades não documentadas ou não observáveis no repositório. As funções futuras não são tratadas como entregues.

## Estado do repositório consultado

- Repositório privado: [`gabrielbugarelli/cartorig`](https://github.com/gabrielbugarelli/cartorig).
- `main` no momento da consulta: `aa38d5d8e04bcf63b92f1b9ef910eddb0361c747` — **v0.3.2**, após rebase.
- Branch de estabilização: `feature/stabilization-v0.3.3`, SHA `140a5c2db99b243254c7d467d997878c72025214` — **v0.3.3 candidata**, com PR #3 integrado à branch e PR #2 ainda aberto para `main`.
- Último lote funcional aprovado: correções de playhead, speed ramp Bézier, navegação, alinhamento e pan vertical, incorporadas na branch de estabilização.
- **Estado “implementado”** abaixo significa que o comportamento está presente no código analisado; não significa que a execução nativa esteja certificada em todas as instalações do DaVinci Resolve.

## Legenda de estado

| Código | Significado |
|---|---|
| **I — Implementado** | Código e/ou testes atuais apresentam a funcionalidade. Pode depender do host para execução real. |
| **P — Parcial** | Parte existe, mas o critério de aceite final não foi cumprido. |
| **N — Não implementado** | Aprovado para evolução futura, mas ainda não existe no produto. |
| **FUT — Ideia** | Possibilidade histórica discutida; não confundir com feature aprovada ou entregue. |

**Identificadores:** `CR-RF-0001` em diante catalogam capacidades e requisitos atuais/pendentes gerais; as 42 features avançadas conservam IDs originais `KF`, `CAM`, `GEO`, `ROUTE` e `MG`. IDs distintos podem se relacionar quando uma feature atravessa módulos (por exemplo, Graph Editor e Undo).

## Linha do tempo funcional

| Marco | Capacidade adicionada ou consolidada |
|---|---|
| **MVP v0.1 — dia zero** | Editor offline, países, estilos, marcadores, rota animada, câmera inicial/final, cena JSON, preview SVG/PNG, exportação por camadas e primeira integração Fusion. |
| **v0.2.x** | Continentes, subdivisões/cidades opcionais, GeoJSON, ampliação da cobertura e testes; migração do processo Fusion para Lua; robustez de instalação/identidade. |
| **v0.2.7** | Identidade CartoRig auditada, cache e prefixos internos, README e scripts atualizados. |
| **v0.2.8** | Gerenciador de exportações com busca, metadados, preview e validação de cada PNG. |
| **v0.2.9** | Reimportação confirmada de sequências via tentativas isoladas, evitando bloqueio permanente e duplo clique concorrente. |
| **v0.3.0** | Modelo v2, migração legada, motor de keyframes múltiplos, interpolações e Undo/Redo. |
| **v0.3.1** | Timeline unificada e câmera visual com Auto Key, poses atômicas e easing gráfico. |
| **v0.3.2** | Workspaces Padrão/Foco, árvore de objetos, Inspector, preview flutuante, Dope Sheet/Graph e timecode. |
| **v0.3.3 candidata** | CI/QA de navegador; playhead arrastável, curva Bézier manipulável, correção do pan vertical e remoção dos controles redundantes. |
| **v0.4.0–v0.6.0 planejadas** | Graph Editor profissional e câmera avançada; movimento geográfico avançado; exportação nativa para Fusion onde suportada. |

---

## Parte A — Requisitos funcionais detalhados (base de produto)

### 01. Produto, projeto e ciclo de vida da cena

**Origem:** MVP v0.1 → v0.3.x. **Fontes principais:** `plugin/js/app.js; plugin/main.js; plugin/animation/index.js`.

- [x] **CR-RF-0001** — Criar um projeto cartográfico editável a partir de uma cena de exemplo offline.
- [x] **CR-RF-0002** — Criar e manter título/nome da cena.
- [x] **CR-RF-0003** — Permitir reutilizar cena de exemplo Brasil–Venezuela como ponto de partida.
- [x] **CR-RF-0004** — Configurar FPS em 24, 25 ou 30 quadros por segundo.
- [x] **CR-RF-0005** — Configurar duração em número inteiro de quadros, de 1 a 480 no motor atual.
- [x] **CR-RF-0006** — Exibir duração equivalente em segundos e/ou timecode.
- [x] **CR-RF-0007** — Navegar pelo projeto de quadro 0 até `frames - 1`.
- [x] **CR-RF-0008** — Manter título, FPS, duração, aparência, regiões, marcadores, rotas, câmera e animações no modelo de cena.
- [x] **CR-RF-0009** — Salvar cena editável em arquivo JSON da extensão `.cartorig.json`.
- [x] **CR-RF-0010** — Abrir cenas salvas por caixa de diálogo do host.
- [x] **CR-RF-0011** — Rejeitar versão de cena inválida ou estrutura sem os campos obrigatórios.
- [x] **CR-RF-0012** — Carregar cenas legadas `version: 1` e migrá-las em memória para `version: 2`.
- [x] **CR-RF-0013** — Salvar o modelo de cena v2 validado sem perder trilhas de animação.
- [x] **CR-RF-0014** — Não modificar o arquivo legado de origem durante a simples abertura/migração.
- [x] **CR-RF-0015** — Manter serialização determinística do modelo v2.
- [x] **CR-RF-0016** — Preservar ID e referencial de objetos entre trilhas, marcadores e rotas.
- [x] **CR-RF-0017** — Validar referências de rotas a IDs de marcadores existentes.
- [x] **CR-RF-0018** — Validar campos de FPS, frames, câmera, cores e opacidade antes de salvar/exportar.
- [x] **CR-RF-0019** — Limitar o arquivo JSON de cena aceito pelo host a até 2 MB.
- [x] **CR-RF-0020** — Respeitar os limites atuais de 100 países no campo legado, 180 territórios, 300 marcadores e 300 rotas.
- [x] **CR-RF-0021** — Rejeitar IDs duplicados de marcadores.
- [x] **CR-RF-0022** — Permitir renomear e personalizar a cena sem regenerar os dados-base.
- [x] **CR-RF-0023** — Atualizar as referências de preview e ferramentas após abrir outra cena.
- [x] **CR-RF-0024** — Encurtar a duração preservando, no novo último quadro, o valor avaliado da câmera e das rotas.
- [x] **CR-RF-0025** — Impedir que o encurtamento deixe keyframes fora do intervalo final de quadros.
- [x] **CR-RF-0026** — Rejeitar operações com valores numéricos não finitos (`NaN`/`Infinity`).
- [x] **CR-RF-0027** — Manter o projeto independente dos PNGs renderizados: JSON é fonte editável, PNG é saída.

### 02. Instalação, inicialização e integração do host

**Origem:** MVP v0.1 → v0.2.7. **Fontes principais:** `Install.cmd; Install.ps1; Uninstall.cmd; Uninstall.ps1; plugin/manifest.xml; plugin/main.js; plugin/preload.js`.

- [x] **CR-RF-0028** — Distribuir a interface como Workflow Integration para DaVinci Resolve Studio Windows.
- [x] **CR-RF-0029** — Instalar com `Install.cmd`/`Install.ps1` por PowerShell, fechando o Resolve antes.
- [x] **CR-RF-0030** — Copiar os arquivos do plugin para o caminho de integração do Resolve sob `com.cartorig.maps`.
- [x] **CR-RF-0031** — Procurar `WorkflowIntegration.node` em caminhos conhecidos do SDK/instalação.
- [x] **CR-RF-0032** — Solicitar caminho do módulo nativo quando a detecção automática falhar.
- [x] **CR-RF-0033** — Usar o `WorkflowIntegration.node` fornecido pela instalação do usuário, sem redistribuí-lo.
- [x] **CR-RF-0034** — Registrar a integração de workflow com identidade e manifesto CartoRig.
- [x] **CR-RF-0035** — Instalar o script Lua de fallback no menu `Workspace → Scripts → Utility` do Resolve.
- [x] **CR-RF-0036** — Disponibilizar opção de instalação manual para diagnóstico.
- [x] **CR-RF-0037** — Desinstalar apenas os componentes instalados pela identidade CartoRig.
- [x] **CR-RF-0038** — Exigir confirmação explícita `REMOVER` na desinstalação.
- [x] **CR-RF-0039** — Preservar arquivos de cena e sequências exportadas fora da pasta do plugin ao desinstalar.
- [x] **CR-RF-0040** — Inicializar interface local em Electron/Chromium com dados cartográficos básicos offline.
- [x] **CR-RF-0041** — Exibir e atualizar status de conexão com o Resolve e identificação da timeline, quando disponível.
- [x] **CR-RF-0042** — Não exigir Node.js/npm como pré-requisito para uso normal no Resolve.
- [x] **CR-RF-0043** — Oferecer preview independente em navegador para recursos que não precisam da ponte IPC.
- [x] **CR-RF-0044** — Desativar recursos dependentes de host quando a ponte Electron/Resolve não estiver presente.
- [x] **CR-RF-0045** — Aplicar isolamento de contexto e expor API limitada via `contextBridge`/preload.
- [x] **CR-RF-0046** — Manter Node integration desabilitada na página de interface.
- [x] **CR-RF-0047** — Impedir navegação arbitrária da janela e manter CSP de recursos locais.
- [x] **CR-RF-0048** — Solicitar downloads geográficos apenas sob ação explícita do usuário.
- [x] **CR-RF-0049** — Preservar preferência manual de `External scripting: Local`, sem ativá-la automaticamente.
- [x] **CR-RF-0050** — Não exigir conta, login ou autenticação de provedor de mapas para os recursos offline.
- [x] **CR-RF-0051** — Não enviar telemetria nem dados do usuário automaticamente.
- [ ] **CR-RF-0052** — **[Parcial]** Certificar a compatibilidade real com Resolve Studio 20.x/21.x em matriz de instalações Windows (os testes Lua atuais são simulados).

### 03. Catálogos, pesquisa geográfica e GeoJSON

**Origem:** MVP v0.1 → v0.2.x. **Fontes principais:** `plugin/js/countries.js; plugin/js/regions.js; plugin/geo-data.js; plugin/js/app.js; plugin/assets/countries.geojson`.

- [x] **CR-RF-0053** — Carregar catálogo offline básico com aproximadamente 173 feições geográficas simplificadas.
- [x] **CR-RF-0054** — Localizar países pelo nome via pesquisa textual.
- [x] **CR-RF-0055** — Normalizar acentos e caixa na busca de nomes.
- [x] **CR-RF-0056** — Adicionar países encontrados à seleção cartográfica.
- [x] **CR-RF-0057** — Identificar países por código ISO-3 do conjunto de dados.
- [x] **CR-RF-0058** — Disponibilizar seleção por continente, país, estado/província e cidade como categorias de UI.
- [x] **CR-RF-0059** — Agrupar países por continente a partir do catálogo local.
- [x] **CR-RF-0060** — Adicionar um continente como conjunto de países, e não como polígono continental único.
- [x] **CR-RF-0061** — Pesquisar e adicionar múltiplos países à composição.
- [x] **CR-RF-0062** — Impedir entrada de códigos de países inexistentes.
- [x] **CR-RF-0063** — Pesquisar capitais/cidades básicas do catálogo offline como pontos.
- [x] **CR-RF-0064** — Preencher coordenadas de marcador a partir de uma cidade selecionada.
- [x] **CR-RF-0065** — Mostrar a indisponibilidade de estados/províncias não carregados.
- [x] **CR-RF-0066** — Oferecer download opcional de estados/províncias Natural Earth.
- [x] **CR-RF-0067** — Oferecer download opcional de cidades Natural Earth.
- [x] **CR-RF-0068** — Buscar dados extras somente por endereços HTTPS previamente autorizados.
- [x] **CR-RF-0069** — Armazenar dados extras sob cache local CartoRig/geodata.
- [x] **CR-RF-0070** — Carregar novamente dados opcionais do cache sem novo download.
- [x] **CR-RF-0071** — Importar arquivo local `GeoJSON FeatureCollection` compatível.
- [x] **CR-RF-0072** — Aceitar geometrias `Polygon` válidas para fronteiras.
- [x] **CR-RF-0073** — Aceitar geometrias `MultiPolygon` válidas para fronteiras.
- [x] **CR-RF-0074** — Aceitar feições `Point` para cidades.
- [x] **CR-RF-0075** — Validar coordenadas WGS84 (longitude/latitude em graus) e anéis de polígonos.
- [x] **CR-RF-0076** — Garantir ou reconstruir fechamento válido de anéis poligonais quando necessário.
- [x] **CR-RF-0077** — Descartar pontos inválidos de anéis recuperáveis e rejeitar geometrias insanáveis.
- [x] **CR-RF-0078** — Rejeitar estrutura que não seja `FeatureCollection`.
- [x] **CR-RF-0079** — Limitar complexidade e tamanho dos dados GeoJSON importados.
- [x] **CR-RF-0080** — Disponibilizar carregamento de geometrias por ID via IPC do host.
- [x] **CR-RF-0081** — Rejeitar consulta a categorias de dados geográficos não autorizadas.
- [x] **CR-RF-0082** — Rejeitar identificadores geográficos com formato/comprimento inválido.
- [x] **CR-RF-0083** — Persistir geometria de regiões selecionadas no projeto para manter portabilidade.
- [x] **CR-RF-0084** — Permitir usar dados de países sem rede ou API comercial de mapas.
- [ ] **CR-RF-0085** — **[Não implementado]** Cobrir globalmente limites administrativos municipais como polígonos (cidades atuais são pontos).
- [ ] **CR-RF-0086** — **[Não implementado]** Suportar SHP, GeoPackage e outros formatos geográficos sem conversão externa para GeoJSON WGS84.
- [ ] **CR-RF-0087** — **[Não implementado]** Consultar e mostrar dados de geocodificação de endereços em serviço externo.

### 04. Territórios, seleção, aparência e composição visual

**Origem:** MVP v0.1 → v0.2.x. **Fontes principais:** `plugin/js/app.js; plugin/js/regions.js; plugin/animation/index.js`.

- [x] **CR-RF-0088** — Criar território destacado ao selecionar país/região compatível.
- [x] **CR-RF-0089** — Selecionar diversos territórios simultaneamente na mesma cena.
- [x] **CR-RF-0090** — Remover território destacado da composição.
- [x] **CR-RF-0091** — Mostrar nome, tipo e identificação do território selecionado.
- [x] **CR-RF-0092** — Editar cor de preenchimento individual do território.
- [x] **CR-RF-0093** — Editar cor da borda individual do território.
- [x] **CR-RF-0094** — Editar opacidade final do território no intervalo 0–1.
- [x] **CR-RF-0095** — Definir quadro inicial do aparecimento do destaque.
- [x] **CR-RF-0096** — Definir quadro final da transição de aparecimento (fade).
- [x] **CR-RF-0097** — Permitir aparecimento instantâneo quando início e fim coincidem.
- [x] **CR-RF-0098** — Calcular opacidade intermediária conforme o tempo da cena.
- [x] **CR-RF-0099** — Ocultar o destaque antes do quadro inicial.
- [x] **CR-RF-0100** — Manter a opacidade configurada depois da transição.
- [x] **CR-RF-0101** — Editar o estilo global do oceano.
- [x] **CR-RF-0102** — Editar o estilo global da massa terrestre.
- [x] **CR-RF-0103** — Editar estilo padrão de novos territórios destacados.
- [x] **CR-RF-0104** — Editar estilo global das fronteiras.
- [x] **CR-RF-0105** — Editar cor padrão de rotas e pontos.
- [x] **CR-RF-0106** — Manter estilos individuais independentes dos padrões globais após serem atribuídos.
- [x] **CR-RF-0107** — Desenhar linhas de grade geográfica no mapa base.
- [x] **CR-RF-0108** — Controlar ordem de renderização, priorizando regiões continentais/países/subdivisões.
- [x] **CR-RF-0109** — Desenhar apenas geometrias disponíveis e válidas, sem criar polígonos fictícios.
- [x] **CR-RF-0110** — Renderizar destaques em camada `highlights` independente da base.
- [x] **CR-RF-0111** — Preservar estilo da cena ao salvar/abrir projeto JSON.
- [x] **CR-RF-0112** — Permitir reverter alterações de cor pelos controles antigos usando histórico de Undo.
- [x] **CR-RF-0113** — Preservar keyframes avançados de opacidade: controles legados não podem sobrescrever trilhas de 3+ keys ou Bézier.

### 05. Marcadores, cidades e rótulos

**Origem:** MVP v0.1 → v0.2.x. **Fontes principais:** `plugin/js/app.js; plugin/geo-data.js`.

- [x] **CR-RF-0114** — Criar marcador com latitude e longitude decimais.
- [x] **CR-RF-0115** — Criar marcador selecionando cidade pré-cadastrada.
- [x] **CR-RF-0116** — Usar duplo clique no mapa para preencher coordenadas de um marcador.
- [x] **CR-RF-0117** — Definir nome/rótulo de texto do marcador.
- [x] **CR-RF-0118** — Definir cor individual do ponto.
- [x] **CR-RF-0119** — Definir tamanho/raio individual do ponto.
- [x] **CR-RF-0120** — Exibir ponto na localização projetada no mapa.
- [x] **CR-RF-0121** — Exibir rótulo legível próximo ao ponto, conforme regras atuais do SVG.
- [x] **CR-RF-0122** — Manter marcadores diferentes na mesma cena.
- [x] **CR-RF-0123** — Selecionar marcadores existentes como origem e destino de rota.
- [x] **CR-RF-0124** — Remover marcador e impedir rotas com referências inválidas no resultado validado.
- [x] **CR-RF-0125** — Persistir marcadores no JSON editável.
- [x] **CR-RF-0126** — Não aceitar coordenadas vazias ou fora dos intervalos geográficos válidos.
- [x] **CR-RF-0127** — Escapar caracteres especiais de rótulos ao produzir SVG.
- [x] **CR-RF-0128** — Renderizar marcadores e rótulos na camada raster `markers` quando exportação separada.
- [ ] **CR-RF-0129** — **[Não implementado]** Criar rótulos vetoriais editáveis como Text+ nativo no Fusion (atualmente ficam rasterizados).

### 06. Rotas e setas animadas — funcionalidade atual

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/js/app.js; plugin/animation/index.js`.

- [x] **CR-RF-0130** — Criar rota entre dois marcadores distintos da mesma cena.
- [x] **CR-RF-0131** — Selecionar explicitamente marcador de origem.
- [x] **CR-RF-0132** — Selecionar explicitamente marcador de destino.
- [x] **CR-RF-0133** — Oferecer rota como linha contínua.
- [x] **CR-RF-0134** — Oferecer rota com estilo tracejado.
- [x] **CR-RF-0135** — Oferecer seta animada com ponta direcional.
- [x] **CR-RF-0136** — Definir cor individual da rota.
- [x] **CR-RF-0137** — Definir espessura em pixels da rota.
- [x] **CR-RF-0138** — Definir curvatura percentual da rota entre dois pontos.
- [x] **CR-RF-0139** — Definir quadro inicial da animação de revelação da rota.
- [x] **CR-RF-0140** — Definir quadro final da animação de revelação da rota.
- [x] **CR-RF-0141** — Não renderizar a rota antes de seu quadro inicial.
- [x] **CR-RF-0142** — Revelar progressivamente o traçado conforme avanço dos quadros.
- [x] **CR-RF-0143** — Fazer a ponta da seta acompanhar a fração revelada do traçado.
- [x] **CR-RF-0144** — Projetar a rota como curva quadrática sobre o mapa 2D.
- [x] **CR-RF-0145** — Permitir múltiplas rotas na mesma cena.
- [x] **CR-RF-0146** — Manter intervalos temporais diferentes entre rotas.
- [x] **CR-RF-0147** — Salvar e abrir rotas com o projeto.
- [x] **CR-RF-0148** — Usar trilha `progress` independente para keyframes de progresso na cena v2.
- [x] **CR-RF-0149** — Preservar animação de rota ao alterar duração da cena, avaliando o novo último frame.
- [x] **CR-RF-0150** — Rejeitar origem/destino inexistentes e intervalos fora da duração.
- [x] **CR-RF-0151** — Rejeitar curvaturas de magnitude incompatível com os limites validados.
- [x] **CR-RF-0152** — Renderizar todas as rotas na camada raster `routes` na exportação separada.
- [x] **CR-RF-0153** — Evitar que o painel antigo de Início/Fim substitua trilhas de rota com easing/keyframes avançados.
- [ ] **CR-RF-0154** — **[Não implementado]** Controlar geometricamente uma rota com três ou mais waypoints e alças espaciais independentes.

### 07. Câmera, cartografia 2D e navegação

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/js/app.js; plugin/animation/index.js`.

- [x] **CR-RF-0155** — Controlar câmera por longitude do centro em graus.
- [x] **CR-RF-0156** — Controlar câmera por latitude do centro em graus.
- [x] **CR-RF-0157** — Controlar câmera por zoom numérico de 0 a 7.
- [x] **CR-RF-0158** — Definir quadro/pose inicial e final de câmera no modo legado.
- [x] **CR-RF-0159** — Interpolar poses de câmera com suavização temporal.
- [x] **CR-RF-0160** — Usar o arco longitudinal curto ao atravessar o antimeridiano.
- [x] **CR-RF-0161** — Restringir latitude à faixa válida da projeção Mercator adotada.
- [x] **CR-RF-0162** — Projetar geometria geográfica no plano 2D da viewport.
- [x] **CR-RF-0163** — Converter coordenadas de pixels do mapa em longitude/latitude para operações interativas.
- [x] **CR-RF-0164** — Disponibilizar botões de aproximar e afastar zoom.
- [x] **CR-RF-0165** — Permitir explorar a câmera temporariamente sem escrever keyframes quando Auto Key está desativado.
- [x] **CR-RF-0166** — Arrastar com mouse para deslocar mapa horizontalmente no sentido natural.
- [x] **CR-RF-0167** — Arrastar com mouse para deslocar mapa verticalmente no sentido natural (corrigido v0.3.3).
- [x] **CR-RF-0168** — Permitir gesto de zoom pela roda do mouse.
- [x] **CR-RF-0169** — Permitir voltar/recentralizar câmera ao estado de referência.
- [x] **CR-RF-0170** — Enquadrar automaticamente territórios selecionados pelo comando simples `Centralizar territórios`.
- [x] **CR-RF-0171** — Copiar posição/zoom da câmera atual para pose inicial ou final.
- [x] **CR-RF-0172** — Criar poses intermediárias de longitude, latitude e zoom via keyframes v2.
- [x] **CR-RF-0173** — Registrar os três canais de câmera em um único comando reversível.
- [x] **CR-RF-0174** — Manter a câmera atual no preview sincronizada ao quadro ativo.
- [x] **CR-RF-0175** — Interromper reprodução ao iniciar arraste que exija editar/explorar câmera.
- [x] **CR-RF-0176** — Preservar poses intermediárias quando a pose extrema é alterada.
- [ ] **CR-RF-0177** — **[Não implementado]** Permitir rotação/bearing da câmera durante a renderização do mapa (atualmente não suportado).
- [ ] **CR-RF-0178** — **[Não implementado]** Permitir caminho espacial Bézier editável para a câmera (não confundir com easing temporal).

### 08. Prévia, reprodução e interação com mapa

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/js/app.js; plugin/js/workspace-layout.js`.

- [x] **CR-RF-0179** — Exibir preview cartográfico atualizado de cada frame da cena.
- [x] **CR-RF-0180** — Exibir nome da cena e coordenadas/zoom da câmera.
- [x] **CR-RF-0181** — Reproduzir sequencialmente os quadros no preview.
- [x] **CR-RF-0182** — Pausar reprodução.
- [x] **CR-RF-0183** — Retornar ao primeiro quadro.
- [x] **CR-RF-0184** — Navegar para quadros por régua, timeline e controles temporais.
- [x] **CR-RF-0185** — Sincronizar valor de frame exibido e renderização de mapa.
- [x] **CR-RF-0186** — Usar resultados do mesmo avaliador para preview e exportação SVG/PNG.
- [x] **CR-RF-0187** — Exibir mudanças nos destaques, rotas e câmera durante a reprodução.
- [x] **CR-RF-0188** — Atualizar preview ao selecionar ou modificar keyframe.
- [x] **CR-RF-0189** — Exibir notificações de sucesso, estado e erro ao usuário.
- [x] **CR-RF-0190** — Oferecer preview estático sem Resolve para edição que não precisa de escrita em disco pelo host.
- [x] **CR-RF-0191** — Permitir a interação com a superfície do mapa para pan, zoom e ponto de marcador.
- [x] **CR-RF-0192** — Preservar a câmera do frame atual ao alternar modos de workspace.
- [x] **CR-RF-0193** — Manter apenas uma instância do mapa mesmo com preview flutuante no modo Foco.
- [ ] **CR-RF-0194** — **[Não implementado]** Reproduzir áudio/narração com waveform sincronizada à timeline para animar por falas.

### 09. Motor de animação, formato v2 e interpolação

**Origem:** v0.3.0 → v0.3.3. **Fontes principais:** `plugin/animation/index.js; contracts/scene-v2.schema.json`.

- [x] **CR-RF-0195** — Representar animação por trilhas (`tracks`) vinculadas a objeto e propriedade específicos.
- [x] **CR-RF-0196** — Permitir mais de dois keyframes em uma propriedade.
- [x] **CR-RF-0197** — Manter keyframes ordenados por frame inteiro.
- [x] **CR-RF-0198** — Impedir dois keyframes distintos no mesmo quadro e mesma trilha, substituindo valor quando aplicável.
- [x] **CR-RF-0199** — Definir chave por ID único, quadro, valor, modo de interpolação e parâmetros quando presentes.
- [x] **CR-RF-0200** — Avaliar cada quadro de forma determinística, independente de relógio e DOM.
- [x] **CR-RF-0201** — Permitir interpolação temporal Linear.
- [x] **CR-RF-0202** — Permitir interpolação temporal Hold/Step.
- [x] **CR-RF-0203** — Permitir interpolação temporal Smoothstep.
- [x] **CR-RF-0204** — Preservar Smoothstep legado para equivalência de cenas antigas.
- [x] **CR-RF-0205** — Permitir interpolação temporal cubic Bézier com controle `x1/y1/x2/y2`.
- [x] **CR-RF-0206** — Rejeitar Bézier inválida com coordenadas de controle temporal fora do domínio permitido.
- [x] **CR-RF-0207** — Respeitar valores exatamente nos extremos dos segmentos.
- [x] **CR-RF-0208** — Avaliar adequadamente zero, um e três ou mais keyframes.
- [x] **CR-RF-0209** — Implementar comportamento antes do primeiro keyframe (base/constante/preValue, conforme trilha).
- [x] **CR-RF-0210** — Implementar comportamento depois do último keyframe.
- [x] **CR-RF-0211** — Não modificar o objeto-fonte durante avaliação.
- [x] **CR-RF-0212** — Permitir trilhas independentes para longitude, latitude e zoom de câmera.
- [x] **CR-RF-0213** — Permitir trilha independente de opacidade de território.
- [x] **CR-RF-0214** — Permitir trilha independente de progresso de rota.
- [x] **CR-RF-0215** — Permitir habilitar/desabilitar trilha de animação no contrato.
- [x] **CR-RF-0216** — Impedir escrita em trilha bloqueada por comandos de edição.
- [x] **CR-RF-0217** — Rejeitar valor incompatível com tipo da propriedade.
- [x] **CR-RF-0218** — Validar IDs de objeto/trilha antes de comando.
- [x] **CR-RF-0219** — Expor operações `keyframe.upsert`, exclusão, movimento, cópia e alteração de easing.
- [x] **CR-RF-0220** — Expor operação de escala temporal de grupos (`keyframes.scale`) no motor — sem afirmar UI completa de retiming.
- [x] **CR-RF-0221** — Executar alterações de cena com comandos e inversas para Undo.
- [x] **CR-RF-0222** — Migrar câmera legada inicial/final preservando a curva visual anterior.
- [x] **CR-RF-0223** — Migrar fades territoriais e progresso de rotas anteriores sem mudança visual perceptível.
- [x] **CR-RF-0224** — Garantir comparação SVG de cenas antigas e convertidas em testes de regressão.
- [x] **CR-RF-0225** — Serializar e validar modelo `version:2` para salvar e renderizar.
- [x] **CR-RF-0226** — Empacotar bundle do motor localmente para Electron, sem CDN.
- [x] **CR-RF-0227** — Evitar recomputação baseada em parâmetros secretos/aleatórios em avaliação.
- [ ] **CR-RF-0228** — **[Parcial]** Expor todos os tipos já previstos no catálogo (`color`, `vector2`, `angle`, etc.) como propriedades efetivamente editáveis na interface — tipos definidos não significam efeitos implementados.

### 10. Timeline, keyframes e comandos de edição

**Origem:** v0.3.0 → v0.3.3. **Fontes principais:** `plugin/js/keyframe-timeline-ui.js; plugin/js/workspace-layout.js; plugin/animation/index.js`.

- [x] **CR-RF-0229** — Exibir timeline de animação com uma régua temporal compartilhada.
- [x] **CR-RF-0230** — Exibir trilha por propriedade animável de cada objeto.
- [x] **CR-RF-0231** — Agrupar trilhas de câmera, regiões e rotas por objeto.
- [x] **CR-RF-0232** — Expandir e recolher grupos de propriedades.
- [x] **CR-RF-0233** — Identificar propriedades por nomes legíveis em português.
- [x] **CR-RF-0234** — Representar keyframes visíveis como losangos nas trilhas.
- [x] **CR-RF-0235** — Diferenciar visualmente keyframe selecionado.
- [x] **CR-RF-0236** — Posicionar playhead no quadro correspondente na régua.
- [x] **CR-RF-0237** — Clicar na régua para navegar ao quadro.
- [x] **CR-RF-0238** — Arrastar continuamente o playhead com botão esquerdo pressionado (v0.3.3).
- [x] **CR-RF-0239** — Arrastar na área vazia de trilha para navegar continuamente sem exigir ponto específico.
- [x] **CR-RF-0240** — Reservar Shift+arrastar para seleção temporal por intervalo.
- [x] **CR-RF-0241** — Permitir selecionar keyframe individual com clique.
- [x] **CR-RF-0242** — Permitir selecionar vários keyframes por Shift+clique.
- [x] **CR-RF-0243** — Permitir selecionar keyframes dentro de um intervalo temporal.
- [x] **CR-RF-0244** — Permitir mover keyframes arrastando horizontalmente.
- [x] **CR-RF-0245** — Permitir mover conjunto selecionado por comando atômico.
- [x] **CR-RF-0246** — Rejeitar movimento de keyframes para quadros fora da cena.
- [x] **CR-RF-0247** — Rejeitar colisão temporal com keyframe existente na trilha.
- [x] **CR-RF-0248** — Criar keyframe da propriedade selecionada no quadro atual.
- [x] **CR-RF-0249** — Excluir keyframes selecionados sem afetar trilhas não relacionadas.
- [x] **CR-RF-0250** — Navegar até keyframe anterior/próximo de trilha selecionada.
- [x] **CR-RF-0251** — Copiar keyframes e offsets relativos.
- [x] **CR-RF-0252** — Colar keyframes usando quadro atual como âncora temporal.
- [x] **CR-RF-0253** — Rejeitar colagem em quadros ocupados ou fora da duração.
- [x] **CR-RF-0254** — Exibir zoom horizontal da timeline.
- [x] **CR-RF-0255** — Preservar scroll/zoom horizontal compartilhado nas trilhas.
- [x] **CR-RF-0256** — Permitir aumentar verticalmente a área da timeline.
- [x] **CR-RF-0257** — Oferecer Snap a frames/keyframes próximos, marcadores e playhead.
- [x] **CR-RF-0258** — Permitir ligar/desligar Snap.
- [x] **CR-RF-0259** — Criar marcador temporal no frame atual.
- [x] **CR-RF-0260** — Manter Auto Key visível e ativável.
- [x] **CR-RF-0261** — Com Auto Key, criar keyframe ao mudar uma propriedade animável pelo inspetor.
- [x] **CR-RF-0262** — Com Auto Key, registrar câmera no fim de arraste do mapa.
- [x] **CR-RF-0263** — Com Auto Key, registrar alteração de zoom pelos botões da câmera.
- [x] **CR-RF-0264** — Consolidar gesto contínuo de roda do mouse em uma única gravação de pose.
- [x] **CR-RF-0265** — Sem Auto Key, não criar poses ao apenas navegar pelo mapa.
- [x] **CR-RF-0266** — Registrar câmera manualmente com latitude, longitude e zoom na mesma ação.
- [x] **CR-RF-0267** — Reverter pose completa de câmera com um único Undo.
- [x] **CR-RF-0268** — Fornecer Undo/Redo para alterações de keyframes, easing e demais ações cobertas pelo histórico.
- [x] **CR-RF-0269** — Fornecer atalho `Ctrl+K` para registrar pose da câmera.
- [x] **CR-RF-0270** — Fornecer atalho `Espaço` para reproduzir/pausar quando fora de campos de texto.
- [x] **CR-RF-0271** — Fornecer setas esquerda/direita para caminhar 1 frame e Shift+setas para 10 frames.
- [x] **CR-RF-0272** — Fornecer `Home` e `End` para primeiro e último frame.
- [x] **CR-RF-0273** — Fornecer `Ctrl+Z`/`Ctrl+Y`, copiar/colar e exclusão via atalhos.
- [x] **CR-RF-0274** — Respeitar foco de input/textarea/select ao decidir consumir atalhos globais.
- [x] **CR-RF-0275** — Exibir inspector contextual com valor, quadro, propriedade e interpolação.
- [x] **CR-RF-0276** — Permitir editar frame de keyframe selecionado por campo numérico.
- [x] **CR-RF-0277** — Permitir alterar valor numérico de keyframe selecionado.
- [x] **CR-RF-0278** — Permitir escolher interpolação individual por segmento.
- [x] **CR-RF-0279** — Permitir editar valor-base da propriedade via opção avançada.
- [x] **CR-RF-0280** — Manter estado de seleção coerente após criar/colar/registrar pose.
- [x] **CR-RF-0281** — Apresentar instruções de uso/atalhos no editor.
- [ ] **CR-RF-0282** — **[Parcial]** Oferecer retiming visual em escala com alças de conjunto e seleção ampla (o motor já suporta operação de escala, mas a interface ainda é limitada).

### 11. Workspaces, navegação, Inspector e preview flutuante

**Origem:** v0.3.2 → v0.3.3. **Fontes principais:** `plugin/index.html; plugin/css/workspace.css; plugin/css/pixel-perfect.css; plugin/js/workspace-layout.js`.

- [x] **CR-RF-0283** — Oferecer Modo Padrão com mapa grande e timeline inferior.
- [x] **CR-RF-0284** — Oferecer Modo Foco com timeline maximizada na área útil da janela.
- [x] **CR-RF-0285** — Oferecer único botão `Expandir timeline` para entrar no Modo Foco.
- [x] **CR-RF-0286** — Oferecer `Restaurar layout` para retornar ao Modo Padrão.
- [x] **CR-RF-0287** — Permitir restaurar modo padrão com Esc fora de diálogo modal.
- [x] **CR-RF-0288** — Disponibilizar atalho de troca de layout configurado pelo editor (`Ctrl+Shift+F`).
- [x] **CR-RF-0289** — Preservar uma única instância de mapa, timeline e Inspector ao trocar modo.
- [x] **CR-RF-0290** — Preservar quadro/playhead atual entre os modos.
- [x] **CR-RF-0291** — Preservar keyframes e trilha selecionados entre os modos.
- [x] **CR-RF-0292** — Preservar zoom e posição de rolagem entre os modos.
- [x] **CR-RF-0293** — Preservar grupos de propriedades abertos/recolhidos entre os modos.
- [x] **CR-RF-0294** — Preservar flags Auto Key e Snap entre os modos.
- [x] **CR-RF-0295** — Preservar histórico Undo/Redo entre os modos.
- [x] **CR-RF-0296** — Não modificar a cena nem criar entrada de histórico só por alternar layout.
- [x] **CR-RF-0297** — Permitir árvore pesquisável de objetos e propriedades no Modo Foco.
- [x] **CR-RF-0298** — Filtrar trilhas por termo buscado na árvore.
- [x] **CR-RF-0299** — Sincronizar escolha da árvore com timeline, Inspector e Graph Editor.
- [x] **CR-RF-0300** — Oferecer colunas de objetos, edição central e Inspector no Modo Foco.
- [x] **CR-RF-0301** — Oferecer painel Inspector ao lado da timeline no layout refinado.
- [x] **CR-RF-0302** — Alternar entre Graph Editor e Dope Sheet na parte inferior.
- [x] **CR-RF-0303** — Disponibilizar preview flutuante do mapa no Modo Foco.
- [x] **CR-RF-0304** — Permitir mostrar/ocultar preview flutuante.
- [x] **CR-RF-0305** — Permitir reposicionar preview flutuante arrastando barra de título.
- [x] **CR-RF-0306** — Permitir redimensionar preview flutuante.
- [x] **CR-RF-0307** — Restaurar o preview ao mapa principal no Modo Padrão.
- [x] **CR-RF-0308** — Oferecer comando `Enquadrar cena` para ajustar a escala da duração.
- [x] **CR-RF-0309** — Oferecer comando `Enquadrar seleção` para ajustar o foco temporal dos keyframes selecionados.
- [x] **CR-RF-0310** — Mostrar timecode de frame por FPS em `HH:MM:SS:FF` sem drop-frame.
- [x] **CR-RF-0311** — Manter comandos reais de salvar/exportar acessíveis nos layouts adequados.
- [x] **CR-RF-0312** — Manter botão `Gerar no Fusion` acessível no rodapé do Modo Foco.
- [x] **CR-RF-0313** — Apresentar ligação real com os botões existentes de playback, Snap, Auto Key e edição.
- [x] **CR-RF-0314** — Usar nomes/identificação de objetos existentes em vez de controles meramente ilustrativos.
- [x] **CR-RF-0315** — Aplicar padrão de layout desktop nas resoluções testadas 1280×720, 1672×941 e 2560×1440.
- [x] **CR-RF-0316** — Eliminar menu superior Animação quando apenas duplicava a expansão (v0.3.3).
- [x] **CR-RF-0317** — Eliminar botões sem ação de Exportação no menu superior e lateral sem remover os comandos reais.
- [x] **CR-RF-0318** — Remover cartões duplicados de seleção de layouts de trabalho.
- [x] **CR-RF-0319** — Posicionar ações úteis do cabeçalho próximo ao título Timeline Focus em vez de centralizadas arbitrariamente.
- [ ] **CR-RF-0320** — **[Parcial]** Fornecer certificação visual pixel a pixel contra as imagens de referência em Windows/Resolve, com DPI e fontes do host real.

### 12. Graph Editor, Dope Sheet e curvas de velocidade atuais

**Origem:** v0.3.1 → v0.3.3. **Fontes principais:** `plugin/js/timeline-graph-editor.js; plugin/js/keyframe-timeline-ui.js; plugin/js/workspace-layout.js`.

- [x] **CR-RF-0321** — Exibir gráfico das amostras reais calculadas pelo avaliador da trilha selecionada.
- [x] **CR-RF-0322** — Exibir eixos de tempo (frame) e valor no Graph Editor.
- [x] **CR-RF-0323** — Exibir playhead sobre o gráfico sincronizado com a timeline.
- [x] **CR-RF-0324** — Plotar pontos reais de keyframe da trilha.
- [x] **CR-RF-0325** — Selecionar keyframe da trilha ao clicar perto de seu ponto na curva.
- [x] **CR-RF-0326** — Exibir curva representativa para propriedades numéricas, longitude e progresso de rota suportados.
- [x] **CR-RF-0327** — Respeitar interpolação Hold/Step no gráfico de valores.
- [x] **CR-RF-0328** — Alternar Graph Editor/Dope Sheet sem alterar a cena.
- [x] **CR-RF-0329** — Listar keyframes reais da trilha selecionada no Dope Sheet.
- [x] **CR-RF-0330** — Selecionar keyframe pelo Dope Sheet, sincronizando tempo e Inspector.
- [x] **CR-RF-0331** — Exibir miniatura de easing temporal no Inspector.
- [x] **CR-RF-0332** — Oferecer interpolação Linear, Hold, Suave, Suave (legado) e Bézier avançada.
- [x] **CR-RF-0333** — Oferecer presets de easing temporal Entrada, Saída e Suave.
- [x] **CR-RF-0334** — Expor alças Bézier temporais (`x1/y1/x2/y2`) no editor quando aplicáveis.
- [x] **CR-RF-0335** — Permitir arrastar diretamente as duas alças no mini-editor Bézier.
- [x] **CR-RF-0336** — Permitir no Graph Editor arrastar alças de um segmento numérico (v0.3.3).
- [x] **CR-RF-0337** — Permitir arrastar o trecho selecionado da curva de interpolação para alterar speed ramp (v0.3.3).
- [x] **CR-RF-0338** — Persistir as alterações de easing no keyframe de saída do segmento, e não somente no desenho.
- [x] **CR-RF-0339** — Atualizar prévia/curva após alterar valores Bézier.
- [x] **CR-RF-0340** — Agrupar cada gesto Bézier em uma única entrada de Undo.
- [x] **CR-RF-0341** — Desfazer/refazer a edição de speed ramp.
- [x] **CR-RF-0342** — Cancelar gesto de edição sem gravar alteração.
- [x] **CR-RF-0343** — Rejeitar entradas ou alças que produzam curva temporal inválida.
- [ ] **CR-RF-0344** — **[Parcial]** Oferecer editor profissional de curvas de velocidade com visualização `valor x tempo` e `velocidade x tempo` alternativas.
- [ ] **CR-RF-0345** — **[Parcial]** Oferecer controle completo de tangentes e pesos por keyframe de vários canais simultaneamente.
- [ ] **CR-RF-0346** — **[Parcial]** Oferecer retiming avançado direto no Graph Editor em trechos múltiplos.

### 13. Renderização SVG e exportação PNG/frames

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/js/app.js; plugin/main.js; plugin/fusion-comp.js`.

- [x] **CR-RF-0347** — Gerar mapa vetorial intermediário SVG para o frame avaliado.
- [x] **CR-RF-0348** — Rasterizar SVG no preview/exportação para PNG.
- [x] **CR-RF-0349** — Exportar imagem estática do frame selecionado.
- [x] **CR-RF-0350** — Oferecer saída HD 1280×720.
- [x] **CR-RF-0351** — Oferecer saída Full HD 1920×1080.
- [x] **CR-RF-0352** — Oferecer saída UHD 3840×2160.
- [x] **CR-RF-0353** — Exportar sequências com FPS da cena 24, 25 ou 30.
- [x] **CR-RF-0354** — Exportar de 1 a 480 quadros por cena no limite atual.
- [x] **CR-RF-0355** — Oferecer exportação com quatro camadas separadas.
- [x] **CR-RF-0356** — Gerar camada `base` com oceano, terras, fronteiras e grade.
- [x] **CR-RF-0357** — Gerar camada `highlights` com destaques territoriais.
- [x] **CR-RF-0358** — Gerar camada `routes` com linhas/setas.
- [x] **CR-RF-0359** — Gerar camada `markers` com pontos e textos.
- [x] **CR-RF-0360** — Oferecer exportação alternativa de camada única `composite`.
- [x] **CR-RF-0361** — Gerar arquivos com padrão `map_0000.png`, `map_0001.png`, etc.
- [x] **CR-RF-0362** — Criar diretório individual por título de cena e timestamp.
- [x] **CR-RF-0363** — Gerar arquivo `scene.cartorig.json` junto à sequência.
- [x] **CR-RF-0364** — Gerar `export.json` com FPS, largura, altura, total e lista de camadas.
- [x] **CR-RF-0365** — Gerar `CREDITOS.txt` para atribuição de dados cartográficos.
- [x] **CR-RF-0366** — Exibir progresso do render e opção de cancelamento.
- [x] **CR-RF-0367** — Não declarar concluída uma exportação cancelada.
- [x] **CR-RF-0368** — Preservar diretório parcial e registrar `INCOMPLETO.txt` quando cancelada.
- [x] **CR-RF-0369** — Validar índices de quadro no IPC antes da gravação.
- [x] **CR-RF-0370** — Validar lista de camadas permitidas no IPC.
- [x] **CR-RF-0371** — Validar integridade do PNG recebido antes de gravar no disco.
- [x] **CR-RF-0372** — Validar dimensões de PNG segundo resolução escolhida.
- [x] **CR-RF-0373** — Evitar sobrescrever frames já gravados com o mesmo índice/camada.
- [x] **CR-RF-0374** — Impedir finalização sem completar os PNGs esperados.
- [x] **CR-RF-0375** — Preservar transparência das camadas raster destinadas à composição.
- [x] **CR-RF-0376** — Assegurar que caracteres de rótulos sejam escapados para não gerar SVG inválido.
- [ ] **CR-RF-0377** — **[Não implementado]** Exportar sequências acima de 480 quadros com chunks e retomada após interrupção.
- [ ] **CR-RF-0378** — **[Não implementado]** Renderizar apenas quadros afetados por mudanças de keyframe, sem repetir o material idêntico.

### 14. Gerenciador de sequências exportadas

**Origem:** v0.2.8 → v0.3.3. **Fontes principais:** `plugin/export-manager.js; plugin/js/export-manager-ui.js; plugin/main.js`.

- [x] **CR-RF-0379** — Oferecer comando de abrir `Gerenciar sequências exportadas / importar no Fusion`.
- [x] **CR-RF-0380** — Solicitar pasta principal de exportações por seletor de diretório.
- [x] **CR-RF-0381** — Aceitar seleção direta da pasta de uma única exportação.
- [x] **CR-RF-0382** — Descobrir exports nas subpastas imediatas da pasta escolhida.
- [x] **CR-RF-0383** — Não varrer recursivamente diretórios arbitrariamente profundos.
- [x] **CR-RF-0384** — Limitar quantidade de exports descobertos por busca.
- [x] **CR-RF-0385** — Exibir lista de cenas/exportações encontradas.
- [x] **CR-RF-0386** — Pesquisar cenas da lista por nome/título.
- [x] **CR-RF-0387** — Exibir título, nome da pasta e metadados disponíveis.
- [x] **CR-RF-0388** — Exibir resolução, FPS e duração derivada de frames/FPS.
- [x] **CR-RF-0389** — Exibir número e tipos de camadas da exportação.
- [x] **CR-RF-0390** — Exibir primeira imagem de cada camada quando houver `nativeImage` disponível.
- [x] **CR-RF-0391** — Combinar as prévias das camadas na interface quando possível.
- [x] **CR-RF-0392** — Distinguir exportação válida de manifest malformado na listagem.
- [x] **CR-RF-0393** — Validar formato e tamanho de `export.json`.
- [x] **CR-RF-0394** — Validar campos de FPS, dimensões, total de frames e lista de camadas.
- [x] **CR-RF-0395** — Validar existência de todos os PNGs esperados em cada camada.
- [x] **CR-RF-0396** — Validar assinatura PNG, chunk de início `IHDR`, largura/altura e fim `IEND`.
- [x] **CR-RF-0397** — Rejeitar PNG ausente, truncado, simbólico/arquivo não regular ou com dimensão divergente.
- [x] **CR-RF-0398** — Exibir erro específico de camada e frame quando a sequência é incompleta.
- [x] **CR-RF-0399** — Bloquear importação enquanto a exportação selecionada não passou na validação.
- [x] **CR-RF-0400** — Revalidar exportação imediatamente antes da importação no Fusion.
- [x] **CR-RF-0401** — Não modificar timeline nem projeto ao apenas listar/inspecionar sequências.
- [x] **CR-RF-0402** — Permitir cancelar seleção ou fechar gerenciador sem importar.
- [x] **CR-RF-0403** — Exigir ação explícita `Confirmar importação no Fusion`.
- [x] **CR-RF-0404** — Usar identificadores opacos de exportação em vez de aceitar caminho arbitrário enviado pela UI.
- [x] **CR-RF-0405** — Impedir tentativa de importar uma exportação fora do diretório autorizado na sessão.
- [x] **CR-RF-0406** — Reaproveitar PNGs já exportados sem renderizar novamente.

### 15. Integração DaVinci Resolve / Fusion

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/main.js; plugin/fusion-comp.js; plugin/fusion-runner.js; plugin/bridge/cartorig-insert.lua; plugin/import-attempts.js`.

- [x] **CR-RF-0407** — Oferecer botão `Gerar no Fusion` para renderizar e iniciar inserção da composição.
- [x] **CR-RF-0408** — Exigir uma exportação válida antes de tentar inserção.
- [x] **CR-RF-0409** — Preparar arquivo `.comp` de fallback ao gerar exportação.
- [x] **CR-RF-0410** — Gerar composição com Loader para cada sequência/camada.
- [x] **CR-RF-0411** — Gerar nós Merge para combinar quatro camadas com ordenação prevista.
- [x] **CR-RF-0412** — Gerar saída `MediaOut` para composição.
- [x] **CR-RF-0413** — Evitar Merge desnecessário quando há camada única composite.
- [x] **CR-RF-0414** — Definir referências relativas/seguras às sequências para arquivo `.comp`.
- [x] **CR-RF-0415** — Gerar arquivo de job/instruções do executor Lua.
- [x] **CR-RF-0416** — Localizar `fuscript.exe` em caminhos oficiais do Resolve no Windows.
- [x] **CR-RF-0417** — Permitir override verificável de localização de `fuscript.exe` em instalações personalizadas.
- [x] **CR-RF-0418** — Executar script Lua para tentar criar Fusion Composition na timeline ativa.
- [x] **CR-RF-0419** — Criar e conectar loaders/merges/media output por API Lua quando disponível.
- [x] **CR-RF-0420** — Usar `Composition.Lock/Unlock` para evitar diálogos Open File durante criação de Loaders.
- [x] **CR-RF-0421** — Garantir Unlock também em caminhos de falha/erro.
- [x] **CR-RF-0422** — Oferecer alternativa de invocação pelo menu Scripts → Utility.
- [x] **CR-RF-0423** — Oferecer fallback manual importando `CartoRig.comp` para composição vazia.
- [x] **CR-RF-0424** — Oferecer alternativa de importar sequências PNG manualmente pelo Media Pool.
- [x] **CR-RF-0425** — Informar caminho dos arquivos de fallback quando inserção automática não puder ser confirmada.
- [x] **CR-RF-0426** — Interpretar registro estruturado de resultado Lua `OK|IMPORTED`.
- [x] **CR-RF-0427** — Interpretar estado parcial `PARTIAL` quando clipe foi criado sem completar os nós.
- [x] **CR-RF-0428** — Não tratar erro de processo ou ausência de confirmação Lua como sucesso.
- [x] **CR-RF-0429** — Distinguir confirmação do Lua do mero exit code do executável.
- [x] **CR-RF-0430** — Impedir repetição da mesma tentativa/job idempotente pelo script Lua.
- [x] **CR-RF-0431** — Permitir importar novamente a mesma exportação após excluir clipe da timeline (v0.2.9).
- [x] **CR-RF-0432** — Permitir importar cópia intencional da mesma exportação em outra timeline.
- [x] **CR-RF-0433** — Exigir confirmação extra quando existe importação anterior OK, parcial ou incerta.
- [x] **CR-RF-0434** — Não bloquear permanentemente o reuso porque `cartorig-fusion-result.txt` antigo existe.
- [x] **CR-RF-0435** — Criar ID de tentativa e diretório isolado em `cartorig-imports/<id>`.
- [x] **CR-RF-0436** — Registrar resultados de tentativas diferentes sem sobrescrever histórico.
- [x] **CR-RF-0437** — Rejeitar importações simultâneas ou duplo clique concorrente.
- [x] **CR-RF-0438** — Cancelar tentativa antes de iniciar sem criar job.
- [x] **CR-RF-0439** — Preservar PNGs diante de falha, cancelamento ou inserção parcial do Fusion.
- [x] **CR-RF-0440** — Validar caminhos de pastas/nomes antes de gerar referência de Loader ou script.
- [x] **CR-RF-0441** — Conservar alternativa raster de quatro camadas como contrato principal do Fusion.
- [ ] **CR-RF-0442** — **[Não implementado]** Converter keyframes cartográficos em ferramentas/nós nativos Fusion editáveis na timeline do Resolve, por propriedade suportada.
- [ ] **CR-RF-0443** — **[Não implementado]** Confirmar automaticamente existência atual de um clipe inserido na timeline quando a API disponível permitir consulta confiável.
- [ ] **CR-RF-0444** — **[Parcial]** Certificar no Resolve Windows real duração/clipe, Loader, Merge, MediaOut e sincronização de FPS para versões 20/21.

### 16. Comportamentos de erro, acessibilidade e documentação funcional

**Origem:** MVP v0.1 → v0.3.3. **Fontes principais:** `plugin/main.js; plugin/js/app.js; plugin/js/keyframe-timeline-ui.js; tests/`.

- [x] **CR-RF-0445** — Fornecer mensagens de erro legíveis ao rejeitar exportação ou cena inválida.
- [x] **CR-RF-0446** — Não abrir diálogo do host ao apenas inspecionar metadados de exportação.
- [x] **CR-RF-0447** — Rejeitar entrada de cena com rotas apontando para IDs ausentes.
- [x] **CR-RF-0448** — Rejeitar dimensões de exportação divergentes dos presets disponíveis.
- [x] **CR-RF-0449** — Proteger paths e arquivos envolvidos em exportação/importação contra nomes perigosos.
- [x] **CR-RF-0450** — Exibir estados de conexão e status da exportação em vez de presumir sucesso.
- [x] **CR-RF-0451** — Permitir desfazer alterações após edição visual de câmera, fade e keyframes.
- [x] **CR-RF-0452** — Impedir que arraste de alça Bézier cancelado crie alteração de cena.
- [x] **CR-RF-0453** — Fornecer foco visível e títulos acessíveis aos principais controles de keyframes.
- [x] **CR-RF-0454** — Oferecer `aria-label`/títulos para mapa, trilhas e botões conforme implementação atual.
- [x] **CR-RF-0455** — Manter documentação de instalação, funcionamento e solução de problemas em português.
- [x] **CR-RF-0456** — Documentar limitações de precisão da cartografia e atribuições de dados.
- [x] **CR-RF-0457** — Preservar avisos de terceiros e licença MIT do código.
- [x] **CR-RF-0458** — Separar recursos confirmados por teste automatizado de integração ainda não certificada no Resolve real.
- [x] **CR-RF-0459** — Oferecer testes `npm test`, `npm run test:contracts` e `npm run test:lua` para o código.
- [x] **CR-RF-0460** — Oferecer testes em Chromium em múltiplos tamanhos de viewport.
- [x] **CR-RF-0461** — Executar workflow GitHub Actions em PR/push com Node, Lua e Chromium (branch v0.3.3).
- [x] **CR-RF-0462** — Registrar screenshots/relatórios de QA como artefatos de CI.
- [x] **CR-RF-0463** — Executar verificação de sintaxe dos módulos JS e bundle determinístico no workflow.
- [ ] **CR-RF-0464** — **[Parcial]** Publicar evidência automatizada de comparação pixel a pixel com referências de design reproduzíveis.
- [ ] **CR-RF-0465** — **[Não implementado]** Automatizar E2E real de DaVinci Resolve Studio Windows com SDK e vídeo renderizado.

---

## Parte B — As 42 features avançadas aprovadas (IDs originais)

A tabela abaixo preserva **cada uma das 42 features aprovadas** na especificação de animação v1.0, com estado atualizado pela implementação v0.3.3. A coluna *marco* é uma referência de roadmap, não promessa de entrega em data específica.

| ID | Estado atual | Marco | Requisito funcional e critério de aceite |
|---|---|---|---|
| **KF-01** | ✅ Implementado | v0.3.0 | **Keyframes múltiplos por propriedade:** Criar, substituir, excluir e avaliar três ou mais keys na mesma trilha. |
| **KF-02** | ✅ Implementado | v0.3.0 | **Timeline multicamadas:** Régua comum, trilhas por objeto/propriedade, seleção e playhead. |
| **KF-03** | ✅ Implementado | v0.3.1 | **Auto Keyframe:** Registrar propriedade/pose somente com o modo ativo; alteração pelo preview da câmera. |
| **KF-04** | 🟨 Parcial | v0.3.2–v0.4.0 | **Graph Editor profissional:** Gráfico de valores e edição Bézier limitada existem; ainda faltam curvas de velocidade completas e manipulação multicanal avançada. |
| **KF-05** | 🟨 Parcial | v0.3.0–v0.4.0 | **Easing individual completo:** Linear, Smoothstep, Hold e Bézier por segmento existem; experiência plena Ease In/Out/InOut e tangentes avançadas permanece parcial. |
| **KF-06** | ✅ Implementado | v0.3.0 | **Trilhas independentes:** Zoom/posição/opacidade/progresso separados sem sobrescrever outro canal. |
| **KF-07** | ✅ Implementado | v0.3.0 | **Copiar, colar e duplicar keyframes:** Colagem relativa com IDs próprios, validação de limites e Undo. |
| **KF-08** | 🟨 Parcial | v0.3.0–v0.4.0 | **Mover e escalar grupos de keyframes:** Movimento múltiplo e comando de escala no motor; retiming visual completo ainda pendente. |
| **KF-09** | ✅ Implementado | v0.3.0 | **Snap e marcadores:** Snap configurável, playhead, marcadores temporais e keys. |
| **KF-10** | ✅ Implementado | v0.3.0 | **Undo/Redo:** Comandos reversíveis de edição e poses atômicas. |
| **CAM-11** | ✅ Implementado | v0.3.0 | **Câmera multiponto por keyframes:** Trilhas de lon/lat/zoom aceitam múltiplas poses; não inclui trajetória espacial Bézier. |
| **CAM-12** | ⬜ Planejado | v0.4.0 | **Trajetória Bézier espacial da câmera:** Editar alças geográficas e caminho espacial, distinto do Bézier temporal do Graph Editor. |
| **CAM-13** | ⬜ Planejado | v0.4.0 | **Fly-to cinematográfico:** Zoom de altitude intermediária e deslocamento geográfico suave entre locais distantes. |
| **CAM-14** | ⬜ Planejado | v0.4.0 | **Bearing / rotação da câmera:** Animar direção do mapa, preservando referências e legibilidade de rótulos. |
| **CAM-15** | ⬜ Planejado | v0.4.0 | **Zoom ancorado:** Manter coordenada geográfica escolhida fixa sob a âncora da viewport. |
| **CAM-16** | 🟨 Parcial | v0.1–v0.4.0 | **Auto Frame / Fit Bounds completo:** Centralização de territórios existe; falta enquadramento amplo de estados, rotas e antimeridiano. |
| **CAM-17** | ⬜ Planejado | v0.4.0 | **Velocidade geográfica constante:** Percorrer caminho por distância geográfica ou de tela, opção explícita. |
| **CAM-18** | ⬜ Planejado | v0.4.0 | **Camera Follow:** Seguir objeto/marcador em movimento com offset previsível. |
| **GEO-19** | ⬜ Planejado | v0.5.0 | **Cor animada de território:** Interpolar RGB/space explícito por keyframes mantendo extremos exatos. |
| **GEO-20** | ✅ Implementado | v0.3.0 | **Opacidade territorial por keyframe:** Trilha de opacidade com múltiplos keys 0..1; além do fade legado. |
| **GEO-21** | ⬜ Planejado | v0.5.0 | **Stroke Reveal de fronteiras:** Desenhar perímetro de Polygon/MultiPolygon progressivamente. |
| **GEO-22** | ⬜ Planejado | v0.5.0 | **Fill Reveal territorial:** Preenchimento radial/direcional com clipping real do polígono. |
| **GEO-23** | ⬜ Planejado | v0.5.0 | **Pulsação de território:** Pulse de opacidade/borda reprodutível e controlável. |
| **GEO-24** | ⬜ Planejado | v0.5.0 | **Espessura animada da fronteira:** Controlar stroke width com keyframes em unidades definidas. |
| **GEO-25** | ⬜ Planejado | v0.5.0 | **Glow animado:** Animar intensidade/raio de brilho com orçamento de render. |
| **GEO-26** | ⬜ Planejado | v0.5.0 | **Scale/Pop:** Escala/overshoot de região, marcador ou rótulo. |
| **GEO-27** | ⬜ Planejado | v0.5.0 | **Presets de destaque:** Aplicar e editar keyframes/efeitos de destaque como uma operação. |
| **ROUTE-28** | ⬜ Planejado | v0.5.0 | **Rotas multiponto:** Trajetória com três ou mais waypoints. |
| **ROUTE-29** | ⬜ Planejado | v0.5.0 | **Path Editor Bézier:** Editar handles espaciais e tangentes da rota. |
| **ROUTE-30** | 🟨 Parcial | v0.1–v0.5.0 | **Trim Path Start/End independentes:** Progresso de revelação atual existe; faltam controles simultâneos independentes de início e fim do traço. |
| **ROUTE-31** | ⬜ Planejado | v0.5.0 | **Moving Object:** Mover ícone separado pela distância acumulada no caminho. |
| **ROUTE-32** | ⬜ Planejado | v0.5.0 | **Orient Along Path:** Orientação do ícone pela tangente da trajetória e offset. |
| **ROUTE-33** | ⬜ Planejado | v0.5.0 | **Trailing Line:** Criar rastro de comprimento/tempo ajustável. |
| **ROUTE-34** | 🟨 Parcial | v0.1–v0.5.0 | **Dashed Motion:** Linha tracejada estática existe; deslocamento animado do padrão não. |
| **ROUTE-35** | ⬜ Planejado | v0.5.0 | **Route Morphing:** Transformar rotas com reamostragem de geometrias. |
| **ROUTE-36** | 🟨 Parcial | v0.3.0–v0.5.0 | **Velocidade variável por segmento:** Keys de progresso com Bézier temporal existem; editor completo por segmentos/waypoints não. |
| **MG-37** | 🟨 Parcial | v0.3.1–v0.5.0 | **Presets cinematográficos:** Presets simples de easing existem; Fly-in, Fly-out, Country Reveal e câmera completa ainda não. |
| **MG-38** | ⬜ Planejado | v0.5.0 | **Parent & Constraints:** Vínculos objetos/câmera, hierarquia e detecção de ciclos. |
| **MG-39** | ⬜ Planejado | v0.5.0 | **Grupos e animação em cascata:** Selecionar objetos e aplicar stagger por frame/ordem definida. |
| **MG-40** | 🟨 Parcial | v0.3.1–v0.4.0 | **Marcadores de sincronização:** Marcadores temporais simples existem; integração com narração/áudio e eventos ampliados ainda não. |
| **MG-41** | ⬜ Planejado | v0.5.0 | **Loop, Ping-Pong e Hold de animações:** Repetição temporal e inversão configuráveis de trechos; Hold isolado de interpolação já existe. |
| **MG-42** | ⬜ Planejado | v0.5.0 | **Expressions seguras:** AST restrita sem `eval`, ciclos e budgets de execução. |

### Integração transversal pós-v0.5 — Fusion nativo (v0.6.0)

**RF-FUSION-NATIVE-01 — [Não implementado]** Converter, apenas quando houver suporte verificado por testes reais na API do Resolve, propriedades animadas selecionadas em keyframes/nós nativos do Fusion, preservando fallback PNG e exportação `.comp`. A especificação aprovada trata a integração v0.6.0 como eixo transversal, **não como 43ª feature**.

---

## Parte C — Requisitos de aceite transversais e restrições

Estes critérios cruzam muitos requisitos individuais e são necessários para aceitar novas versões:

- [ ] **ACC-01** — Preview do frame N e PNG exportado do frame N devem usar o mesmo estado avaliado.
- [ ] **ACC-02** — A mudança em uma trilha não pode modificar trilhas ou geometrias não relacionadas.
- [ ] **ACC-03** — Toda alteração da cena feita por ação mutável suportada deve ser validada e passível de Undo/Redo.
- [ ] **ACC-04** — Arquivos `version:1` devem reproduzir comportamento visual legado quando convertidos para `version:2`.
- [ ] **ACC-05** — Aborto de exportação ou falha Lua não podem destruir o projeto ou PNGs já gerados.
- [ ] **ACC-06** — Botões visíveis precisam ter ação funcional ou ficar indisponíveis com justificativa explícita; nada de UI cenográfica.
- [ ] **ACC-07** — Alternar workspaces não altera o JSON, keyframes, zoom, seleção nem histórico.
- [ ] **ACC-08** — A confirmação de importação deve ser associada à tentativa atual, nunca inferida de um registro de sucesso antigo.
- [ ] **ACC-09** — Graph Editor deve editar o easing real, não apenas simular a curva desenhada.
- [ ] **ACC-10** — Scrubbing deve acompanhar mouse com botão pressionado de modo contínuo na régua e nas áreas livres.
- [ ] **ACC-11** — Arrastar o mapa deve seguir o mouse nos eixos horizontal e vertical, respeitando Auto Key.
- [ ] **ACC-12** — Sequência invalidada por PNG ausente ou incompleto não pode ser enviada ao Fusion.
- [ ] **ACC-13** — Nova versão só é promovida à `main` após testes de regressão e aprovação do responsável.
- [ ] **ACC-14** — A certificação Fusion real requer testes no Resolve Windows e não pode ser substituída por mock de Lua.
- [ ] **ACC-15** — Alterações na interface devem passar em testes de viewport e inspeção visual comparativa; testes DOM não garantem pixel perfect.

## Parte D — Ideias históricas fora do conjunto das 42 features aprovadas

Estes itens surgiram como possibilidades de produto. **Não são implementados nem devem ser considerados compromissos de versão** sem especificação e aprovação próprias.

- [ ] **FUT-01** — Suporte nativo a tiles XYZ e basemaps raster com proveniência/licenças verificadas.
- [ ] **FUT-02** — Camadas vetoriais editáveis no Fusion por entidade geográfica.
- [ ] **FUT-03** — Globo terrestre 3D e transição 2D/3D.
- [ ] **FUT-04** — Terreno, elevação e superfícies 3D.
- [ ] **FUT-05** — Extrusão de polígonos e edifícios.
- [ ] **FUT-06** — Mapas de satélite e provedores comerciais de tiles com licenças próprias.
- [ ] **FUT-07** — Suporte a arquivos GeoPackage, shapefile e importação CSV de dados em lote.
- [ ] **FUT-08** — Geocodificação global de endereços e serviços online de busca de locais.
- [ ] **FUT-09** — Sincronização bidirecional de keyframes do Resolve/Fusion com o projeto CartoRig.
- [ ] **FUT-10** — Sistema de templates comerciais, marketplace e plugins externos.

## Parte E — Cenários ponta a ponta para verificar o produto

- [ ] **E2E-01** — Criar cena offline → adicionar Brasil e Venezuela → estilizar regiões → criar Caracas/Brasília → seta progressiva → câmera → salvar → abrir → preview.
- [ ] **E2E-02** — Importar GeoJSON válido → pesquisar estado/cidade → selecionar/estilizar → persistir cena → reabrir → renderizar.
- [ ] **E2E-03** — Animar câmera em 3+ poses com Auto Key → alterar curva → arrastar playhead → Undo/Redo → exportar sequência.
- [ ] **E2E-04** — Exportar 4 camadas × N frames → verificar `export.json` e cada PNG → importar no Fusion → excluir clipe → importar nova cópia confirmada.
- [ ] **E2E-05** — Abrir cena v1 → migrar v2 → comparar golden SVG/PNG nos frames equivalentes.
- [ ] **E2E-06** — Expandir/restaurar timeline repetidamente → preservar seleção, zoom, rolagem, frame, preview, Auto Key, Snap e Undo.
- [ ] **E2E-07** — Arrastar alça Bézier e trecho de curva → verificar mudança de velocidade → cancelar gesto sem alteração → desfazer/refazer.
- [ ] **E2E-08** — Tentar PNG faltante, JSON inválido, rota sem marcador e caminhos indevidos → erros claros sem criar clip.
- [ ] **E2E-09** — Executar CI de Node, Lua simulada, bundle e Chromium CSP real em cada PR; arquivar screenshots.
- [ ] **E2E-10** — Validar no Resolve Windows real o clip, Loader, Merge, MediaOut, duração, FPS, exportação e reimportação.

## Parte F — Fontes e rastreabilidade

**Código atual:** [`main`](https://github.com/gabrielbugarelli/cartorig/tree/main) (v0.3.2); [`feature/stabilization-v0.3.3`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3) (v0.3.3 com correções, PR [#2](https://github.com/gabrielbugarelli/cartorig/pull/2)); PR de correções [#3](https://github.com/gabrielbugarelli/cartorig/pull/3) (integrado à estabilização).

- [`README.md`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/README.md) — guia e limites de uso.
- [`CHANGELOG.md`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/CHANGELOG.md) — histórico e versões.
- [`QA-REPORT.md`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/QA-REPORT.md) — evidências de testes.
- [`STATUS.md`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/STATUS.md) — marco atual.
- [`plugin/js/app.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/js/app.js) — render e fluxo da cena.
- [`plugin/animation/index.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/animation/index.js) — motor e migração.
- [`plugin/geo-data.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/geo-data.js) — GeoJSON, downloads e cache.
- [`plugin/export-manager.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/export-manager.js) — descoberta e validação de exportações.
- [`plugin/import-attempts.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/import-attempts.js) — histórico de importações.
- [`plugin/fusion-comp.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/fusion-comp.js) — arquivo .comp.
- [`plugin/fusion-runner.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/fusion-runner.js) — execução FuScript.
- [`plugin/bridge/cartorig-insert.lua`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/bridge/cartorig-insert.lua) — integração Lua.
- [`plugin/js/keyframe-timeline-ui.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/js/keyframe-timeline-ui.js) — timeline e keyframes.
- [`plugin/js/workspace-layout.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/js/workspace-layout.js) — workspaces e preview.
- [`plugin/js/timeline-graph-editor.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/js/timeline-graph-editor.js) — curvas e speed ramps.
- [`plugin/main.js`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/plugin/main.js) — host Electron e IPC.
- [`tests/`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/tests/) — casos de regressão.
- [`docs/animation/`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/docs/animation/) — especificações de animação existentes no repo.
- [`contracts/scene-v2.schema.json`](https://github.com/gabrielbugarelli/cartorig/tree/feature/stabilization-v0.3.3/contracts/scene-v2.schema.json) — contrato de cena v2.

**Especificação formal original:** “CartoRig — Especificações de Animação v1.0”, com 42 IDs aprovados, contrato de cena v2, roadmap e matriz de 129 cenários. Os IDs foram preservados na Parte B. Para exigências futuras, ela continua sendo fonte de comportamento-alvo; este inventário registra a situação efetiva até v0.3.3.

### Limitações de cobertura declaradas

- “Implementado” não equivale a aprovação de compatibilidade em todas as versões do DaVinci Resolve Studio.
- Os serviços de mapa atuais usam base simplificada offline, não cartografia oficial universal nem dados de fronteira juridicamente vinculantes.
- Funções descritas apenas em protótipos visuais não são consideradas implementadas sem representação no código.
- O item `GEO-20` já tem implementação do objetivo v0.5 antecipada na v0.3.0; a numeração do roadmap original foi mantida.
- Uma futura auditoria de novas branches/PRs deve atualizar esta lista antes de declarar a próxima versão estável.

---

## Totais do inventário

- **Requisitos de base detalhados:** 465 (`443` implementados, `9` parciais, `13` não implementados).
- **Features avançadas aprovadas:** 42 (`9` implementadas, `9` parciais, `24` planejadas).
- **Ideias históricas ainda sem escopo aprovado:** 10.
- **Além disso:** 15 critérios transversais, 10 cenários E2E e um eixo de integração nativa Fusion v0.6.

**Observação sobre totais:** os 42 IDs avançados e os requisitos de base se sobrepõem intencionalmente. Não some os totais como se cada item fosse um produto distinto; a Parte A é decomposição funcional por módulo e a Parte B é o roadmap formal aprovado.