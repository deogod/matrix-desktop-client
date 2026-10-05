# Limitações

## Fora do escopo

Verificação de dispositivo e cross-signing, mídia, edição, reações, threads e criação de conta.

## Autenticação

- Login só com usuário e senha. SSO e OAuth 2.0 não são suportados.
- Refresh token não é solicitado. Servidores que emitem tokens com expiração vão levar a `SessionExpired` e a um novo login.
- Soft logout (`M_UNKNOWN_TOKEN` com `soft_logout: true`) é tratado como sessão expirada: o store é apagado e as chaves do dispositivo se perdem, em vez de reautenticar no mesmo dispositivo.
- Logout feito sem conexão limpa os dados locais, mas o token continua válido no servidor até ser revogado por outro cliente. O app avisa o usuário nesse caso.
- Se a restauração falhar por erro de rede ou desconhecido e o usuário fizer um novo login, o dispositivo da sessão anterior não é desconectado no servidor; só o store local dele é apagado.

## Homeserver

- Para um servidor local sem TLS é preciso digitar o esquema (`http://localhost:8008`). Sem esquema, `localhost:8008` é tratado como nome de servidor e resolvido via https.
- Um nome de servidor digitado errado aparece como falha de rede, porque o erro de DNS não se distingue de falta de conexão.

## Armazenamento seguro

- No macOS é usado o keychain tradicional (ver DECISIONS). O acesso ao item fica atrelado à assinatura do app; não foi verificado se, com assinatura ad hoc, uma recompilação do código nativo faz o macOS pedir permissão para ler a sessão salva.
- No Linux o `flutter_secure_storage` depende do libsecret e de um serviço de keyring ativo (GNOME Keyring ou KWallet). Sem ele, a sessão não é salva e o login falha com erro de armazenamento.

## Plataformas

- Build, execução e armazenamento seguro verificados só no macOS até agora.
