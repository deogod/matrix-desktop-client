# Matrix Desktop Client

Cliente de mensagem desktop para o protocolo Matrix, feito em Flutter. A comunicação com o homeserver fica num núcleo em Rust que usa o `matrix-sdk` e o `matrix-sdk-ui` 0.19.1, exposto ao Dart pelo `flutter_rust_bridge` 2.13.

## O que funciona

- Login com servidor, usuário e senha. O servidor pode ser um nome (`matrix.org`, resolvido pelo `.well-known`) ou um endereço `https://`.
- Restauração da sessão ao abrir o app e logout. Se o servidor não puder ser avisado no logout, os dados locais são apagados mesmo assim e o app avisa.
- Lista de salas ordenada por atividade recente, com nome, inicial do nome, prévia da última mensagem, horário e contagem de não lidas.
- Indicador de conexão: conectado, sincronizando ou offline.
- Conversa da sala selecionada em tempo real, com envio de texto (Enter envia, Shift+Enter quebra linha), carregamento de mensagens antigas ao rolar até o topo e indicação de envio e de falha.
- Em salas cifradas, mensagens que não puderam ser descriptografadas aparecem com o motivo informado pelo SDK.

O servidor precisa oferecer Sliding Sync simplificado (MSC4186), como o matrix.org. Servidores sem esse suporte são recusados no login.

Testado manualmente no macOS contra o matrix.org: login, lista de salas com atualização em tempo real e indicador de conexão, inclusive com queda e volta do Wi-Fi. Build e execução só foram verificados no macOS.

## Como rodar

Requisitos:

- Flutter 3.41 (Dart 3.11).
- Rust 1.96 ou mais recente, exigência do `matrix-sdk-ui` 0.19.1. O desenvolvimento usou o 1.99.
- `flutter_rust_bridge_codegen` 2.13.0, só para regenerar os bindings depois de alterar `rust/src/api/`: `cargo install flutter_rust_bridge_codegen --version 2.13.0`, depois `flutter_rust_bridge_codegen generate`.
- No Linux, o `flutter_secure_storage` precisa do libsecret e de um serviço de keyring ativo (não verificado).

```bash
flutter pub get
flutter run -d macos    # ou windows / linux
```

O código Rust é compilado pelo próprio build do Flutter (cargokit). A primeira compilação leva alguns minutos.

Em modo debug, o login aceita `http://` para `localhost`, `127.0.0.1` e `[::1]`, para uso com um Synapse local. Fora do debug, só `https://`.

Os logs do Rust usam `tracing` e são filtrados por `RUST_LOG`. Para que a variável chegue ao app, rode o binário diretamente:

```bash
flutter build macos --debug
RUST_LOG="warn,rust_lib_matrix_client=debug" \
  ./build/macos/Build/Products/Debug/matrix_client.app/Contents/MacOS/matrix_client
```

## Testes

```bash
flutter analyze && flutter test
cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

- `flutter test`: blocs com fakes dos repositories; repositories com fakes do handle Rust e do armazenamento seguro; formulário de login; campo de envio; formatação da prévia e do horário.
- `cargo test`: validação do homeserver, mapeamento de erros, conversão para os DTOs, estado da conexão, ciclo de vida do store e das tasks. Em `rust/tests/handle_flow.rs`, login, restauração e logout contra um homeserver simulado com `wiremock`, incluindo servidor fora do ar e token rejeitado.
- `rust/tests/auth_flow.rs` roda contra um servidor real e fica ignorado por padrão. As credenciais vêm só do ambiente:

  ```bash
  cd rust
  MATRIX_TEST_HOMESERVER=... MATRIX_TEST_USER=... MATRIX_TEST_PASSWORD=... \
    cargo test --test auth_flow -- --ignored
  ```

- `integration_test/secure_storage_test.dart` verifica o armazenamento seguro da plataforma com as opções do app: `flutter test integration_test -d macos`.

## Arquitetura

```
Rust (lib/src/rust) → Repository → Bloc → StableData → Tela
```

- `rust/src/api/`: fachada exposta ao Dart. O `MatrixClientHandle` guarda a sessão e o sync; o `TimelineHandle` representa a conversa aberta num painel e encerra sua task quando é descartado. Tipos do `matrix-sdk` não atravessam a ponte, só DTOs e o enum `MatrixError`.
- `rust/src/matrix/`: login, restauração, sync, lista de salas, timeline, validação do homeserver, store e mapeamento de erros, fora da ponte e testados com `cargo test`.
- `lib/features/`: `auth` (splash, login e sessão salva), `rooms` (tela principal e lista de salas) e `timeline` (painel da conversa). Os repositories são o único ponto que fala com o Rust; os blocs só conhecem os repositories.
- `lib/core/architecture/`: base própria de estado, navegação, injeção de dependências e HUD, sem pacotes externos para isso.

A tela principal tem dois painéis: lista de salas à esquerda e conversa à direita. O painel da conversa é recriado pela `ValueKey` da sala ao trocar de sala.

## Segurança

- Access token e passphrase do store ficam só no armazenamento seguro do sistema. No macOS é usado o keychain tradicional, porque o keychain de proteção de dados exige assinatura com um Team de desenvolvimento.
- O store SQLite do SDK fica no diretório de suporte do app, criptografado com uma passphrase aleatória gerada a cada login. Cada login usa um store novo, e uma tentativa com senha errada não apaga a sessão salva.
- Só `https://` é aceito, inclusive no endereço descoberto pelo `.well-known`.
- O logout encerra a sessão no servidor e apaga o store e o armazenamento seguro. Um token rejeitado pelo servidor leva de volta ao login.
- Os logs nunca incluem token, senha ou passphrase.

## Decisões e limitações

As decisões, com contexto e alternativas, estão em `docs/DECISIONS.md`. As limitações estão em `docs/LIMITATIONS.md`. As principais:

- Exige servidor com Sliding Sync simplificado (MSC4186).
- Verificação de dispositivo, cross-signing e backup de chaves estão fora do escopo. Por isso mensagens anteriores ao login não podem ser lidas, e clientes que excluem dispositivos não verificados não compartilham chaves com este.
- Sem mídia, edição, reações, threads, separador de dia, reenvio manual de mensagens e marcação como lida.
- A queda de rede leva de 1 a 3 minutos para aparecer no indicador, por causa do timeout e das tentativas do SDK.
- Verificado só no macOS.
