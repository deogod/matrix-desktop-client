# Decisões

## matrix-sdk 0.19.1 com features explícitas

Contexto: o cliente precisa de TLS, store persistente e suporte a salas criptografadas nas três plataformas desktop.

Decisão: `matrix-sdk = "=0.19.1"` com `default-features = false` e as features `e2e-encryption`, `automatic-room-key-forwarding`, `bundled-sqlite` e `rustls-aws-lc-rs`. Nessa versão o reqwest usa sempre rustls; a feature só escolhe o provider de criptografia. O SQLite vai embutido porque o Windows não tem `libsqlite3` e no Linux exigiria o pacote de desenvolvimento. Quando o `matrix-sdk-ui` entrar, será fixado na mesma versão.

Alternativas: manter as features default (equivalente hoje, mas implícito e sem SQLite embutido); usar o SQLite do sistema.

## Fachada fina em rust/src/api

Contexto: o flutter_rust_bridge expõe ao Dart tudo que é público em `crate::api`.

Decisão: `api/` contém só o `MatrixClientHandle` opaco (estado da sessão e ciclo de vida do store), os DTOs e o enum de erro. A lógica que usa o SDK fica em `rust/src/matrix/` (`auth`, `homeserver`, `errors`, `store`), fora da ponte e testável com `cargo test`.

Alternativas: implementar tudo dentro dos métodos do handle, misturando estado, regras e chamadas ao SDK.

## Dart em três camadas

Contexto: usecases e datasources separados seriam só repasse entre o bloc e o handle Rust.

Decisão: `Rust → Repository → Bloc → StableData → Tela`. O repository é a fronteira com o Rust: chama o `MatrixClientHandle`, converte DTO em entity com funções privadas no próprio arquivo e devolve `Result<T>` via `guard`. `lib/src/rust/` só é importado por repositories, `core/failure_mapper.dart`, `core/injector.dart` e `main.dart`. Um único `MatrixClientHandle` é criado no injector, porque a sessão vive nele e as próximas features vão usar a mesma instância.

Alternativas: camadas data/domain/presentation com usecases e datasources, que nesse tamanho só acrescentam arquivos.

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

## Um store por login

Contexto: o store SQLite é criptografado com uma passphrase gerada a cada login, e uma passphrase nova não abre um store antigo. Ao mesmo tempo, uma tentativa de login com senha errada não pode destruir uma sessão salva. O cliente do login não pode ser reaberto em outro diretório depois do sucesso, porque tarefas de E2EE do SDK continuam segurando o store em segundo plano.

Decisão: cada login cria `<data_dir>/stores/<id aleatório>` vazio e usa esse diretório até o fim. Se o login falhar, só esse diretório é apagado. Se der certo, os outros stores são apagados. O id volta no `SessionDto` como `store_id`, é salvo junto com a sessão e é validado na restauração (só letras e números), para que um valor adulterado não aponte para fora de `stores/`. O Rust nunca apaga nada fora de `<data_dir>/stores`. Na restauração, se o store não existir, o retorno é `Storage`: abrir um crypto store vazio criaria chaves novas para um dispositivo que o servidor já conhece. O logout e a sessão expirada apagam o store.

Alternativas: um diretório fixo recriado antes do login (uma senha errada apagava o store da sessão salva); fechar e reabrir o cliente num diretório definitivo depois do login (o SDK mantém o store aberto em tarefas de fundo); usar o device_id enviado pelo cliente como nome do diretório (dependeria de o servidor respeitar o id enviado).

## Sessão e passphrase no secure storage

Contexto: o access token e a passphrase do store não podem ficar em arquivos comuns.

Decisão: homeserver, user id, device id, token, store id e passphrase são gravados juntos, como JSON, numa única chave do `flutter_secure_storage`, para que nunca fiquem dessincronizados. A passphrase são 32 bytes de `Random.secure()`, gerada a cada login, já que o store é sempre novo. A sessão salva só é sobrescrita depois que o login dá certo. Se a gravação falhar, o repository faz logout no handle para não deixar no servidor uma sessão que nunca poderia ser restaurada.

Alternativas: chaves separadas para cada campo; reaproveitar a passphrase entre logins.

## Keychain no macOS

Contexto: por padrão o `flutter_secure_storage` 11 usa no macOS o keychain de proteção de dados, que exige o entitlement `keychain-access-groups`. O projeto é assinado ad hoc, sem Team de desenvolvimento.

Decisão: `MacOsOptions(usesDataProtectionKeychain: false)`, que usa o keychain tradicional, e nenhum `keychain-access-groups` nos entitlements. Verificado com `integration_test/secure_storage_test.dart` no macOS: com o entitlement, o Xcode recusa o build ("requires signing with a development certificate"); sem o entitlement e com o padrão, a gravação falha com -34018 (`errSecMissingEntitlement`); sem o entitlement e com a opção, grava, lê e apaga normalmente.

Alternativas: configurar um Team e provisioning profile, o que impede rodar o projeto em outra máquina sem conta de desenvolvedor.

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

Decisão: a restauração usa o homeserver salvo (o endereço já resolvido no login), sem refazer a descoberta. Depois de restaurar, o handle chama `whoami`. Só 401 ou `M_UNKNOWN_TOKEN` encerram a sessão (store apagado, retorno `SessionExpired`). Erro de rede ou qualquer outra falha mantém a sessão restaurada e é registrado em log. No Dart, sessão expirada, store indisponível, homeserver inválido ou dado salvo corrompido apagam o secure storage; falha de rede ou desconhecida mantém os dados para a próxima abertura.

Alternativas: não validar (o token expirado só apareceria no sync); exigir rede para abrir o app.

## Logout

Contexto: o logout precisa encerrar a sessão no servidor e apagar os dados locais, mas o servidor pode estar inacessível.

Decisão: o logout no servidor é tentado e o resultado volta como `LogoutOutcomeDto`: `Complete` quando o servidor revogou o token (ou ele já era inválido) e `LocalOnly` quando o servidor não respondeu. Nos dois casos o store e o secure storage são apagados e o app volta para o login. Com `LocalOnly`, a tela avisa que a sessão foi encerrada só neste computador e que o acesso pode continuar ativo no servidor. Para esse aviso, a `AppHud` ganhou `showMessage`, uma snackbar neutra, porque não é um erro.

Alternativas: falhar e manter a sessão quando o servidor não responde, deixando o usuário preso logado; encerrar em silêncio, escondendo que o token pode continuar válido.

## Testes do handle com servidor simulado

Contexto: login, restauração e logout dependem de respostas do homeserver, e o teste contra servidor real precisa de credenciais.

Decisão: `rust/tests/handle_flow.rs` usa `wiremock` para simular o homeserver e roda no `cargo test` comum. Cada teste cria o próprio servidor com `MockServer::builder()`, porque o `MockServer::start()` reaproveita servidores de um pool: soltar o servidor não fecha a porta, e os testes de servidor inacessível passariam por engano. `rust/tests/auth_flow.rs` continua como teste ignorado contra um servidor real.

Alternativas: só o teste contra servidor real.

## Logs

Contexto: o `setup_default_user_utils` do flutter_rust_bridge registra no macOS um logger do crate `log` em nível trace.

Decisão: `init_app` chama só `setup_backtrace` e registra um subscriber `tracing` com filtro `warn,rust_lib_matrix_client=info`, ajustável por `RUST_LOG`. Access token, senha e passphrase nunca são logados, e o `Debug` de `SessionDto` omite o token.

Alternativas: manter o logger padrão do flutter_rust_bridge.
