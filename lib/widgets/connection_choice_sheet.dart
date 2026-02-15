import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ConnectionChoiceSheet extends StatelessWidget {
  final VoidCallback onTerminalSelected;
  final VoidCallback onSftpSelected;

  const ConnectionChoiceSheet({
    super.key,
    required this.onTerminalSelected,
    required this.onSftpSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              color: AppTheme.border,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Tools',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 8),
            _ConnectionTile(
              icon: Icons.terminal,
              iconColor: AppTheme.accent,
              title: 'Terminal',
              subtitle: 'Run commands on remote server',
              onTap: onTerminalSelected,
            ),
            _ConnectionTile(
              icon: Icons.folder_outlined,
              iconColor: AppTheme.info,
              title: 'SFTP',
              subtitle: 'Browse and transfer files',
              onTap: onSftpSelected,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ConnectionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                border: Border.all(color: iconColor.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

void showConnectionChoiceSheet(
  BuildContext context, {
  required VoidCallback onTerminal,
  required VoidCallback onSftp,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => ConnectionChoiceSheet(
      onTerminalSelected: onTerminal,
      onSftpSelected: onSftp,
    ),
  );
}
