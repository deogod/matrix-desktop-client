import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/core/architecture/architecture.dart';
import 'package:matrix_client/core/routes.dart';
import 'package:matrix_client/features/auth/auth_repository.dart';
import 'package:matrix_client/features/rooms/room.dart';
import 'package:matrix_client/features/rooms/rooms_bloc.dart';
import 'package:matrix_client/features/rooms/rooms_repository.dart';

import '../../helpers/fake_app.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_rooms_repository.dart';

const general = Room(id: '!general:matrix.org', name: 'Geral', initial: 'G');
const random = Room(id: '!random:matrix.org', name: 'Aleatório', initial: 'A');

void main() {
  late FakeRoomsRepository rooms;
  late FakeAuthRepository auth;
  late FakeAppNavigator navigator;
  late FakeAppHud hud;
  late RoomsBloc bloc;

  setUp(() {
    final app = registerFakeApp();
    navigator = app.navigator;
    hud = app.hud;
    rooms = FakeRoomsRepository();
    auth = FakeAuthRepository();
    bloc = RoomsBloc(roomsRepository: rooms, authRepository: auth)..onReady();
  });

  tearDown(() async {
    await bloc.close();
    Locator.instance.reset();
  });

  RoomsStableData stableData() {
    final state = bloc.state;
    if (state is! Stable<RoomsStableData>) fail('Esperava Stable, veio $state');
    return state.data;
  }

  Future<void> emitRooms(List<Room> list) async {
    rooms.roomsController.add(list);
    await pumpEventQueue();
  }

  Future<void> emitStatus(SyncStatus status) async {
    rooms.syncStatusController.add(status);
    await pumpEventQueue();
  }

  group('lista de salas', () {
    test('fica em Loading até chegar a primeira lista', () async {
      await emitStatus(SyncStatus.connected);

      expect(bloc.state, isA<Loading<RoomsStableData>>());
    });

    test('publica a primeira lista com o status mais recente', () async {
      await emitStatus(SyncStatus.connected);
      await emitRooms([general, random]);

      expect(stableData().rooms, [general, random]);
      expect(stableData().syncStatus, SyncStatus.connected);
    });

    test('lista vazia também é Stable', () async {
      await emitRooms([]);

      expect(stableData().isEmpty, isTrue);
      expect(stableData().syncStatus, SyncStatus.syncing);
    });

    test('atualiza o indicador de conexão', () async {
      await emitRooms([general]);

      await emitStatus(SyncStatus.offline);
      expect(stableData().syncStatus, SyncStatus.offline);

      await emitStatus(SyncStatus.connected);
      expect(stableData().syncStatus, SyncStatus.connected);
    });

    test('falha no stream de status mostra offline', () async {
      await emitRooms([general]);

      rooms.syncStatusController.addError(const UnknownFailure());
      await pumpEventQueue();

      expect(stableData().syncStatus, SyncStatus.offline);
    });
  });

  group('seleção', () {
    test('destaca a sala selecionada e a mantém quando a lista muda', () async {
      await emitRooms([general, random]);

      bloc.dispatchEvent(RoomsSelectEvent(random.id));
      expect(stableData().selectedRoom, random);

      await emitRooms([random, general]);
      expect(stableData().selectedRoomId, random.id);
    });

    test('limpa a seleção quando a sala some da lista', () async {
      await emitRooms([general, random]);
      bloc.dispatchEvent(RoomsSelectEvent(random.id));

      await emitRooms([general]);

      expect(stableData().selectedRoomId, isNull);
      expect(stableData().selectedRoom, isNull);
    });
  });

  group('falhas', () {
    test('antes da primeira lista viram ErrorState', () async {
      rooms.roomsController.addError(const NetworkFailure());
      await pumpEventQueue();

      expect(
        bloc.state,
        isA<ErrorState<RoomsStableData>>()
            .having((state) => state.failure, 'failure', isA<NetworkFailure>()),
      );
      expect(hud.failures, isEmpty);
    });

    test('depois da primeira lista mantêm as salas e avisam pelo HUD',
        () async {
      await emitRooms([general]);

      rooms.roomsController.addError(const NetworkFailure());
      await pumpEventQueue();

      expect(stableData().rooms, [general]);
      expect(hud.failures, [const NetworkFailure().message]);
    });

    test('sessão expirada limpa os dados locais e volta ao login', () async {
      await emitRooms([general]);

      await emitStatus(SyncStatus.sessionExpired);
      await emitStatus(SyncStatus.sessionExpired);

      expect(auth.logoutCalls, 1);
      expect(hud.failures, [const SessionExpiredFailure().message]);
      expect(navigator.routes, [Routes.login]);
    });
  });

  group('logout', () {
    Future<void> logout() async {
      bloc.dispatchEvent(RoomsLogoutEvent());
      await pumpEventQueue();
    }

    test('pede confirmação e não sai se for cancelado', () async {
      hud.confirmResult = false;

      await logout();

      expect(hud.confirmations, 1);
      expect(auth.logoutCalls, 0);
      expect(navigator.routes, isEmpty);
    });

    test('completo vai para o login sem aviso', () async {
      await logout();

      expect(auth.logoutCalls, 1);
      expect(hud.messages, isEmpty);
      expect(navigator.routes, [Routes.login]);
    });

    test('só local avisa que o servidor não foi avisado', () async {
      auth.logoutResult = const Ok(LogoutOutcome.localOnly);

      await logout();

      expect(hud.messages, [RoomsBloc.localOnlyLogoutMessage]);
      expect(navigator.routes, [Routes.login]);
    });

    test('com falha mostra a falha e vai para o login', () async {
      auth.logoutResult = const Err(StorageFailure());

      await logout();

      expect(hud.failures, [const StorageFailure().message]);
      expect(navigator.routes, [Routes.login]);
    });
  });
}
