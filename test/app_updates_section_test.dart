import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huginn_messenger/huginn_messenger.dart';
import 'package:huginn_messenger/main.dart';
import 'package:huginn_messenger/src/services/app_update_service.dart';
import 'package:huginn_messenger/src/widgets/app_updates_section.dart';

class _Updates extends AppUpdateService {
  _Updates({UpdatePlatform platform = UpdatePlatform.android})
    : super(platform: platform);
  Completer<UpdateCheck>? pendingCheck;
  Completer<bool>? pendingInstall;
  Object? failure;
  Object? installFailure;
  bool verifyPackage = true;
  UpdateAsset? verifiedAsset;
  int settingsOpens = 0;
  Completer<void>? pendingSettings;
  UpdateCheck result = const UpdateCheck(
    currentVersion: '1.0.0',
    release: AppRelease(version: '1.1.0'),
  );
  int installs = 0;

  @override
  Future<String> currentVersion() async => '1.0.0';

  @override
  Future<UpdateCheck> check() async {
    if (failure != null) throw failure!;
    return pendingCheck?.future ?? result;
  }

  @override
  Future<bool> install(
    UpdateAsset asset, {
    required void Function(double) onProgress,
  }) async {
    installs++;
    onProgress(0.5);
    if (verifyPackage) verifiedAsset = asset;
    if (installFailure != null) throw installFailure!;
    return pendingInstall?.future ?? true;
  }

  @override
  bool canOpenInstallationSettings(UpdateAsset asset) =>
      platform == UpdatePlatform.macos && verifiedAsset == asset;

  @override
  Future<void> openInstallationSettings() async {
    settingsOpens++;
    await pendingSettings?.future;
  }
}

void main() {
  late _Updates updates;
  final available = UpdateCheck(
    currentVersion: '1.0.0',
    release: AppRelease(
      version: '1.2.0',
      asset: UpdateAsset(
        name: 'update.apk',
        url: Uri.parse('https://github.com/update'),
        size: 1048576,
        digest: null,
      ),
    ),
  );
  setUp(() => updates = _Updates());
  tearDown(() => updates.dispose());

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdatesSection(service: updates)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Settings contains the updates section', (tester) async {
    final messenger = MessengerService();
    addTearDown(messenger.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(service: messenger)),
    );
    await tester.scrollUntilVisible(
      find.byType(AppUpdatesSection),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets(
    'install is enabled only after a successful check; busy buttons are disabled',
    (tester) async {
      await show(tester);
      expect(find.text('Current version: 1.0.0'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      updates.pendingCheck = Completer<UpdateCheck>();
      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      updates.pendingCheck!.complete(available);
      await tester.pumpAndSettle();
      expect(find.text('Version 1.2.0 is available (1.0 MB).'), findsOneWidget);
      updates.pendingInstall = Completer<bool>();
      await tester.tap(find.text('Install update'));
      await tester.pump();
      expect(find.text('Downloading 50%'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      updates.pendingInstall!.complete(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Installer opened.'), findsOneWidget);
      expect(updates.installs, 1);
    },
  );

  testWidgets(
    'recheck failure clears previously available install and allows retry',
    (tester) async {
      updates.result = available;
      await show(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      updates.failure = const UpdateException('Network unavailable');
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Network unavailable'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'missing platform package and up-to-date versions do not allow installation',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no installation package'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      updates.result = const UpdateCheck(
        currentVersion: '1.0.0',
        release: AppRelease(version: '1.0.0'),
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You are using the latest version.'), findsOneWidget);
    },
  );

  testWidgets('permission handoff does not claim installation succeeded', (
    tester,
  ) async {
    updates.result = available;
    updates.pendingInstall = Completer<bool>()..complete(false);
    await show(tester);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow Huginn to install apps'), findsOneWidget);
    expect(find.text('Allow installation…'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('blocked macOS package offers an explicit settings handoff', (
    tester,
  ) async {
    updates.dispose();
    updates = _Updates(platform: UpdatePlatform.macos)..result = available;
    await show(tester);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Allow installation…'), findsNothing);
    updates.installFailure = const UpdateException(
      'macOS blocked the installer',
    );
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(find.text('Allow installation…'), findsOneWidget);
    expect(find.textContaining('Open Anyway for this package'), findsOneWidget);
    expect(updates.settingsOpens, 0);
    updates.pendingSettings = Completer<void>();
    await tester.tap(find.text('Allow installation…'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    updates.pendingSettings!.complete();
    await tester.pumpAndSettle();
    expect(updates.settingsOpens, 1);
    expect(updates.installs, 1);
    expect(
      find.textContaining('Approve the package in Privacy & Security'),
      findsOneWidget,
    );
    expect(find.textContaining('Installer opened.'), findsNothing);
    updates.installFailure = null;
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(updates.installs, 2);
    expect(find.text('Allow installation…'), findsOneWidget);
    updates.failure = const UpdateException('Network unavailable');
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Allow installation…'), findsNothing);
  });

  testWidgets('a failed package check never offers installation approval', (
    tester,
  ) async {
    updates.dispose();
    updates = _Updates(platform: UpdatePlatform.macos)
      ..result = available
      ..verifyPackage = false
      ..installFailure = const UpdateException('Package verification failed.');
    await show(tester);
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(find.text('Package verification failed.'), findsOneWidget);
    expect(find.text('Allow installation…'), findsNothing);
  });

  testWidgets(
    'late response after closing settings does not update a disposed widget',
    (tester) async {
      updates.pendingCheck = Completer<UpdateCheck>();
      await show(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      updates.pendingCheck!.complete(available);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
