# 12 — Cobertura funcional de longo prazo comparável ao GEOlayers

**Escopo:** requisitos originais para um produto independente inspirado na categoria 'animação de mapas'. Não reproduzir código, UI, identidade visual, assets nem formatos proprietários do GEOlayers. O roadmap abaixo não transforma P1/P2 em requisitos de release 0.1.0.

## Referência de capacidade (publicamente descrita)
A página do GEOlayers 3 descreve pesquisa online geográfica, estilos customizados, mapas rotacionados/inclinados, etiquetas, dados CSV/TSV, edifícios/rios/ruas, rotas e terrenos 3D com dependências. Em 24/10/2026, também menciona melhorias em data visualization; a equivalência direta dessas funções **não** é garantida pelas APIs do Resolve. Fonte: https://aescripts.com/geolayers/.

## P1 — ferramenta documental completa 2D

| ID | Requisito | Contrato | Comportamento esperado |
|---|---|---|---|
| ADV-001 | Importação GeoJSON | `importGeoJSON(input, limits): FeatureCollection`, CRS WGS84 documentado; validado | `Polygon/MultiPolygon/Point/LineString`, buracos, dateline e JSON malicioso |
| ADV-002 | Import CSV/TSV | Mapper guiado de colunas lon, lat, ISO3, valores, labels e locale | Amostra 10k linhas, duplicidades e encoding BOM, sem swap lon/lat |
| ADV-003 | Estatística por país/região | join por ISO3/featureID e escala linear/quantis, missing=estilo explícito | Ordem/valores e choropleth fixtures idênticos após reopen |
| ADV-004 | Fontes geográficas múltiplas | Catalog adapters (Natural Earth / arquivo próprio / provedor licenciado), provenance | Trocar dataset mantém IDs se possível, apresenta diff de fronteiras |
| ADV-005 | Pesquisa avançada | resultados tipados países/ADM1/cidades/POI, score e desambiguação | `São Paulo` município vs estado não seleciona sozinho |
| ADV-006 | Recurso desenhado no mapa | cliques criam linha, polígono e ponto WGS84 editáveis no editor | round-trip, edição vértices, distância e snap desativável |
| ADV-007 | Estilos extensos | paleta, stroke, camadas hidrografia/rodovias, labels e presets | toggle isolado não altera georreferência nem outros layers |
| ADV-008 | Labels inteligentes | evitar overlap previsivelmente, prioridade e idiomas; override manual persistente | 50 labels, collisions <= baseline e estabilidade por frame |
| ADV-009 | Animação de rotas avançada | pontos intermediários, curvas por waypoints, ritmo, trace, ícone móvel | objeto permanece sobre trajetória em todo frame |
| ADV-010 | Linhas de conexão | mesh one-to-many/many-to-many, sem duplicações | N pontos geram cardinalidade esperada, limite de desempenho |
| ADV-011 | Máscaras de água/terra | land/water shapes independentes por região | water holes sem preencher lagos, compositing 4K correto |
| ADV-012 | Diretório de templates | presets de cena, intro, zoom, foco, rotas, highlight, legenda | importar preset não sobrescreve IDs ou assets alheios |
| ADV-013 | API local de automação | CLI versionado e/ou IPC segura para criar cenas por JSON | batch 100 cenas sem abrir editor, recursos autorizados |
| ADV-014 | Provedores externos | conectores opcionais, quotas, caching, consentimento e licenças para vídeo | simular 401/429/cache-expired/offline/limite de tiles |
| ADV-015 | Temas a partir de imagem | extrair paleta local de imagem autorizada e mapear para tokens | resultados reproduzíveis, cores acessíveis, sem exportar imagem para servidor |
| ADV-016 | Distância/escala/rosa dos ventos | geodésica, projeção da escala e visibilidade | 100/1000km de referência e variação latitude corretas |

### Decisões de P1
- **Estilo e tiles:** estilo vector/raster provider só se licença permitir render export, cache e monetização. Cache isolado por provider/dataset.
- **CSV:** nunca confiar em entradas para executar fórmulas se exportar CSV novamente; proteger contra formula injection.
- **Desenhos:** a nova geometria do usuário fica no Scene e é editável no editor; possibilidade de export como máscara nativa depende do adaptador.
- **Labels:** usar layout determinístico por quadro; não promover conflito geométrico invisível (no preview um rótulo pode mudar com zoom, porém não deve saltar de lugar em cada frame sem tolerância).

## P2 — equivalente avançado em motion geográfico 3D

| ID | Requisito | Subcomponentes | Comportamento esperado |
|---|---|---|---|
| ADV-101 | Câmera 2.5D | pitch/heading, matriz de view/projeção, clipping e picking | anchors corretos em 0/30/60° e reversão de tela p/ geo |
| ADV-102 | Terreno de elevação | DEM licenciado, malha LOD, normais, luz/sombra | panorâmica com altitude validada, bordas sem fissura |
| ADV-103 | Satélite/imagens híbridas | provider com licença de audiovisual, cache permitido | render 4K sem tiles faltando, atribuição obrigatória |
| ADV-104 | Extrusão de prédios/regiões | alturas e base de dados de edifícios, escala de câmera | extrusão correta em coordenadas/referência de altura |
| ADV-105 | Rotas sobre terreno | amostragem 3D de altitude, offset e oclusão | trajetória acompanha superfície nas cenas documentadas |
| ADV-106 | Globo ou projeções alternadas | globo esfera, Mercator/ortográfica, transições | regiões polares e antimeridiano corretos nos extremos |
| ADV-107 | Finalização avançada | múltiplos materiais, sombras e atmosfera com workflow de compositor | render reproduzível, controle de qualidade e desempenho |
| ADV-108 | Dataviz em movimento | linhas estatísticas animadas, séries temporais, particles opcionais | leitura correta de data/fps, valores sem extrapolação |

### Gate específico de 3D
Não escolher OFX, Fuse, Fusion nativo, motor 3D externo ou export de sequência até realizar **prova comparativa** de qualidade, velocidade e controle editável. Documentar em ADR. Não anunciar 3D nativo em Fusion quando o sistema apenas renderizar uma sequência de imagens. Versão 3D pode exigir backend dedicado e dados licenciados.

## Regras de evolução para P1/P2
- Preservar compatibilidade do schema v1; adicionar `Scene v2` com migração explícita quando houver camadas novas.
- Criar `licenses/provider-matrix.json`, declarando `videoAllowed`, `offlineCacheAllowed`, `bulkRenderAllowed`, atribuição e expiração.
- Fontes não confiáveis devem respeitar limites de recursos, quotas e licenças; tratar antimeridiano e polos conforme contrato da projeção.
- Recursos anunciados como editáveis no Fusion exigem implementação nativa real; sequências raster devem ser rotuladas como rasterizadas.