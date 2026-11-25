import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huginn_messenger/src/services/app_update_service.dart';

const _repo = AppUpdateService.repository;
final _bytes = utf8.encode('test installation package');

Map<String, dynamic> _asset(String name, {String version = '1.2.0'}) => {
  'name': name,
  'state': 'uploaded',
  'size': _bytes.length,
  'digest': 'sha256:${sha256.convert(_bytes)}',
  'browser_download_url':
      'https://github.com/$_repo/releases/download/v$version/$name',
};

Map<String, dynamic> _release({String version = '1.2.0'}) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'assets': [
    _asset('huginn-messenger-$version.apk', version: version),
    _asset('huginn-messenger-$version-macos-universal.pkg', version: version),
    _asset('huginn-messenger-$version-linux-x64.deb', version: version),
  ],
};

void main() {
  late Directory cache;
  late AppUpdateService service;
  late Map<String, dynamic> release;
  late List<String> opened;
  late List<http.Request> requests;
  late int status;
  late List<int> downloadBytes;
  late bool permissionGranted;
  Object? installerFailure;
  Object? settingsFailure;
  late int settingsOpens;

  AppUpdateService createService({
    String version = '1.0.0',
    UpdatePlatform platform = UpdatePlatform.android,
    http.Client? client,
  }) => AppUpdateService(
    platform: platform,
    readVersion: () async => version,
    temporaryDirectory: () async => cache,
    openInstaller: (path) async {
      opened.add(path);
      if (installerFailure != null) throw installerFailure!;
      return permissionGranted;
    },
    openSecuritySettings: () async {
      settingsOpens++;
      if (settingsFailure != null) throw settingsFailure!;
    },
    client:
        client ??
        MockClient((request) async {
          requests.add(request);
          return request.url == AppUpdateService.latestReleaseUrl
              ? http.Response(jsonEncode(release), status)
              : http.Response.bytes(downloadBytes, 200);
        }),
  );

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('huginn-updater-test-');
    release = _release();
    opened = [];
    requests = [];
    status = 200;
    downloadBytes = _bytes;
    permissionGranted = true;
    installerFailure = null;
    settingsFailure = null;
    settingsOpens = 0;
    service = createService();
  });
  tearDown(() async {
    service.dispose();
    await cache.delete(recursive: true);
  });

  test(
    'blocked macOS installer offers settings and retries the verified file',
    () async {
      service.dispose();
      service = createService(platform: UpdatePlatform.macos);
      final asset = (await service.check()).release!.asset!;
      expect(service.canOpenInstallationSettings(asset), isFalse);
      installerFailure = StateError('LaunchServices rejected the package');
      await expectLater(
        service.install(asset, onProgress: (_) {}),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.message,
            'message',
            contains('Allow installation…'),
          ),
        ),
      );
      expect(service.canOpenInstallationSettings(asset), isTrue);
      expect(settingsOpens, 0);
      await service.openInstallationSettings();
      expect(settingsOpens, 1);
      expect(
        opened,
        hasLength(1),
      ); // Opening settings does not install or approve.
      installerFailure = null;
      expect(await service.install(asset, onProgress: (_) {}), isTrue);
      expect(opened, [opened.first, opened.first]);
      expect(requests, hasLength(2)); // Release check and one download.
      final newAsset = (await service.check()).release!.asset!;
      expect(service.canOpenInstallationSettings(newAsset), isFalse);

      // A retry must still reject a file modified after the initial verification.
      await File(opened.first).writeAsBytes(List.filled(_bytes.length, 0));
      await expectLater(
        service.install(asset, onProgress: (_) {}),
        throwsA(isA<UpdateException>()),
      );
      expect(service.canOpenInstallationSettings(asset), isFalse);
      expect(opened, hasLength(2));
    },
  );

  test('settings launch failure gives a manual macOS path', () async {
    service.dispose();
    service = createService(platform: UpdatePlatform.macos);
    settingsFailure = StateError('Settings unavailable');
    await expectLater(
      service.openInstallationSettings(),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          contains('Open System Settings → Privacy & Security manually'),
        ),
      ),
    );
  });

  test(
    'other platforms do not offer or launch macOS security settings',
    () async {
      final asset = (await service.check()).release!.asset!;
      await service.install(asset, onProgress: (_) {});
      expect(service.canOpenInstallationSettings(asset), isFalse);
      await expectLater(
        service.openInstallationSettings(),
        throwsA(isA<UpdateException>()),
      );
      expect(settingsOpens, 0);
    },
  );

  test('selects only the package for the current platform', () async {
    for (final entry in {
      UpdatePlatform.android: '.apk',
      UpdatePlatform.macos: '-macos-universal.pkg',
      UpdatePlatform.linuxX64: '-linux-x64.deb',
    }.entries) {
      service.dispose();
      service = createService(platform: entry.key);
      final result = await service.check();
      expect(result.hasUpdate, isTrue);
      expect(
        result.release!.asset!.name,
        'huginn-messenger-1.2.0${entry.value}',
      );
      expect(requests.last.headers['Accept'], 'application/vnd.github+json');
    }
  });

  test('compares SemVer numerically and ignores build metadata', () async {
    for (final pair in [
      ('1.9.0', '1.10.0', true),
      ('1.2.0', '1.2.0', false),
      ('2.0.0', '1.2.0', false),
      ('1.2.0+1', '1.2.0+99', false),
      ('1.2.0-rc.1', '1.2.0', true),
    ]) {
      expect(
        UpdateCheck(
          currentVersion: pair.$1,
          release: AppRelease(version: pair.$2),
        ).hasUpdate,
        pair.$3,
      );
    }
  });

  test('ignores drafts and prereleases, including mislabeled tags', () async {
    for (final json in [
      {..._release(), 'draft': true},
      {..._release(), 'prerelease': true},
      _release(version: '1.3.0-beta.1'),
    ]) {
      release = json;
      expect((await service.check()).release, isNull);
    }
  });

  test(
    'no releases, missing assets, and unsupported architectures are distinct',
    () async {
      status = 404;
      expect((await service.check()).release, isNull);
      status = 200;
      for (final platform in [
        UpdatePlatform.linuxArm64,
        UpdatePlatform.unsupported,
      ]) {
        service.dispose();
        service = createService(platform: platform);
        final result = await service.check();
        expect(result.hasUpdate, isTrue);
        expect(result.release!.asset, isNull);
      }
    },
  );

  test('rejects asset URLs outside the exact repository release', () async {
    for (final url in [
      'http://github.com/$_repo/releases/download/v1.2.0/huginn-messenger-1.2.0.apk',
      'https://example.com/huginn-messenger-1.2.0.apk',
      'https://github.com/another/repo/releases/download/v1.2.0/huginn-messenger-1.2.0.apk',
    ]) {
      (release['assets'] as List).first['browser_download_url'] = url;
      expect((await service.check()).release!.asset, isNull);
    }
  });

  test(
    'reports API errors and malformed versions instead of offering an install',
    () async {
      for (final code in [403, 429, 500]) {
        status = code;
        await expectLater(service.check(), throwsA(isA<UpdateException>()));
      }
      status = 200;
      release['tag_name'] = 'nightly';
      await expectLater(service.check(), throwsFormatException);
    },
  );

  test('downloads, verifies, and opens the package with progress', () async {
    final asset = (await service.check()).release!.asset!;
    final progress = <double>[];
    expect(await service.install(asset, onProgress: progress.add), isTrue);
    expect(progress.last, 1);
    expect(opened, hasLength(1));
    expect(await File(opened.single).readAsBytes(), _bytes);
    expect(opened.single.endsWith('.apk'), isTrue);
  });

  test('permission retry reuses but rechecks the verified download', () async {
    final asset = (await service.check()).release!.asset!;
    permissionGranted = false;
    expect(await service.install(asset, onProgress: (_) {}), isFalse);
    permissionGranted = true;
    expect(await service.install(asset, onProgress: (_) {}), isTrue);
    expect(requests, hasLength(2)); // Metadata plus a single download.
    await File(opened.last).writeAsBytes(List.filled(_bytes.length, 0));
    await expectLater(
      service.install(asset, onProgress: (_) {}),
      throwsA(isA<UpdateException>()),
    );
    expect(opened, hasLength(2));
  });

  test('missing checksum prevents downloading or installing', () async {
    (release['assets'] as List).first['digest'] = null;
    final asset = (await service.check()).release!.asset!;
    await expectLater(
      service.install(asset, onProgress: (_) {}),
      throwsA(isA<UpdateException>()),
    );
    expect(requests, hasLength(1));
    expect(opened, isEmpty);
  });

  test(
    'truncated, oversized and corrupt packages never reach the installer',
    () async {
      final asset = (await service.check()).release!.asset!;
      for (final bytes in [
        _bytes.sublist(1),
        [..._bytes, 0],
        List.filled(_bytes.length, 0),
      ]) {
        downloadBytes = bytes;
        await expectLater(
          service.install(asset, onProgress: (_) {}),
          throwsA(isA<UpdateException>()),
        );
        expect(opened, isEmpty);
        expect(
          await cache.list(recursive: true).where((e) => e is File).toList(),
          isEmpty,
        );
      }
    },
  );

  test(
    'leaving settings during download never launches an installer',
    () async {
      final asset = (await service.check()).release!.asset!;
      service.dispose();
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      service = createService(
        client: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      final install = service.install(asset, onProgress: (_) {});
      final expectation = expectLater(install, throwsA(isA<UpdateException>()));
      await started.future;
      service.dispose();
      pending.complete(http.Response.bytes(_bytes, 200));
      await expectation;
      expect(opened, isEmpty);
    },
  );
}
