# Renicon

App nativo para macOS (SwiftUI) que deixa você dar **um novo nome e um novo ícone** a qualquer app — sem mexer no app original, para que ele continue recebendo atualizações normalmente.

Exemplo: arraste o **Adobe Photoshop 2026** para o Renicon, escolha uma imagem nova e renomeie para **Photoshop**. Depois disso, ao buscar "Photoshop" no Spotlight, ele aparece com o seu ícone e o seu nome.

## Como funciona

Para cada app, o Renicon cria um **app atalho** em `~/Applications/Renicon/`:

- é um pacote `.app` leve, com o nome e o ícone que você escolheu;
- ao ser aberto, ele apenas abre o app original pelo *bundle identifier* (ex.: `com.adobe.Photoshop`);
- é registrado no LaunchServices e indexado no Spotlight, então aparece no **Spotlight**, no **Launchpad** e pode ser fixado no **Dock**;
- como o app original nunca é modificado, **atualizações funcionam normalmente** — e mesmo que o app mude de pasta ou nome de arquivo, o atalho continua funcionando.

### Ícone no Dock com o app aberto (opcional)

Quando o app original está aberto, o Dock mostra o ícone *dele*. Ative **"Usar este ícone também no app original"** para aplicar o seu ícone ao app original também (é um ícone personalizado do Finder, o mesmo de "Obter Informações › colar ícone").

Uma atualização substitui o pacote do app e apaga esse ícone, por isso o Renicon fica observando: quando um app abre/fecha e a cada 15 minutos, ele confere e **reaplica o ícone automaticamente**. Para isso, deixe o Renicon aberto (ou na barra de menus) e ative **Abrir ao iniciar sessão** nos Ajustes.

> Para alterar o ícone de apps em `/Applications` o macOS pode pedir permissão: em **Ajustes do Sistema › Privacidade e Segurança**, dê ao Renicon "Gerenciamento de Apps" (ou "Acesso Total ao Disco").

### Limitações honestas

- O **nome** exibido no Dock/menu enquanto o app original está rodando continua sendo o original: mudar isso exigiria editar o `Info.plist` do app, o que quebra a assinatura e é desfeito a cada atualização. O nome novo aparece no atalho (Spotlight, Launchpad, Finder, Dock fixado).
- Se você fixar o atalho no Dock, ao abrir o app o Dock mostra o atalho e, ao lado, o app em execução. Ative a opção de ícone no app original para que ambos fiquem com o seu ícone.

## Recursos

- Arrastar e soltar apps na janela (ou ⌘O para escolher)
- Arrastar uma imagem (PNG, JPEG, HEIC, ICNS…) ou outro app sobre o ícone
- Estilo **Formato macOS**: recorta qualquer imagem no formato padrão dos ícones do macOS, com margem e sombra
- Pré-visualização antes/depois, busca, menu de contexto, ⌘S para aplicar, "Aplicar Tudo"
- Ajustes: abrir ao iniciar sessão, continuar rodando em segundo plano, ícone na barra de menus
- Biblioteca salva em `~/Library/Application Support/Renicon`

## Compilar

Requer macOS 14+ e Xcode 15+ (ou as Command Line Tools).

```sh
./build.sh
mv build/Renicon.app /Applications/
```

Também dá para abrir a pasta no Xcode (`File › Open…` e escolher `Package.swift`) e rodar com ⌘R.

## Estrutura

| Arquivo | Função |
| --- | --- |
| `RenIconApp.swift` | Cenas (janela, Ajustes, barra de menus) e observação de apps abrindo/fechando |
| `ContentView.swift` | Barra lateral, estado vazio, arrastar e soltar |
| `EditorView.swift` | Editor de nome e ícone |
| `SettingsView.swift` | Ajustes |
| `LibraryStore.swift` | Biblioteca, persistência e sincronização após atualizações |
| `ShortcutBuilder.swift` | Gera o app atalho (Info.plist, launcher, .icns, assinatura, Spotlight) |
| `IconRenderer.swift` | Renderização dos ícones e geração de `.icns` |
