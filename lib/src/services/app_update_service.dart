import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

import 'platform_service.dart';

enum UpdatePlatform { android, macos, linuxX64, linuxArm64, unsupported }

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.digest,
  });

  final String name;
  final Uri url;
  final int size;
  final String? digest;
}

class AppRelease {
  const AppRelease({required this.version, this.asset});
  final String version;
  final UpdateAsset? asset;
}

class UpdateCheck {
  const UpdateCheck({required this.currentVersion, this.release});
  final String currentVersion;
  final AppRelease? release;

  bool get hasUpdate =>
      release != null &&
      _version(release!.version).compareTo(_version(currentVersion)) > 0;
}

// Build metadata does not indicate an upgrade (SemVer precedence).
Version _version(String value) => Version.parse(value.split('+').first);

class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    Future<String> Function()? readVersion,
    Future<Directory> Function()? temporaryDirectory,
    Future<bool> Function(String)? openInstaller,
    Future<void> Function()? openSecuritySettings,
    UpdatePlatform? platform,
  }) : _client = client ?? http.Client(),
       _readVersion = readVersion ?? _installedVersion,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _openInstaller = openInstaller ?? PlatformService.installUpdate,
       _openSecuritySettings =
           openSecuritySettings ?? PlatformService.openUpdateSecuritySettings,
       platform = platform ?? _currentPlatform();

  static const repository = 'killbane1232/huginn-messenger-flutter';
  static final latestReleaseUrl = Uri.https(
    'api.github.com',
    '/repos/$repository/releases/latest',
  );
  static const _timeout = Duration(seconds: 30);
  final http.Client _client;
  final Future<String> Function() _readVersion;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<bool> Function(String) _openInstaller;
  final Future<void> Function() _openSecuritySettings;
  final UpdatePlatform platform;
  bool _disposed = false;
  File? _downloadedFile;
  UpdateAsset? _downloadedAsset;

  bool get supportsInstallation => platform != UpdatePlatform.unsupported;

  bool canOpenInstallationSettings(UpdateAsset asset) =>
      platform == UpdatePlatform.macos &&
      _downloadedAsset == asset &&
      _downloadedFile != null;

  Future<void> openInstallationSettings() async {
    _ensureActive();
    if (platform != UpdatePlatform.macos) {
      throw const UpdateException('These installation settings require macOS.');
    }
    try {
      await _openSecuritySettings();
    } catch (_) {
      throw const UpdateException(
        'Could not open security settings. Open System Settings → '
        'Privacy & Security manually and look for the blocked Huginn package.',
      );
    }
  }

  static Future<String> _installedVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  static UpdatePlatform _currentPlatform() {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isMacOS) return UpdatePlatform.macos;
    if (Platform.isLinux) {
      if (Abi.current() == Abi.linuxX64) return UpdatePlatform.linuxX64;
      if (Abi.current() == Abi.linuxArm64) return UpdatePlatform.linuxArm64;
    }
    return UpdatePlatform.unsupported;
  }

  Future<String> currentVersion() => _readVersion();

  Future<UpdateCheck> check() async {
    _ensureActive();
    final installed = await currentVersion();
    _version(
      installed,
    ); // Do not offer installs if the installed version is unknown.
    final response = await _client
        .get(
          latestReleaseUrl,
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Huginn-Messenger/$installed',
          },
        )
        .timeout(_timeout);
    _ensureActive();
    if (response.statusCode == 404) {
      return UpdateCheck(currentVersion: installed);
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException(
        'GitHub temporarily refused the request. Please try again later.',
      );
    }
    if (response.statusCode != 200) {
      throw UpdateException('GitHub returned HTTP ${response.statusCode}.');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['draft'] != false || json['prerelease'] != false) {
      return UpdateCheck(currentVersion: installed);
    }
    final tag = json['tag_name'] as String;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (_version(version).isPreRelease) {
      return UpdateCheck(currentVersion: installed);
    }
    final suffix = switch (platform) {
      UpdatePlatform.android => '.apk',
      UpdatePlatform.macos => '-macos-universal.pkg',
      UpdatePlatform.linuxX64 => '-linux-x64.deb',
      UpdatePlatform.linuxArm64 => '-linux-arm64.deb',
      UpdatePlatform.unsupported => null,
    };
    final expectedName = 'huginn-messenger-$version$suffix';
    UpdateAsset? asset;
    for (final value in json['assets'] as List<dynamic>) {
      final item = value as Map<String, dynamic>;
      if (suffix == null ||
          item['name'] != expectedName ||
          item['state'] != 'uploaded') {
        continue;
      }
      final url = Uri.parse(item['browser_download_url'] as String);
      // Only install assets belonging to the configured repository and release.
      final expectedUrl = Uri.https(
        'github.com',
        '/$repository/releases/download/$tag/$expectedName',
      );
      if (url != expectedUrl || (item['size'] as int) <= 0) continue;
      asset = UpdateAsset(
        name: expectedName,
        url: url,
        size: item['size'] as int,
        digest: item['digest'] as String?,
      );
      break;
    }
    return UpdateCheck(
      currentVersion: installed,
      release: AppRelease(version: version, asset: asset),
    );
  }

  /// Returns false when Android has opened the install permission settings.
  /// True means the system installer opened, not that installation completed.
  Future<bool> install(
    UpdateAsset asset, {
    required void Function(double) onProgress,
  }) async {
    _ensureActive();
    if (!supportsInstallation) {
      throw const UpdateException(
        'Installation is not supported on this platform.',
      );
    }
    final digest = asset.digest;
    if (digest == null ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const UpdateException(
        'This package has no SHA-256 checksum. Please wait for a new release.',
      );
    }
    var file = _downloadedAsset == asset ? _downloadedFile : null;
    if (file == null || !await file.exists()) {
      file = await _download(asset, onProgress);
    }
    // Recheck on retry too: the file may have changed since the last attempt.
    final actualDigest = await sha256.bind(file.openRead()).first;
    if (await file.length() != asset.size ||
        actualDigest.toString() != digest.substring(7).toLowerCase()) {
      await file.delete();
      _downloadedFile = null;
      _downloadedAsset = null;
      throw const UpdateException(
        'Package verification failed. Please download the update again.',
      );
    }
    _ensureActive();
    _downloadedFile = file;
    _downloadedAsset = asset;
    try {
      return await _openInstaller(file.path);
    } catch (_) {
      if (platform != UpdatePlatform.macos) rethrow;
      throw const UpdateException(
        'macOS could not open the installer. If the package was blocked, '
        'use Allow installation… to review it in Privacy & Security.',
      );
    }
  }

  Future<File> _download(
    UpdateAsset asset,
    void Function(double) onProgress,
  ) async {
    final cache = await _temporaryDirectory();
    final updates = await Directory(
      '${cache.path}/huginn-updates',
    ).create(recursive: true);
    final directory = await updates.createTemp('package-');
    final partial = File('${directory.path}/${asset.name}.part');
    try {
      final response = await _client
          .send(
            http.Request('GET', asset.url)
              ..headers['User-Agent'] = 'Huginn-Messenger',
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw UpdateException(
          'Package download failed (HTTP ${response.statusCode}).',
        );
      }
      var received = 0;
      final output = await partial.open(mode: FileMode.write);
      try {
        await for (final chunk in response.stream.timeout(_timeout)) {
          _ensureActive();
          received += chunk.length;
          if (received > asset.size) {
            throw const UpdateException(
              'Downloaded package is larger than expected.',
            );
          }
          await output.writeFrom(chunk);
          onProgress(received / asset.size);
        }
      } finally {
        await output.close();
      }
      if (received != asset.size) {
        throw const UpdateException(
          'The download was interrupted. Please try again.',
        );
      }
      return await partial.rename('${directory.path}/${asset.name}');
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  void _ensureActive() {
    if (_disposed) throw const UpdateException('Update cancelled.');
  }

  void dispose() {
    _disposed = true;
    _client.close();
    // Keep verified packages: the external installer may still be reading them.
  }
}
