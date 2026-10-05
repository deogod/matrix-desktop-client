part of 'timeline_bloc.dart';

sealed class TimelineEvent {}

final class TimelineStartEvent extends TimelineEvent {}

final class TimelineLoadOlderEvent extends TimelineEvent {}

final class TimelineSendEvent extends TimelineEvent {
  TimelineSendEvent(this.text);

  final String text;
}
