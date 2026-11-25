import 'package:flutter/material.dart';

import '../models/config.dart';
import '../models/muninn_ice_config.dart';

typedef MuninnServerEdit = ({String address, MuninnIceConfig ice});

class MuninnIceDialog extends StatefulWidget {
  const MuninnIceDialog({
    super.key,
    required this.server,
    required this.config,
    required this.existingServers,
  });

  final String server;
  final MuninnIceConfig config;
  final List<String> existingServers;

  @override
  State<MuninnIceDialog> createState() => _MuninnIceDialogState();
}

class _MuninnIceDialogState extends State<MuninnIceDialog> {
  late final _address = TextEditingController(text: widget.server);
  late final _stun = TextEditingController(
    text: widget.config.stunUrls.join('\n'),
  );
  late final _turn = TextEditingController(
    text: widget.config.turnUrls.join('\n'),
  );
  late final _username = TextEditingController(
    text: widget.config.turnUsername,
  );
  late final _password = TextEditingController(
    text: widget.config.turnPassword,
  );
  bool _showPassword = false;
  String? _error;
  String? _addressError;

  @override
  void dispose() {
    _address.dispose();
    _stun.dispose();
    _turn.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  List<String> _urls(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  void _apply() {
    final address = AppConfig.normalizeMuninnAddr(_address.text);
    String? addressError;
    if (!AppConfig.isValidMuninnAddr(address)) {
      addressError =
          'Enter an http(s) URL without a path, credentials, query or fragment';
    } else if (address != AppConfig.normalizeMuninnAddr(widget.server) &&
        widget.existingServers
            .map(AppConfig.normalizeMuninnAddr)
            .contains(address)) {
      addressError = 'This server is already in the list';
    }
    setState(() => _addressError = addressError);
    if (addressError != null) return;

    final config = MuninnIceConfig(
      stunUrls: _urls(_stun.text),
      turnUrls: _urls(_turn.text),
      turnUsername: _username.text,
      turnPassword: _password.text,
    );
    final error = config.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop<MuninnServerEdit>(context, (
      address: address,
      ice: config.normalized(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit Muninn server'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Muninn server URL',
                hintText: 'https://muninn.example.org',
                errorText: _addressError,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Used when this Muninn server is selected. Leave the URL lists '
              'empty to disable STUN and TURN for this server. '
              'Save Settings to apply changes.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stun,
              autocorrect: false,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'STUN URLs',
                hintText: 'stun:stun.example.org:3478',
                helperText: 'One URL per line',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _turn,
              autocorrect: false,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'TURN URLs',
                hintText:
                    'turn:turn.example.org:3478?transport=udp\n'
                    'turns:turn.example.org:5349?transport=tcp',
                helperText: 'One URL per line',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'TURN username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'TURN password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Apply')),
    ],
  );
}
