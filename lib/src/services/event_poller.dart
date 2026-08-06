typedef NativeEventReader = String Function(int timeoutMs);
typedef NativeEventHandler = void Function(String eventJson);

const eventPollInterval = Duration(milliseconds: 50);
const maxEventsPerPoll = 16;

int drainNativeEvents({
  required NativeEventReader readEvent,
  required NativeEventHandler onEvent,
  int maxEvents = maxEventsPerPoll,
}) {
  if (maxEvents <= 0) {
    throw ArgumentError.value(maxEvents, 'maxEvents', 'must be positive');
  }

  var drained = 0;
  while (drained < maxEvents) {
    // The timer already controls how long we wait between polls. Waiting in the
    // native call would block Flutter's UI isolate and stall frame rendering.
    final json = readEvent(0);
    if (json.isEmpty) break;
    onEvent(json);
    drained++;
  }
  return drained;
}
