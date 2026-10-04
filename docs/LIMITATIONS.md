# Limitações

## Fora do escopo

Verificação de dispositivo e cross-signing, mídia, edição, reações, threads e criação de conta.

## Autenticação

- Login só com usuário e senha. SSO e OAuth 2.0 não são suportados.
- Refresh token não é solicitado. Servidores que emitem tokens com expiração vão levar a `SessionExpired` e a um novo login.
- Soft logout (`M_UNKNOWN_TOKEN` com `soft_logout: true`) é tratado como sessão expirada: o store é apagado e as chaves do dispositivo se perdem, em vez de reautenticar no mesmo dispositivo.
- Logout feito sem conexão limpa os dados locais, mas o token continua válido no servidor até ser revogado por outro cliente.

## Homeserver

- Para um servidor local sem TLS é preciso digitar o esquema (`http://localhost:8008`). Sem esquema, `localhost:8008` é tratado como nome de servidor e resolvido via https.
- Um nome de servidor digitado errado aparece como falha de rede, porque o erro de DNS não se distingue de falta de conexão.

## Plataformas

- Build e execução verificados só no macOS até agora.
