## Segundo teste real — 06/11/2026 02:37 (Edit / Resolve 20)

O usuário forneceu `ofx-diagnostics(1).log` e `DaVinci Resolve_2026.11.06-02.37.mp4`. O arquivo de log contém linhas acumuladas de uma sessão anterior; as entradas do teste novo começam aproximadamente na linha 301. **Não confundir os erros antigos `only RGBA is supported` com o estado atual.**

Evidência da sessão mais recente:

- `1920×1080`, `OfxBitDepthFloat`, `OfxImageComponentRGBA`, `rowBytes=30720`, `renderWindow=0,0,1920,1080`.
- `premult=OfxImageAlphaPremultiplied` — requer testes posteriores de transparência/composição.
- Sem `ERROR` da sessão nova no recorte capturado; o RenderWindow é solicitado normalmente.
- O vídeo mostra `RGB bars` corretas e estáveis, mas `Normal map` com faixas horizontais na superfície cartográfica.
- Os valores `time=0,1,2,...` aparecem mesmo com timecode de timeline 01:00:xx; **não foi demonstrado bug de offset temporal**.

### Causa cartográfica comprovada em reprodução isolada

A implementação anterior usava `project()` para cada ponto de um polígono independentemente. `project()` escolhe a cópia do mundo mais próxima da câmera para cada vértice; ao cruzar o meridiano oposto ao centro (-62° ⇒ seam ~118°E), dois pontos geograficamente próximos passavam a coordenadas de tela distantes em um mundo inteiro. Exemplos reais do GeoJSON incluem `CHN`, `IDN`, `MYS`, `AUS` e `ANT`.

A triangulação 2D por scanlines interpretava estas ligações falsas como arestas longas, desenhando blocos horizontais sobre o oceano Atlântico e a América do Sul.

Em `242e49d8`, o CartoRig projeta anéis geográficos por longitudes contínuas, preservando anéis interiores (buracos), gerenciando cópias do mundo como conjuntos completos e eliminando cópias fora do RenderWindow.

**Validação A/B independente:** o `previews/f000.ppm` do CI anterior reproduzia as faixas exatamente no oceano; o mesmo quadro, mesma câmera e mesmo GeoJSON no novo CI não apresenta as faixas. A correção foi compilada e testada com sanitizadores. Há ainda um teste usando a cena real e amostras precisas de pixels de oceano que teriam falhado no renderizador anterior.

### GATE: não fechar sem teste real

Substituir completamente o bundle OFX no Windows, reiniciar Resolve e reproduzir o trecho 0–90 com `Normal map`. Esperado: oceano uniforme e sem listras em todos os enquadramentos. Depois testar `RGB bars`, `Alpha split` sobre outra faixa e `Overlay` sobre clipe de vídeo real.

**Riscos não resolvidos por esta mudança:** alfa premultiplicado para fundos transparentes, semântica do filtro Overlay, interpolação e zoom, desempenho 4K ao fazer seek, projetos salvos/reabertos e cache de render do Resolve. O teste em C++ não certifica a experiência dentro da Edit.

## Resultado conclusivo do log de 06/11 — ComponentNone no Generator

O usuário enviou `ofx-diagnostics.log` (300 linhas). Entre os eventos brutos registrados, 36 mensagens `IMAGE_RAW` confirmam:

```text
boundsStatus=0 strideStatus=0 depthStatus=0 componentsStatus=0
rect=0,0,1920,1080
rowBytes=30720
depth=OfxBitDepthFloat
components=OfxImageComponentNone
```

Após cada obtenção de imagem, o plugin terminava a ação `OfxImageEffectActionRender` com `only RGBA is supported`. Portanto **nenhum quadro RGB foi renderizado com sucesso**. Os contornos/artefatos vistos no Viewer eram produzidos durante uma ação que falhava, não evidência de cores geográficas intencionalmente erradas.

Segundo o padrão OpenFX, `OfxImageComponentNone` significa imagem sem componentes definidos e não deveria rotular um buffer de imagem válido. Entretanto, o stride de 30.720 bytes corresponde exatamente a `1920 × 4 canais × sizeof(float)`.

**Correção experimental em `e527d904`:**
1. Solicitar `OfxImageClipPropComponents_Output = OfxImageComponentRGBA` no `GetClipPreferences` do Generator.
2. Se o Resolve 20 continuar retornando `ComponentNone`, permitir uma exceção **somente** para a saída do Generator, com `Float`, pitch positivo **exatamente** `width×16`, dimensões válidas e sem componentes alternativos.
3. A decisão é isolada em `classifyOfxLayout` com 16 casos automatizados (aceite e rejeição). Não se aplica ao Overlay/Filter nem à saída Byte sem metadados.
4. Emitir `COMPAT` no log para indicar quando a exceção foi utilizada.

O contrato de metadados continua inconforme à especificação no cenário de fallback. Esta compatibilidade não deve ser generalizada nem marcada como certificada até observar o resultado no host.

**Revalidação prioritária com Artifact novo:** modo `RGB bars` e log ativado. O esperado é eliminar `only RGBA is supported` e produzir as barras inteiras. Depois repetir com `Normal map`, `Grayscale ramp` e `Alpha split`. Se a imagem ainda falhar, analisar as linhas `GetClipPreferences`, `COMPAT`, `render` e qualquer novo `ERROR` do log.

Referências: https://openfx.readthedocs.io/en/main/Reference/ofxClipPreferences.html e https://openfx.readthedocs.io/en/main/Reference/api/file/ofxImageEffect_8h.html.

# CartoRig Native — diagnóstico de buffers na página Edit (Resolve Studio 20)

## Sintoma documentado (6/11/2026)

Após as correções de RenderWindow, preMult e escrita opaca (commits anteriores), a gravação "DaVinci Resolve_2026.11.06-01.31.mp4" ainda mostra, com o CartoRig Map sozinho na V1, ruído verde/branco e linhas horizontais. Em determinados quadros ao tentar arrastar o Overlay, é possível distinguir os contornos do mapa e uma rota; portanto, a descoberta do efeito e a avaliação de alguma geometria funcionam, mas a imagem exibida não corresponde aos valores RGB da cena.

**Não está provado** que o driver da GPU, OpenFX Float, alpha, frame range, pixel packing ou color management seja a causa. O padrão de ruído exige um experimento que ignore totalmente o renderizador de mapas.

## O que foi acrescentado

O Inspector do CartoRig Map e Overlay possui dois controles novos:

- **Diagnostic output (test only)**, com modos:
  - `Normal map`: renderização existente
  - `RGB bars`: quatro barras opacas, vermelho puro, verde puro, azul puro e branco, independentemente do GeoJSON
  - `Grayscale ramp`: escala de cinza 0–1
  - `Alpha split`: metade transparente, um quarto vermelho a 50% de alfa e um quarto branco opaco
  - `Solid white`: branco totalmente opaco em toda a composição
- **Write OFX diagnostic log**: desligado por padrão, grava até 250 eventos por processo no arquivo `%TEMP%\CartoRigNative\ofx-diagnostics.log`. Registra somente dados técnicos: tempo do host, frame range (quando disponível), dimensões, escala, bounds, RenderWindow, row pitch, depth, componentes RGBA e estado de premultiplicação. Não registra caminhos para arquivos de projeto, conteúdo dos vídeos, nomes de usuário ou identificadores pessoais.

O render diagnóstico ignora a rasterização geográfica, mistura de polígonos e renderização de textos. Os padrões RGBA8/RGBA Float são verificados por testes automáticos; o teste com o Resolve real permanece indispensável.

## Sequência de reprodução — um projeto descartável

1. Fechar Resolve e instalar o Artifact Windows **do mesmo commit que introduz os controles diagnósticos**. Verificar no Inspector se aparecem `Diagnostic output (test only)` e `Write OFX diagnostic log`. Se não aparecerem, a instalação ainda é antiga; não interpretar o resultado.
2. Criar projeto descartável com uma timeline 1920×1080, 24 ou 30 fps. **Somente** `CartoRig Map (Edit)` na V1, sem Overlay, sem outros clipes, sem grading. Viewer em Fit.
3. Habilitar `Write OFX diagnostic log` e selecionar `RGB bars`. Esperado: quatro áreas verticais nítidas e estáticas, na ordem vermelho, verde, azul, branco, sem ruído, independente do tempo.
4. Selecionar `Solid white`. Esperado: quadro branco completamente uniforme.
5. Selecionar `Grayscale ramp`. Esperado: gradiente horizontal uniforme preto → branco, sem linhas ou blocos.
6. Selecionar `Alpha split` com um gerador Solid Color na V1 e CartoRig Map na V2. Esperado: cor de fundo visível somente na metade transparente, vermelho semitransparente no quadrante seguinte e branco opaco no final. Não usar o Overlay durante este teste.
7. Voltar para `Normal map` e gravar um trecho. Nos quadros 0 e 120, conferir câmera (quando os controles do SceneCamera estiverem ativos). Se as barras forem corretas e o mapa continuar corrompido, a falha está no caminho próprio do motor de mapas ou no tempo/caching, não na conversão básica dos buffers.
8. Fechar o Resolve e anexar o log `%TEMP%\CartoRigNative\ofx-diagnostics.log` juntamente com uma captura do modo RGB bars e de Normal map. O log não contém caminhos pessoais por projeto, mas deve ser revisado antes de compartilhar.

## Resultado da gravação de 01:58 (2026-11-06)

O usuário ativou `RGB bars` e `Write OFX diagnostic log` no Inspector. No vídeo de 29,2 segundos, as barras não aparecem como quatro faixas coloridas: há linhas verticais, pixels brancos e padrões verdes ruidosos. Isso confirma que a falha independe da leitura de GeoJSON e da avaliação da câmera **durante a tentativa de renderizar os padrões**. Também foi confirmado que o arquivo `%TEMP%\\CartoRigNative\\ofx-diagnostics.log` não foi encontrado.

### Revisão do pipeline de diagnóstico

O logger anterior só era acionado depois de `clipGetImage` e `surfaceOf`; qualquer erro nessas chamadas terminava o render sem log. O novo logger:

1. Registra a alteração de `Write OFX diagnostic log` diretamente pelo callback `kOfxActionInstanceChanged`, antes mesmo de uma renderização bem-sucedida.
2. Registra `RENDER_BEGIN` antes da consulta à imagem de saída.
3. Registra os status brutos de `kOfxImagePropBounds`, `kOfxImagePropRowBytes`, `kOfxImageEffectPropPixelDepth` e `kOfxImageEffectPropComponents` **antes** de validar o buffer.
4. Registra exceções ocorridas em qualquer callback OpenFX, sem conteúdo dos arquivos de projeto.
5. Tenta primeiro `%LOCALAPPDATA%\\CartoRigNative\\ofx-diagnostics.log`, depois `%TEMP%\\CartoRigNative\\ofx-diagnostics.log`. Caso ambos falhem, emite mensagem `OutputDebugStringA` para ferramentas de depuração Windows.

**Novo procedimento:** após instalar o artifact do commit com esta alteração, abra projeto descartável, ative `Write OFX diagnostic log` desligando e ligando a opção uma vez, selecione `RGB bars`, mova o playhead por dois quadros e feche o Resolve. Verifique os **dois** caminhos acima. Se nenhum existir, registre como falha independente de logging; não deduza automaticamente que o render foi bem-sucedido.

## Árvore de decisão

| Observação | Próxima investigação |
|---|---|
| RGB bars também exibem verde/ruído | OpenFX output depth/stride/component packing/host color management — comparar log e modos RGB8/Float |
| RGB bars corretas, Normal map corrompido | Rasterizador geográfico, blend, regionOfDefinition, tempo, caches |
| RGB bars corretas, Alpha split incorreto | Premultiplication/alpha compositing e clip preferences do gerador |
| Solid white correto mas RGB bars incorretas | Interpretação de canais, byte/float packing e edição de cor |
| Câmera acompanha o último keyframe desde o primeiro segundo | Investigar diferença entre `kOfxPropTime` e começo do trecho (`kOfxImageEffectPropFrameRange`) |
| Nenhuma opção diagnóstica aparece no Inspector | Artifact antigo, bundle antigo em outro diretório ou cache de plugin |

**Critério de aceite:** nenhuma correção de RGB, Float ou tempo será anunciada como solução definitiva sem evidência do teste no Resolve 20, tanto nas barras quanto no mapa.

## Limitação explicitamente mantida

A rasterização geográfica ainda não tem correção definitiva para o ruído observado no Resolve 20. O modo de diagnóstico foi introduzido para isolar a causa, e não para substituir a renderização nem para mascarar a falha.
