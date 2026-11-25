import 'package:flutter/material.dart';

import '../models/app_event.dart';
import '../services/messenger_service.dart';

class MuninnConnectionIndicator extends StatelessWidget
    implements PreferredSizeWidget {
  const MuninnConnectionIndicator({super.key, required this.service});

  final MessengerService service;

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) => StreamBuilder<AppEvent>(
    stream: service.events,
    builder: (context, _) {
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      final (label, icon, color) = switch (service.muninnConnectionState) {
        MuninnConnectionState.connecting => (
          'Connecting to Muninn…',
          Icons.sync,
          dark ? Colors.amber.shade300 : Colors.orange.shade900,
        ),
        MuninnConnectionState.connected => (
          'Connected to Muninn',
          Icons.cloud_done_outlined,
          dark ? Colors.green.shade300 : Colors.green.shade800,
        ),
        MuninnConnectionState.disconnected => (
          'Muninn: not connected',
          Icons.cloud_off_outlined,
          theme.colorScheme.error,
        ),
      };
      return SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Semantics(
            liveRegion: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
