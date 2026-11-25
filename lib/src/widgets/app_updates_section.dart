import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

class AppUpdatesSection extends StatefulWidget {
  const AppUpdatesSection({super.key, this.service});
  final AppUpdateService? service;

  @override
  State<AppUpdatesSection> createState() => _AppUpdatesSectionState();
}

class _AppUpdatesSectionState extends State<AppUpdatesSection>
    with AutomaticKeepAliveClientMixin {
  late final AppUpdateService _service;
  String? _version;
  UpdateAsset? _asset;
  String _status = 'Check for updates from GitHub Releases.';
  bool _busy = false;
  bool _installing = false;
  bool _error = false;
  double? _progress;

  // Scrolling to another settings section must not cancel an active download.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppUpdateService();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await _service.currentVersion();
      if (mounted) setState(() => _version = version);
    } catch (_) {
      // A manual check retries reading package information and reports errors.
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = false;
      _asset = null;
      _status = 'Checking for updates…';
    });
    try {
      final check = await _service.check();
      if (!mounted) return;
      setState(() {
        _version = check.currentVersion;
        if (check.release == null) {
          _status = 'No published stable releases yet.';
        } else if (!check.hasUpdate) {
          _status = 'You are using the latest version.';
        } else {
          _asset = check.release!.asset;
          _status = _asset == null
              ? 'Version ${check.release!.version} is available, but there is no '
                    'installation package for this platform.'
              : 'Version ${check.release!.version} is available '
                    '(${(_asset!.size / (1024 * 1024)).toStringAsFixed(1)} MB).';
        }
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    final asset = _asset;
    if (asset == null) return;
    setState(() {
      _busy = true;
      _installing = true;
      _error = false;
      _progress = 0;
      _status = 'Downloading and verifying the update…';
    });
    try {
      final opened = await _service.install(
        asset,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _status = opened
            ? 'Installer opened. Complete the installation, then restart Huginn.'
            : 'Allow Huginn to install apps, then tap Install update again.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _installing = false;
          _progress = null;
        });
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = true;
      _status = error is UpdateException
          ? error.message
          : 'Could not update the app. Check your connection and try again. ($error)';
    });
  }

  Future<void> _openInstallationSettings() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _service.openInstallationSettings();
      if (!mounted) return;
      setState(() {
        _status =
            'Approve the package in Privacy & Security, then return to '
            'Huginn and tap Install update again if the installer has not opened.';
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final canOpenInstallationSettings =
        _asset != null && _service.canOpenInstallationSettings(_asset!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.system_update, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'App updates',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Current version: ${_version ?? 'unavailable'}'),
        const SizedBox(height: 4),
        Text(_status, style: TextStyle(color: _error ? colors.error : null)),
        if (!_service.supportsInstallation) ...[
          const SizedBox(height: 4),
          const Text(
            'Installing GitHub packages is not supported on this platform.',
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _installing ? _progress : null),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _check,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Check for updates'),
            ),
            FilledButton.icon(
              onPressed:
                  _busy || _asset == null || !_service.supportsInstallation
                  ? null
                  : _install,
              icon: const Icon(Icons.download, size: 18),
              label: Text(
                _installing
                    ? 'Downloading ${((_progress ?? 0) * 100).round()}%'
                    : 'Install update',
              ),
            ),
            if (canOpenInstallationSettings)
              OutlinedButton.icon(
                onPressed: _busy ? null : _openInstallationSettings,
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('Allow installation…'),
              ),
          ],
        ),
        if (canOpenInstallationSettings) ...[
          const SizedBox(height: 8),
          Text(
            'If macOS blocked "${_asset!.name}", open Privacy & Security, '
            'scroll to Security and choose Open Anyway for this package. '
            'If it is not listed, tap Install update to try opening it again.',
          ),
        ],
      ],
    );
  }
}
