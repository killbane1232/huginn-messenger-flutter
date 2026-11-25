import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';

class _SettingsService extends MessengerService {
  AppConfig value = AppConfig(
    username: 'alice',
    muninnAddr: 'https://first.example',
    muninnServers: ['https://second.example'],
    chunkTtl: '1m',
  );
  int saves = 0;

  @override
  AppConfig get config => value;

  @override
  bool saveConfig(AppConfig newConfig) {
    value = newConfig;
    saves++;
    return true;
  }
}

void main() {
  late _SettingsService service;
  setUp(() => service = _SettingsService());
  tearDown(() => service.dispose());

  Future<void> showSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(service: service)),
    );
    await tester.pumpAndSettle();
  }

  Finder getServerInput() =>
      find.widgetWithText(TextField, 'New Muninn server');

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'adds normalized server, removes active server, and saves all fields',
    (tester) async {
      await showSettings(tester);
      expect(find.text('TURN / STUN'), findsNothing);
      expect(find.text('Active server'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove server').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(getServerInput());
      await tester.enterText(getServerInput(), ' https://THIRD.example:443/ ');
      await tester.ensureVisible(find.text('Add server'));
      await tester.tap(find.text('Add server'));
      await tester.pumpAndSettle();
      expect(service.saves, 0);
      await save(tester);
      expect(service.value.allMuninnServers, [
        'https://second.example',
        'https://third.example',
      ]);
      expect(service.value.username, 'bob');
      expect(service.value.chunkTtl, '1m');
      expect(service.saves, 1);
    },
  );

  testWidgets('rejects invalid and duplicate addresses and an empty list', (
    tester,
  ) async {
    await showSettings(tester);
    await tester.ensureVisible(getServerInput());
    await tester.enterText(getServerInput(), 'https://host/path');
    await tester.ensureVisible(find.text('Add server'));
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an http(s) URL'), findsOneWidget);
    await tester.enterText(getServerInput(), 'https://FIRST.example:443/');
    await tester.ensureVisible(find.text('Add server'));
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();
    expect(find.text('This server is already in the list'), findsOneWidget);
    await tester.enterText(getServerInput(), '');
    for (var i = 0; i < 2; i++) {
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Remove server').first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove server').first);
      await tester.pumpAndSettle();
    }
    await save(tester);
    expect(service.saves, 0);
    await tester.scrollUntilVisible(
      getServerInput(),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add at least one Muninn server'), findsOneWidget);
  });

  testWidgets('Save includes a typed address even without pressing Add', (
    tester,
  ) async {
    await showSettings(tester);
    await tester.ensureVisible(getServerInput());
    await tester.enterText(getServerInput(), 'https://third.example');
    await save(tester);
    expect(service.value.allMuninnServers, contains('https://third.example'));
  });
  testWidgets(
    'renames a server with its ICE profile and preserves other servers',
    (tester) async {
      service.value.muninnIce = {
        'https://second.example': MuninnIceConfig(
          turnUrls: ['turn:second.example:3478'],
          turnUsername: 'second-user',
          turnPassword: 'second-password',
        ),
      };
      await showSettings(tester);
      await tester.tap(find.byTooltip('Edit server').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'STUN URLs'),
        'stun:first.example:3478',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'TURN URLs'),
        'turns:first.example:5349?transport=tcp',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'TURN username'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'TURN username'),
        'first-user',
      );
      final password = find.widgetWithText(TextField, 'TURN password');
      await tester.ensureVisible(password);
      await tester.pumpAndSettle();
      await tester.enterText(password, ' first-password ');
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(service.saves, 0);
      await tester.tap(find.byTooltip('Edit server').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Muninn server URL'),
        ' https://RENAMED.example:443/ ',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(service.value.muninnAddr, 'https://first.example');
      expect(service.saves, 0);
      await save(tester);
      expect(service.value.allMuninnServers, [
        'https://renamed.example',
        'https://second.example',
      ]);
      expect(
        service.value.muninnIce.containsKey('https://first.example'),
        isFalse,
      );
      expect(
        service.value.iceFor('https://renamed.example').turnPassword,
        ' first-password ',
      );
      expect(service.value.iceFor('https://renamed.example').stunUrls, [
        'stun:first.example:3478',
      ]);
      expect(
        service.value.iceFor('https://second.example').turnPassword,
        'second-password',
      );
    },
  );

  testWidgets('invalid ICE stays in the editor and Cancel discards changes', (
    tester,
  ) async {
    await showSettings(tester);
    await tester.tap(find.byTooltip('Edit server').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Muninn server URL'),
      'https://cancelled.example',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'TURN URLs'),
      'turn:first.example:3478',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('TURN requires a username and password'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(service.value.muninnIce, isEmpty);
    expect(service.value.muninnAddr, 'https://first.example');
  });
  testWidgets(
    'rejects invalid or duplicate edits and accepts the current normalized address',
    (tester) async {
      await showSettings(tester);
      await tester.tap(find.byTooltip('Edit server').first);
      await tester.pumpAndSettle();
      final address = find.widgetWithText(TextField, 'Muninn server URL');
      for (final invalid in ['', 'host:8080', 'https://host/path']) {
        await tester.enterText(address, invalid);
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('Enter an http(s) URL'), findsOneWidget);
      }
      await tester.enterText(address, 'https://SECOND.example:443/');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('This server is already in the list'), findsOneWidget);
      expect(service.saves, 0);
      await tester.enterText(address, ' https://FIRST.example:443/ ');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await save(tester);
      expect(service.value.allMuninnServers, [
        'https://first.example',
        'https://second.example',
      ]);
    },
  );
}
