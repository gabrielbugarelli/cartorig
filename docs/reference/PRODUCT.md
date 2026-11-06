# 01 — PRD: produto, escopo e critérios de aceite

## Visão e público
Software de uso pessoal/editorial para reduzir o tempo de produção de mapas documentais no DaVinci Resolve Studio/Fusion. Persona principal: editor que não deseja desenhar máscaras, linhas, keyframes e enquadramentos geográficos manualmente. Nome provisório: **Neo Atlas Maps**.

### Trabalhos que o produto resolve
1. "Ache Brasil e Venezuela e coloque no mapa em segundos."
2. "Faça um zoom de América do Sul para Brasília, mantendo fronteiras, rotas e marcadores corretos."
3. "Selecione mapa escuro, destaque Brasil e desenhe Caracas → Brasília."
4. "Gere uma composição Fusion, ajuste cor/opacidade/posição de rótulo e retorne ao painel para atualizar sem refazer tudo."
5. "Reutilize o mesmo mapa/preset em diversos vídeos e exporte 4K sem depender de mapas online."

## Requisitos funcionais P0 — MVP
Cada item tem ID permanente e critério de aceite funcional que orienta a implementação.

| ID | Especificação observável | Aceite inequívoco |
|---|---|---|
| MAP-001 | Criar cena com nome, resolução, fps, totalFrames, estilo | Novo arquivo válido no schema; defaults 3840x2160, 24, 240 |
| MAP-002 | Buscar países, capitais e cidades presentes no catálogo offline | `Brasil` retorna BRA, `Venezuela` VEN; resultados ambíguos exigem escolha |
| MAP-003 | Adicionar destaque de país/fronteira com cor/opacidade | Camada isolada e nomeada, sem alterar mapa-base |
| MAP-004 | Inserir marcador geoancorado e rótulo | Posição acompanha câmera; tamanho aparente de marcador/rótulo estável |
| MAP-005 | Criar rota de duas ou mais coordenadas com revelação | Visibilidade de 0% no frame inicial e 100% no final, sem teleporte |
| MAP-006 | Câmera com pan, zoom, bearing e keyframes | Frames de início/fim e intermediários determinísticos; dateline sem giro longo |
| MAP-007 | `fitToFeatures` com padding | Todos pontos/área enquadrados sem cortar margem, exceto limitações explícitas |
| MAP-008 | Estilos escuro/claro + paleta editável | Alterar cor da terra/água/contorno sem regenerar scene ID |
| MAP-009 | Preview frame-accurate e reprodução | Frame N do preview corresponde ao render N, tolerância visual definida |
| MAP-010 | Salvar, reabrir e versionar `.namap.json` | Round-trip sem perda; recurso ausente reportado, sem crash |
| MAP-011 | Gerar composição Fusion com nodes organizados | MediaOut ligado, nomes estáveis, camadas editáveis conforme matriz |
| MAP-012 | Inserir no projeto/timeline e reabrir | Composição legível no Resolve Studio e visível na timeline |
| MAP-013 | Atualização idempotente | Duas atualizações iguais não duplicam nodes/clipes/assets |
| MAP-014 | Exportar para uso no Resolve com alfa | Render local 4K de mapa/camadas, alfa correto, assets relativos |
| MAP-015 | Undo/redo no editor e cancelamento | Ações reverterem estado; cancelamento não deixa cena corrompida |
| MAP-016 | Diagnóstico e erros compreensíveis | Sem Studio ou sem timeline: erro acionável; export standalone continua disponível |
| MAP-017 | Preset `Neo Atlas Dark` | Resultado visual repetível, cores configuráveis, assets próprios |
| MAP-018 | Transparência sobre fontes e atribuições | Cada scene registra dataset e licença; créditos quando exigidos |
| MAP-019 | Atualizar sem destruir edições não gerenciadas | Nós de usuário preservados; conflitos sinalizados, sem sobrescrita silenciosa |
| MAP-020 | Projeto offline-first | Cena de países + capitais e export funcionam sem rede |

## P1 — após MVP
P1-001 import GeoJSON/TopoJSON/CSV; P1-002 busca remota opcional com geocoder licenciado; P1-003 coropléticos e escalas; P1-004 temas/presets; P1-005 múltiplas rotas e partículas; P1-006 suporte a fontes vetoriais adicionais; P1-007 editor visual de keyframes avançado; P1-008 batch de cenas.

## P2 — avançado
P2-001 pitch/terreno/globo, P2-002 satélite licenciado, P2-003 edifícios e extrusão, P2-004 malhas geográficas complexas, P2-005 renderização distribuída ou tempo real, P2-006 edição realmente bidirecional de rigs Fusion.

## Fora do MVP
Não é editor GIS profissional; não substitui o Fusion; não oferece geocodificação ilimitada, tracking, clima em tempo real, rotas de veículos calculadas por estradas, fronteiras legalmente oficiais, globo/terreno 3D, export universal de todos os layers como formas editáveis, painel nativamente encaixado no Inspector ou alternativa ao GEOlayers por engenharia reversa de binários.

## Cenários de aceitação obrigatórios
**S1 — América do Sul:** criar cena 4K, 24fps, 240 frames; mapa escuro; BRA e VEN destacados; marcadores Caracas (-66.9036, 10.4806) e Brasília (-47.8825, -15.7942) [coordenadas ilustrativas, não geocodificação oficial]; rota entre pontos, revelação do frame 48 ao 144; câmera de visão continental a enquadramento Brasil; visualizar corretamente os frames 0, 48, 96, 144, 239.

**S2 — Persistência:** salvar, fechar, reabrir, aplicar edição de cor, atualizar; sceneId e featureIds idênticos; sem perda de georreferência.

**S3 — Falhas:** Resolve fechado, Studio não disponível, Fusion não carregado, caminho Unicode, falta de disco, API ausente, asset faltando, geometria inválida: erro tratado; rollback e projeto preservado.

**S4 — Edição de usuário:** adicionar node fora do namespace do plugin e atualizar: node preservado; edição conflitante num node gerenciado: avisar e oferecer 'substituir gerenciados' ou 'cancelar'.

**S5 — Sem internet:** desligar acesso à rede, criar e renderizar uma cena do dataset embutido com resultado reproduzível.

## Requisitos não funcionais e metas de desempenho
- Inicialização da UI <= 5 s em máquina-alvo para percentil 95 após aquecimento (meta, medir).
- Busca offline <= 100 ms p95 com catálogo de escala MVP.
- Preview 960×540 estático <= 250 ms p95 para cena de referência, após dados carregados (meta, hardware real).
- Operação de salvar/abrir 10 MB sem congelar UI por mais de 200 ms (uso de workers).
- Render 4K deve ser correto e reportar tempo real; não prometer tempo sem medição na máquina-alvo.
- Tolerância de âncora: <= 1 px no preview, <= 2 px em 4K; diferença de reprojeção <= 1e-7 no centro das coordenadas em casos não polares.
- Logs estruturados locais com token/identificador pessoal removido; erros recuperáveis não interrompem edição.

## Política de edição no Fusion
| Elemento | Editável no MVP dentro do Fusion | Fonte de verdade |
|---|---|---|
| Fundo/tile/mapa-base | Recolorir/transformar visualmente, não alterar geometria interna | Cena/camadas geradas |
| País/região | Liga/desliga, cor e opacidade por camada; vértices editáveis só se backend nativo validar | GeoJSON |
| Rota | Cor, espessura, opacidade; pontos/percursos alterados no editor | Scene |
| Marcador | Cor, tamanho e posição visual, via controles expostos quando suportado | Coordenadas na cena |
| Texto | Conteúdo e estilo, caso emitido como Text+ Fusion | Scene; alterações manuais detectadas |
| Câmera | Keyframes preferencialmente editados no plugin; Fusion rig direto somente quando a ancoragem síncrona for comprovada na instalação | Scene |

Nunca alegar '100% editável' quando rasterizações estão envolvidas.