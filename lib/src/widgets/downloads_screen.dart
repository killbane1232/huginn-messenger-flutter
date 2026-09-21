import 'dart:async';

import 'package:flutter/material.dart';

import '../models/file_download.dart';
import '../services/messenger_service.dart';

class DownloadsButton extends StatelessWidget {
  final MessengerService service;

  const DownloadsButton({super.key, required this.service});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.downloading),
    tooltip: 'Downloads',
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DownloadsScreen(service: service)),
    ),
  );
}

class DownloadsScreen extends StatefulWidget {
  final MessengerService service;

  const DownloadsScreen({super.key, required this.service});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Timer? _timer;
  List<FileDownload>? _downloads;
  final Set<String> _cancelling = {};
  bool _loadFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final downloads = await widget.service.getFileDownloads();
      if (!mounted || request != _request) return;
      setState(() {
        _downloads = downloads;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _cancel(FileDownload download) async {
    setState(() => _cancelling.add(download.fileId));
    try {
      await widget.service.cancelFileDownload(download.fileId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel download. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cancelling.remove(download.fileId));
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Downloads')),
    body: Column(
      children: [
        if (_loadFailed)
          MaterialBanner(
            content: const Text('Could not load downloads.'),
            actions: [
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        Expanded(child: _buildList()),
      ],
    ),
  );

  Widget _buildList() {
    final downloads = _downloads;
    if (downloads == null) {
      return _loadFailed
          ? const SizedBox.shrink()
          : const Center(child: CircularProgressIndicator());
    }
    if (downloads.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_done, size: 48),
            SizedBox(height: 12),
            Text('No downloads in progress'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: downloads.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final download = downloads[index];
        final cancelling = _cancelling.contains(download.fileId);
        final percent = (download.progress * 100).floor();
        return Card(
          key: ValueKey(download.fileId),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: download.progress,
                        semanticsLabel: download.displayName,
                        semanticsValue: '$percent%',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        download.progress >= 1
                            ? '100% · Finishing…'
                            : '$percent% · ${download.receivedChunks} / ${download.totalChunks} parts received',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (cancelling)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Cancel download',
                    onPressed: () => _cancel(download),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
