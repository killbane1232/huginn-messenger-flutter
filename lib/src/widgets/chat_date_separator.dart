import 'package:flutter/material.dart';

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.timestamp});

  final DateTime timestamp;

  static const _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = timestamp.toLocal();
    final dayAndMonth = '${date.day} ${_months[date.month - 1]}';
    final label = date.year == DateTime.now().year
        ? dayAndMonth
        : '$dayAndMonth ${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Semantics(
          header: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
