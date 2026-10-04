# Decisões

## matrix-sdk 0.19.1 com features explícitas

Contexto: o cliente precisa de TLS, store persistente e suporte a salas criptografadas nas três plataformas desktop.

Decisão: `matrix-sdk = "=0.19.1"` com `default-features = false` e as features `e2e-encryption`, `automatic-room-key-forwarding`, `bundled-sqlite` e `rustls-aws-lc-rs`. Nessa versão o reqwest usa sempre rustls; a feature só escolhe o provider de criptografia. O SQLite vai embutido porque o Windows não tem `libsqlite3` e no Linux exigiria o pacote de desenvolvimento. Quando o `matrix-sdk-ui` entrar, será fixado na mesma versão.

Alternativas: manter as features default (equivalente hoje, mas implícito e sem SQLite embutido); usar o SQLite do sistema.

## Fachada fina em rust/src/api

Contexto: o flutter_rust_bridge expõe ao Dart tudo que é público em `crate::api`.

Decisão: `api/` contém só o `MatrixClientHandle` opaco (estado da sessão e ciclo de vida do store), os DTOs e o enum de erro. A lógica que usa o SDK fica em `rust/src/matrix/` (`auth`, `homeserver`, `errors`, `store`), fora da ponte e testável com `cargo test`.

Alternativas: implementar tudo dentro dos métodos do handle, misturando estado, regras e chamadas ao SDK.

## Resolução do homeserver

Contexto: usuários costumam digitar o nome do servidor (`matrix.org`), que nem sempre é o endereço da API (`https://matrix-client.matrix.org`).

Decisão: a entrada é classificada antes de qualquer requisição.
- Com esquema (`https://...`), é um endereço e vai direto para `ClientBuilder::homeserver_url`.
- Sem esquema e válida como nome de servidor (`matrix.org`, `example.org:8448`), passa por `server_name_or_homeserver_url`: o SDK consulta o `.well-known` e, se não houver, testa `https://<nome>` com `/versions`.
- Qualquer outra entrada sem esquema (por exemplo com caminho) recebe `https://`.

Depois do build, o endereço resolvido passa pela mesma validação, porque um `.well-known` pode apontar para `http`. O cliente é criado com `respect_login_well_known(false)` para que a resposta do login não troque o homeserver depois da validação.

Alternativas: aceitar só URL completa (pior para o usuário); prefixar `https://` em tudo (quebra servidores com delegação, como matrix.org).

## Apenas https, com exceção local controlada pelo Dart

Contexto: em desenvolvimento é comum um Synapse local sem TLS.

Decisão: só `https` é aceito. `http` é aceito apenas para `localhost`, `127.0.0.1` e `[::1]`, e só quando o handle é criado com `allowInsecureLocalhost: true`. O Dart decide (por exemplo com `kDebugMode`); o perfil de build do Rust não interfere. Credenciais embutidas na URL são rejeitadas.

Alternativas: usar `cfg!(debug_assertions)` no Rust, o que acopla a regra ao perfil do cargokit e dificulta testar os dois casos.

## Store do SDK num subdiretório fixo

Contexto: o store SQLite é criptografado com uma passphrase gerada no login. Uma passphrase nova não abre um store antigo.

Decisão: o Dart informa o diretório de dados e o Rust usa sempre `<data_dir>/store`. Esse subdiretório é recriado a cada login, apagado quando o login falha, no logout e quando a sessão expira. Apagar só esse subdiretório garante que um caminho errado vindo do Dart nunca leve a apagar outros arquivos. Na restauração, se o store não existir, o retorno é `Storage`: abrir um crypto store vazio criaria chaves novas para um dispositivo que o servidor já conhece.

Alternativas: o Dart apagar o diretório; reaproveitar o store entre logins.

## MatrixError sem campos

Contexto: no flutter_rust_bridge, enums com campos geram classes `@freezed`, o que exigiria freezed e build_runner.

Decisão: `MatrixError` tem só variantes simples e vira um `enum` Dart. O detalhe de cada erro é registrado com `tracing` no Rust.

Mapeamento:
- `M_FORBIDDEN` ou `M_USER_DEACTIVATED` no login: `InvalidCredentials`.
- 401 ou `M_UNKNOWN_TOKEN`: `SessionExpired`.
- Falha de conexão ou timeout: `Network`.
- No login, um 5xx sem corpo Matrix (proxy na frente de servidor fora do ar): `Network`.
- URL inválida, falha de descoberta ou resposta sem corpo Matrix (site comum, 404): `InvalidHomeserver`.
- Erros de abertura do store, IO e stores de estado ou criptografia: `Storage`.
- O resto: `Unknown`.

Alternativas: enum com mensagem (exigiria freezed); repassar a mensagem do servidor ao Dart.

## Retry das requisições

Contexto: por padrão o SDK repete requisições com falha transitória por até 15 minutos, o que travaria login e abertura do app sem rede.

Decisão: o cliente usa `RequestConfig::short_retry()` (3 tentativas, timeout de 30 s). A verificação da sessão restaurada usa uma requisição sem retry e com timeout de 10 s.

Alternativas: manter o padrão do SDK; configurar requisição por requisição.

## Restauração de sessão

Contexto: `restore_session` do SDK não fala com o servidor, e o app precisa abrir offline.

Decisão: depois de restaurar, o handle chama `whoami`. Só 401 ou `M_UNKNOWN_TOKEN` encerram a sessão (store apagado, retorno `SessionExpired`). Erro de rede ou qualquer outra falha mantém a sessão restaurada e é registrado em log.

Alternativas: não validar (o token expirado só apareceria no sync); exigir rede para abrir o app.

## Logout

Contexto: o logout precisa encerrar a sessão no servidor e apagar os dados locais, mas o servidor pode estar inacessível.

Decisão: o logout no servidor é tentado. Se o token já for inválido, conta como sucesso. Outras falhas são registradas e não impedem a limpeza local. O `Client` é liberado antes de apagar o store. O retorno só é erro (`Storage`) se não for possível apagar o store.

Alternativas: falhar e manter a sessão quando o servidor não responde, deixando o usuário preso logado.

## Logs

Contexto: o `setup_default_user_utils` do flutter_rust_bridge registra no macOS um logger do crate `log` em nível trace.

Decisão: `init_app` chama só `setup_backtrace` e registra um subscriber `tracing` com filtro `warn,rust_lib_matrix_client=info`, ajustável por `RUST_LOG`. Access token, senha e passphrase nunca são logados, e o `Debug` de `SessionDto` omite o token.

Alternativas: manter o logger padrão do flutter_rust_bridge.
