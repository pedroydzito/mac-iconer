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

O Renicon consulta as Releases deste repositório ao abrir e a cada 6 horas. Quando há uma versão nova, ele mostra o número da versão e as novidades e pergunta se você quer **Instalar e Reiniciar**, **Lembrar Depois** ou **Pular Esta Versão**. Também dá para procurar manualmente em **Renicon › Procurar Atualizações…** ou nos Ajustes.

### Publicar uma nova versão (para o mantenedor)

Crie uma tag com o número da versão e envie para o GitHub:

```sh
git tag v1.1.0
git push origin v1.1.0
```

O GitHub Actions compila o app, gera `Renicon.dmg` e `Renicon.zip` e publica a Release. Os apps já instalados recebem o aviso de atualização.

## Como funciona

Para cada app, o Renicon cria um **app atalho** em `~/Applications/Renicon/`:

- é um pacote `.app` leve, com o nome e o ícone que você escolheu;
- ao ser aberto, ele apenas abre o app original pelo *bundle identifier* (ex.: `com.adobe.Photoshop`);
- é registrado no LaunchServices e indexado no Spotlight, então aparece no **Spotlight**, no **Launchpad** e pode ser fixado no **Dock**;
- como o app original nunca é modificado, **atualizações funcionam normalmente** — e mesmo que o app mude de pasta ou nome de arquivo, o atalho continua funcionando.

### Ícone no Dock com o app aberto (opcional)

Quando o app original está aberto, o Dock mostra o ícone *dele*. Ative **"Usar este ícone também no app original"** para aplicar o seu ícone ao app original também (é um ícone personalizado do Finder, o mesmo de "Obter Informações › colar ícone").

Uma atualização substitui o pacote do app e apaga esse ícone, por isso o Renicon fica observando a pasta dos apps (FSEvents): assim que um app é atualizado, ele **reaplica o ícone automaticamente** (e confere também quando apps abrem/fecham e a cada 15 minutos). Se o Dock demorar para mostrar o ícone novo, use **Ajustes › Recarregar Dock**. Para isso, deixe o Renicon aberto (ou na barra de menus) e ative **Abrir ao iniciar sessão** nos Ajustes.

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
| `RenIconApp.swift` | Cenas (janela, Ajustes, barra de menus) e observação de apps abrindo/fechando |
| `ContentView.swift` | Barra lateral, estado vazio, arrastar e soltar |
| `EditorView.swift` | Editor de nome e ícone |
| `SettingsView.swift` | Ajustes |
| `LibraryStore.swift` | Biblioteca, persistência e sincronização após atualizações |
| `ShortcutBuilder.swift` | Gera o app atalho (Info.plist, launcher, .icns, assinatura, Spotlight) |
| `Updater.swift` | Verificação e instalação de novas versões pelo GitHub |
| `FolderWatcher.swift` | Detecta na hora quando um app é atualizado |
| `IconRenderer.swift` | Renderização dos ícones e geração de `.icns` |
