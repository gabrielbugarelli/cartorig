# CartoRig Native — mapa vazio e animação autoral (Edit / Resolve 20)

Este documento descreve **o que existe no código da v0.3-dev**. A disponibilidade efetiva dos novos controles no Inspector e sua operação durante uma edição real ainda precisam ser verificadas no DaVinci Resolve Studio 20.

## O que mudou

Ao inserir `CartoRig Map (Edit)` na timeline, a cena inicia com um mapa-múndi estático, câmera em longitude 0, latitude 0 e zoom 1.3. **Nenhuma câmera, país, marcador ou rota Brasil–Venezuela é carregada ou animada automaticamente.** O antigo exemplo permanece somente em `samples/` no repositório, para testes opcionais; ele **não é distribuído no bundle OpenFX**.

As novas instâncias têm `Use camera animation from imported scene` **desativado** por padrão. Nenhum keyframe é criado pelo plugin. Os parâmetros numéricos do Inspector podem ser animados pelo sistema de keyframes/curvas da página Edit, sujeito ao comportamento do host.

## Fluxo: construir uma animação do zero

1. Na **Edit**, adicione `CartoRig Map (Edit)` à V1. A câmera começa fixa e sem elementos predefinidos.
2. Ajuste **Camera longitude**, **Camera latitude**, **Camera zoom** e **Camera bearing**. Para animar, posicione o playhead, adicione keyframes dos respectivos parâmetros e altere valores em outros quadros. As curvas Bézier são editadas pelo editor nativo da Edit quando o Resolve expuser os parâmetros OpenFX.
3. Em **Territories / highlight**, digite códigos ISO3, por exemplo `BRA`, `VEN`, `FRA`, nos campos de **Country 1** e **Country 2**. Ambos iniciam vazios. **Highlight opacity** aceita keyframes de 0 a 1 para aparecer/desaparecer. Não existe seleção automática de Brasil ou Venezuela.
4. Em **Manual geographic route**, marque **Enable manual route** apenas quando quiser criar uma rota. Ajuste latitudes e longitudes dos pontos de partida e chegada. **Route reveal** começa em 1 (rota inteira visível quando ativada); para desenhá-la progressivamente, coloque um keyframe em 0 no quadro inicial e outro em 1 no quadro final. É possível animar também coordenadas, curvatura e espessura.
5. **Show route endpoints** controla a exibição de marcadores; os campos **Origin label** e **Destination label** aceitam rótulos curtos. Nenhuma marcação é adicionada antes da ativação manual da rota.
6. Em **Map colors (optional override)**, marque **Override imported map colors** para escolher os valores RGB de oceano, territórios e destaque. Desmarcado, o plugin preserva as cores definidas na cena.
7. Para camadas sobre vídeo, `CartoRig Overlay (Edit)` é um **filtro OpenFX**: aplique diretamente a um clipe existente. Ele não é um clipe independente que possa ser inserido em uma faixa vazia.

## Projetos anteriores e cenas importadas

**Substituir o binário não apaga dados salvos no projeto.** Se um clipe antigo contiver um `Embedded scene JSON` ou `Scene .json` apontando para a demonstração, esse conteúdo permanece como uma escolha explícita. Para obter o estado neutro, limpe ambos os campos, desative **Use camera animation from imported scene** e reinicie os parâmetros pertinentes. A opção mais simples para conferir os novos padrões é arrastar um **novo** gerador para uma timeline descartável.

Os campos avançados continuam disponíveis: `Scene .json`, `GeoJSON`, `Embedded scene JSON` e `Embedded GeoJSON`. Se uma cena autoral tiver suas próprias keyframes de câmera, elas só controlam a câmera quando **Use camera animation from imported scene** estiver ativado. O valor `-1` de `Route reveal` continua reservado para usar tempos de rota descritos no JSON importado.

A versão exibida no Inspector é **0.3.0-dev / SHA de origem**. O GitHub Actions publica builds de pull request a partir de commits temporários de merge; a partir desta versão, o parâmetro de origem do compilador deve exibir o commit da branch do PR, não o commit temporário de merge.

## Limites explícitos

- Estes controles oferecem **manipulação nativa por parâmetros numéricos e campos do Inspector**; ainda não há clique direto em países no Viewer, alças de Bézier geográficas nem drag-and-drop de marcadores na imagem.
- Dois países podem ser destacados diretamente no Inspector. Cenas complexas com quantidades variáveis de territórios/rotas continuam possíveis via JSON incorporado; um gerenciador visual de objetos dinâmicos permanece futuro.
- O editor de curvas da Edit controla parâmetros OpenFX publicados; não se deve anunciar suporte completo a todas as curvas sem o teste host-real.
- O efeito `Overlay` aplicado a vídeo, o alfa e o salvamento/reabertura dos novos parâmetros ainda precisam de testes reais no Resolve 20.
- O projeto continua em prévia de desenvolvimento; o catálogo completo de requisitos não foi concluído.

## Testes mínimos de aceite (Resolve Studio 20)

1. Inserir novo Map em uma timeline vazia: quadros 0, 96 e 239 devem ser **idênticos**, sem zoom, países destacados ou rota.
2. Digitar `BRA` em Country 1: somente o país deve ser realçado. Animar Highlight opacity 0→1 e conferir os quadros intermediários.
3. Ativar manual route, modificar origem/destino e animar Route reveal 0→1. Confirmar que os marcadores podem ser ocultados.
4. Animar longitude, latitude e zoom no Inspector, salvar projeto, reabrir, voltar ao mesmo quadro e comparar a imagem.
5. Ativar/desativar override de cores, duplicar o clipe e confirmar que cada instância mantém seus próprios controles.
6. Aplicar Overlay a um clipe real (não à prévia de hover), verificar visualização, alfa e opacidade.
7. Verificar `Installed plugin build` e confrontar os 12 caracteres com o commit mostrado no PR de origem.

**Gate de CI:** `cartorig_edit_first_neutral_and_manual_controls`, `cartorig_ofx_simulated_host`, checksum idêntico de previews 0/96/239 e build/sanitizadores aprovados. **Gate humano:** os testes acima com evidências da interface real.
