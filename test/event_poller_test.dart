import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/src/services/event_poller.dart';

void main() {
  test('native event polling never waits on the UI isolate', () {
    final timeouts = <int>[];
    final handled = <String>[];
    final pending = <String>['first', 'second'];

    final drained = drainNativeEvents(
      readEvent: (timeoutMs) {
        timeouts.add(timeoutMs);
        return pending.isEmpty ? '' : pending.removeAt(0);
      },
      onEvent: handled.add,
    );

    expect(drained, 2);
    expect(handled, ['first', 'second']);
    expect(timeouts, everyElement(0));
  });

  test('event polling bounds work performed in one UI tick', () {
    var reads = 0;

    final drained = drainNativeEvents(
      readEvent: (_) {
        reads++;
        return 'event';
      },
      onEvent: (_) {},
    );

    expect(drained, maxEventsPerPoll);
    expect(reads, maxEventsPerPoll);
  });

  test('event polling rejects a non-positive batch limit', () {
    expect(
      () => drainNativeEvents(
        readEvent: (_) => '',
        onEvent: (_) {},
        maxEvents: 0,
      ),
      throwsArgumentError,
    );
  });
}
