# Renicon

App nativo para macOS (SwiftUI) que deixa você dar **um novo nome e um novo ícone** a qualquer app — sem mexer no app original, para que ele continue recebendo atualizações normalmente.

Exemplo: arraste o **Adobe Photoshop 2026** para o Renicon, escolha uma imagem nova e renomeie para **Photoshop**. Depois disso, ao buscar "Photoshop" no Spotlight, ele aparece com o seu ícone e o seu nome.

## Instalar (sem precisar de código)

1. Abra a página de [**Releases**](https://github.com/pedroydzito/mac-renicon/releases/latest) e baixe o **Renicon.dmg**.
2. Abra o `.dmg` e arraste o **Renicon** para a pasta **Aplicativos**.
3. Na primeira vez, o macOS avisa que não consegue verificar o desenvolvedor (o app não é notarizado pela Apple). Para liberar:
   - abra o Renicon uma vez e clique em **OK**;
   - vá em **Ajustes do Sistema › Privacidade e Segurança**, role até o aviso sobre o Renicon e clique em **Abrir Mesmo Assim**.

Isso só é necessário na primeira instalação. Depois, o próprio Renicon avisa quando houver uma versão nova e se atualiza sozinho.

## Atualizações automáticas

O Renicon consulta as Releases deste repositório sempre que é aberto. Quando há uma versão nova, ele mostra o número da versão e as novidades e pergunta se você quer **Instalar e Reiniciar**, **Lembrar Depois** ou **Pular Esta Versão**. Também dá para procurar manualmente em **Renicon › Procurar Atualizações…** ou nos Ajustes.

### Publicar uma nova versão (para o mantenedor)

No GitHub, vá em **Actions › Build › Run workflow**, digite a versão (ex.: `1.1.0`) e clique em **Run workflow**. Também funciona enviando uma tag (`git tag v1.1.0 && git push origin v1.1.0`).

O GitHub Actions compila o app, gera `Renicon.dmg` e `Renicon.zip` e publica a Release. Os apps já instalados recebem o aviso de atualização.

## Como funciona

Para cada app, o Renicon cria um **app atalho** em `~/Applications/` (a pasta de apps do seu usuário, que o Spotlight e o Launchpad sempre indexam):

- é um pacote `.app` leve, com o nome e o ícone que você escolheu;
- ao ser aberto, ele apenas abre o app original pelo *bundle identifier* (ex.: `com.adobe.Photoshop`);
- é registrado no LaunchServices e indexado no Spotlight, então aparece no **Spotlight**, no **Launchpad** e pode ser fixado no **Dock**;
- como o app original nunca é modificado, **atualizações funcionam normalmente** — e mesmo que o app mude de pasta ou nome de arquivo, o atalho continua funcionando.

### Ícone no Dock com o app aberto (opcional)

Quando o app original está aberto, o Dock mostra o ícone *dele*. Ative **"Usar este ícone também no app original"** para aplicar o seu ícone ao app original também (é um ícone personalizado do Finder, o mesmo de "Obter Informações › colar ícone").

Uma atualização substitui o pacote do app e apaga esse ícone. **O Renicon não precisa estar aberto** para recolocá-lo, e nada fica rodando em segundo plano:

- o próprio atalho confere o ícone do app original antes de abri-lo e o recoloca se precisar;
- uma regra do launchd (`~/Library/LaunchAgents/com.renicon.reapply.plist`) só é acionada pelo macOS quando a pasta do app muda (ou seja, numa atualização), roda um script de ~1 segundo e termina.

Ou seja: abra o Renicon, ajuste, clique em **Aplicar** e feche. Se o Dock demorar para mostrar o ícone novo, use **Ajustes › Recarregar Dock**.

> Para alterar o ícone de apps em `/Applications` o macOS pode pedir permissão: em **Ajustes do Sistema › Privacidade e Segurança**, dê ao Renicon "Gerenciamento de Apps" (ou "Acesso Total ao Disco").

### Nome e ícone no Dock

O app original **nunca é renomeado, movido ou reassinado** — instaladores e atualizadores (como o Creative Cloud) continuam encontrando o app normalmente. No Dock fica fixado o **atalho**, que sempre mostra o seu nome e ícone. Com o app aberto, o macOS mostra ao lado o app em execução com o nome original; ao fechar, fica só o atalho.

### Limitações honestas

- O **nome** exibido no Dock/menu enquanto o app original está rodando continua sendo o original: mudar isso exigiria editar o `Info.plist` do app, o que quebra a assinatura e é desfeito a cada atualização. O nome novo aparece no atalho (Spotlight, Launchpad, Finder, Dock fixado).
- Se você fixar o atalho no Dock, ao abrir o app o Dock mostra o atalho e, ao lado, o app em execução. Ative a opção de ícone no app original para que ambos fiquem com o seu ícone.

## Recursos

- Visual escuro com **Liquid Glass** (macOS 26; nas versões 14/15 usa vidro translúcido)
- Faixa estilo Dock com seus apps na parte de baixo; clique em um para editar e use **‹ Voltar** (ou Esc) para voltar à área de soltar apps
- Editor: clique no ícone para trocar (ou escolha uma das **sugestões da App Store**) → digite o nome. As mudanças são **aplicadas sozinhas**
- Formato automático: imagens com cantos transparentes ficam como estão; imagens quadradas ganham o formato macOS
- Se o app já estava no Dock, ele é trocado pelo ajustado automaticamente
- **⌘Z / ⇧⌘Z** para desfazer e refazer nome, ícone, formato e ajustes
- Ícone: clique, arraste uma imagem (inclusive direto do navegador) ou cole (⋯ › Colar Imagem)
- A imagem é **copiada** para o Renicon: apagar o arquivo original não afeta nada; remover o app do Renicon apaga a cópia
- Botão **Pôr no Dock**: fixa o atalho no Dock, no lugar do app original se ele estiver lá; ao renomear, o item do Dock acompanha
- Detalhes e opções avançadas ficam no botão **ⓘ**
- Zoom e cor de fundo do ícone (botão ⓘ)
- Aviso de nome duplicado, confirmação ao remover, **Remover Todos os Atalhos** nos Ajustes (use antes de desinstalar)
- Estilo **Formato macOS**: recorta qualquer imagem no formato padrão dos ícones do macOS (evita a moldura cinza que o macOS 26 coloca em ícones fora do padrão)
- Prateleira de apps estilo Dock na parte de baixo, ⌘S para aplicar, ⌘O para adicionar
- Biblioteca salva em `~/Library/Application Support/Renicon`

## Compilar a partir do código

Requer macOS 14+ e Xcode 15+ (ou as Command Line Tools).

```sh
./build.sh 1.0.0
mv build/Renicon.app /Applications/
```

Também dá para abrir a pasta no Xcode (`File › Open…` e escolher `Package.swift`) e rodar com ⌘R.

## Estrutura

| Arquivo | Função |
| --- | --- |
| `RenIconApp.swift` | Janela, Ajustes, menus e oferta de mover para Aplicativos |
| `ContentView.swift` | Tela principal, estado vazio, prateleira de apps |
| `EditorView.swift` | Editor de ícone e nome, painel ⓘ |
| `Glass.swift` | Efeitos Liquid Glass (com alternativa para macOS 14/15) |
| `DockManager.swift` | Fixar/atualizar atalhos no Dock |
| `SettingsView.swift` | Ajustes |
| `LibraryStore.swift` | Biblioteca, persistência e sincronização após atualizações |
| `ShortcutBuilder.swift` | Gera o app atalho (Info.plist, launcher, .icns, assinatura, Spotlight) |
| `Updater.swift` | Verificação e instalação de novas versões pelo GitHub |
| `AutoReapply.swift` | Script + regra do launchd que recolocam ícones sem o app aberto |
| `IconRenderer.swift` | Renderização dos ícones e geração de `.icns` |
