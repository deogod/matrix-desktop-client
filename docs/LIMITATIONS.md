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

## Sync e lista de salas

- Só funcionam servidores com Sliding Sync simplificado (MSC4186), como o matrix.org e versões recentes do Synapse. Os demais são recusados no login.
- A lista mostra as 200 salas mais recentes, sem paginação.
- Avatares são só a inicial do nome; imagens de avatar ficam para quando houver suporte a mídia.
- Convites e espaços não aparecem na lista.
- Se um servidor deixar de oferecer MSC4186 depois do login, a restauração funciona, mas o indicador alterna entre offline e sincronizando.
- A queda de rede leva de 1 a 3 minutos para aparecer no indicador. O SDK fixa, para cada requisição de sliding sync, timeout de 60 s (30 s de long poll mais 30 s de rede) e até 3 tentativas; o estado só muda quando a última tentativa falha. Num teste com o Wi-Fi desligado, a requisição em andamento esperou o timeout e as tentativas seguintes falharam na hora por erro de DNS, e o indicador foi para Offline cerca de 1 minuto depois da queda. Quando as conexões ficam penduradas em vez de falhar (rede presente sem rota, servidor que para de responder), cada tentativa espera os 60 s e o atraso chega a cerca de 3 minutos. A volta da rede é rápida: o modo offline consulta `/versions` a cada poucos segundos. Melhoria possível: entregar ao SDK um cliente HTTP com keepalive de HTTP/2 (pings com timeout curto), que fecha a conexão morta em dezenas de segundos e faz a requisição em andamento falhar logo.
- O fechamento com parada do sync foi verificado só no macOS.

## Conversa

- Fora desta etapa: separador de dia, reenvio manual de mensagens que falharam (as que falham por falta de rede saem sozinhas quando a conexão volta) e marcação como lida.
- Só texto puro: sem formatação HTML ou Markdown, respostas, reações e threads. Edições aparecem com o texto novo, sem indicação de que foram editadas.
- Mídia, figurinhas e localização aparecem como rótulo ("Imagem", "Arquivo").
- Eventos de estado (entradas, saídas, mudanças de nome) não aparecem na conversa.
- Ao chegar mensagem com a conversa rolada para cima, o conteúdo visível sobe a altura da mensagem nova; a lista só acompanha o fim quando já está nele.
- Mensagens anteriores ao login não podem ser lidas: não há backup de chaves nem verificação do dispositivo.
- Clientes que excluem dispositivos não verificados (modo "excluir dispositivos inseguros" do Element, MSC4153) não enviam a chave para este dispositivo; as mensagens deles aparecem como não descriptografáveis, com esse motivo.
- Envio e descriptografia em sala cifrada não foram verificados contra um servidor real no ambiente de desenvolvimento.

## Armazenamento seguro

- No macOS é usado o keychain tradicional (ver DECISIONS). O acesso ao item fica atrelado à assinatura do app; não foi verificado se, com assinatura ad hoc, uma recompilação do código nativo faz o macOS pedir permissão para ler a sessão salva.
- No Linux o `flutter_secure_storage` depende do libsecret e de um serviço de keyring ativo (GNOME Keyring ou KWallet). Sem ele, a sessão não é salva e o login falha com erro de armazenamento.

## Plataformas

- Build, execução e armazenamento seguro verificados só no macOS até agora.
