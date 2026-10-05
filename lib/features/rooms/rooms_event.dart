part of 'rooms_bloc.dart';

sealed class RoomsEvent {}

final class RoomsStartEvent extends RoomsEvent {}

final class RoomsSelectEvent extends RoomsEvent {
  RoomsSelectEvent(this.roomId);

  final String roomId;
}

final class RoomsLogoutEvent extends RoomsEvent {}
