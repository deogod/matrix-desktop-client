import '../../core/architecture/architecture.dart';
import '../../core/routes.dart';
import '../auth/auth_repository.dart';
import 'room.dart';
import 'rooms_repository.dart';

part 'rooms_event.dart';

final class RoomsStableData {
  const RoomsStableData({
    this.rooms = const [],
    this.syncStatus = SyncStatus.syncing,
    this.selectedRoomId,
  });

  final List<Room> rooms;
  final SyncStatus syncStatus;
  final String? selectedRoomId;

  bool get isEmpty => rooms.isEmpty;

  Room? get selectedRoom {
    for (final room in rooms) {
      if (room.id == selectedRoomId) return room;
    }
    return null;
  }

  RoomsStableData copyWith({
    List<Room>? rooms,
    SyncStatus? syncStatus,
    String? Function()? selectedRoomId,
  }) {
    return RoomsStableData(
      rooms: rooms ?? this.rooms,
      syncStatus: syncStatus ?? this.syncStatus,
      selectedRoomId:
          selectedRoomId != null ? selectedRoomId() : this.selectedRoomId,
    );
  }
}

final class RoomsBloc extends Bloc<RoomsEvent, RoomsStableData> {
  RoomsBloc({required this.roomsRepository, required this.authRepository});

  static const localOnlyLogoutMessage =
      'Sessão encerrada neste computador, mas não foi possível avisar o '
      'servidor. O acesso pode continuar ativo até ser revogado em outro '
      'dispositivo.';

  final RoomsRepository roomsRepository;
  final AuthRepository authRepository;
  RoomsStableData _data = const RoomsStableData();
  bool _hasReceivedRooms = false;
  bool _isLeaving = false;

  @override
  void onReady() {
    super.onReady();
    dispatchEvent(RoomsStartEvent());
  }

  @override
  void handleEvent(RoomsEvent event) {
    switch (event) {
      case RoomsStartEvent():
        _handleStart();
      case RoomsSelectEvent():
        _handleSelect(event.roomId);
      case RoomsLogoutEvent():
        _handleLogout();
    }
  }

  void _handleStart() {
    addSubscription(
      roomsRepository.watchRooms().listen(_onRooms, onError: _onRoomsError),
    );
    addSubscription(
      roomsRepository.watchSyncStatus().listen(
            _onSyncStatus,
            onError: (Object _) => _onSyncStatus(SyncStatus.offline),
          ),
    );
  }

  void _handleSelect(String roomId) {
    _data = _data.copyWith(selectedRoomId: () => roomId);
    _publish();
  }

  void _onRooms(List<Room> rooms) {
    _hasReceivedRooms = true;
    final selectedRoomId = _data.selectedRoomId;
    final selectionStillExists = rooms.any((room) => room.id == selectedRoomId);
    _data = _data.copyWith(
      rooms: rooms,
      selectedRoomId: () => selectionStillExists ? selectedRoomId : null,
    );
    _publish();
  }

  // Before the first list there is nothing to show, so the failure takes the
  // screen. Afterwards the rooms already on screen are kept and the connection
  // indicator tells the rest.
  void _onRoomsError(Object error) {
    final failure = error is Failure ? error : const UnknownFailure();
    if (_hasReceivedRooms) {
      handleFailure(failure);
    } else {
      dispatchState(ErrorState(failure));
    }
  }

  void _onSyncStatus(SyncStatus status) {
    if (status == SyncStatus.sessionExpired) {
      _handleSessionExpired();
      return;
    }
    _data = _data.copyWith(syncStatus: status);
    _publish();
  }

  void _publish() {
    if (_hasReceivedRooms) dispatchState(Stable(_data));
  }

  Future<void> _handleSessionExpired() async {
    if (_isLeaving) return;
    _isLeaving = true;

    // The token is already invalid, so this only clears the local data.
    await authRepository.logout();
    handleFailure(const SessionExpiredFailure());
    offAllNamed(Routes.login);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showConfirmation(
      title: 'Sair da conta',
      message: 'A sessão será encerrada e os dados desta conta serão apagados '
          'deste computador.',
      confirmText: 'Sair',
    );
    if (!confirmed || _isLeaving) return;

    await doPersist(() async {
      _isLeaving = true;
      final result = await authRepository.logout();
      // Local data is gone even when logout fails, so the user always leaves.
      result.fold(handleFailure, (outcome) {
        if (outcome == LogoutOutcome.localOnly) {
          showMessage(localOnlyLogoutMessage);
        }
      });
      offAllNamed(Routes.login);
    });
  }
}
