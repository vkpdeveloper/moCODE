import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../models/app_models.dart' as app_models;
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';

class AgentSelectionScreen extends ConsumerWidget {
  const AgentSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final agentsAsync = ref.watch(agentsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/connect');
          },
        ),
        title: const Text(
          'AGENTS',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (settings.connectedDeviceName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                settings.connectedDeviceName!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          agentsAsync.when(
            data: (agents) {
              if (agents.isEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.memory_outlined,
                        color: AppTheme.textTertiary,
                        size: 36,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No agents are available on this device.',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: agents.map((agent) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: AppTheme.surface,
                      child: InkWell(
                        onTap: () => _selectAgent(context, ref, agent),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _AgentIcon(iconSvg: agent.iconSvg),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      agent.name,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if ((agent.description ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        agent.description!,
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppTheme.textTertiary,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            ),
            error: (error, _) => Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.error,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(agentsProvider),
                    child: const Text('RETRY'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAgent(
    BuildContext context,
    WidgetRef ref,
    app_models.Agent agent,
  ) async {
    final connectionKey = ref.read(settingsProvider).selectedConnectionKey;
    if (connectionKey == null || connectionKey.isEmpty) {
      AppSnackBar.showError(context, 'Select a device first.');
      context.go('/connect');
      return;
    }
    if (agent.mode == null || agent.mode!.isEmpty) {
      AppSnackBar.showError(context, 'This agent is missing an identifier.');
      return;
    }

    await ref
        .read(selectedAgentProvider.notifier)
        .selectAgent(connectionKey: connectionKey, agent: agent);
    ref.read(selectedModelProvider.notifier).state = null;
    ref.read(selectedSessionProvider.notifier).state = null;
    ref.invalidate(providersListProvider);
    ref.invalidate(projectsProvider);
    ref.invalidate(sessionsProvider);
    if (context.mounted) {
      context.go('/projects');
    }
  }
}

class _AgentIcon extends StatelessWidget {
  const _AgentIcon({required this.iconSvg});

  final String? iconSvg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: iconSvg != null && iconSvg!.isNotEmpty
          ? SvgPicture.string(
              iconSvg!,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppTheme.textPrimary,
                BlendMode.srcIn,
              ),
            )
          : const Icon(
              Icons.memory_outlined,
              color: AppTheme.textSecondary,
              size: 20,
            ),
    );
  }
}
