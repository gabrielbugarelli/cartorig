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
