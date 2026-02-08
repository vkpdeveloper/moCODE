import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/provider.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class ModelPickerScreen extends ConsumerStatefulWidget {
  final void Function(String providerId, String modelId)? onSelection;
  final Map<String, String>? selectedModel;

  const ModelPickerScreen({super.key, this.onSelection, this.selectedModel});

  @override
  ConsumerState<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends ConsumerState<ModelPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(providersListProvider);
    // Use widget.selectedModel if provided, otherwise fall back to the session-specific provider
    // If widget.onSelection is provided (Settings mode), we strictly use widget.selectedModel.
    // If widget.onSelection is null (Chat mode), we use selectedModelProvider.
    final currentSelection = widget.onSelection != null
        ? widget.selectedModel
        : ref.watch(selectedModelProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'MODELS',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
        actions: [
          if (currentSelection != null)
            TextButton(
              onPressed: () {
                if (widget.onSelection != null) {
                  // In settings mode, we generally don't "reset" to null,
                  // but maybe we want to unset the default?
                  // For now let's disable reset in Settings mode or handle it
                  // But the user might want to "Clear Default".
                  // Let's implement it if needed, but for now just handle session reset
                } else {
                  ref.read(selectedModelProvider.notifier).state = null;
                }
              },
              child: widget.onSelection == null
                  ? const Text('RESET', style: TextStyle(fontSize: 11))
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search models...',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppTheme.textTertiary,
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 36),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
                ),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
          ),
          Expanded(
            child: providersAsync.when(
              data: (providerList) {
                final providers = providerList.providers;
                if (providers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.model_training,
                          size: 48,
                          color: AppTheme.textTertiary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No providers available',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                final filtered = _filterProviders(providers);

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 40,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No models matching "$_query"',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    final provider = entry.provider;
                    final models = entry.models;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppTheme.border),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  color: AppTheme.accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  (provider.name ?? provider.id).toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${models.length} models',
                                  style: const TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...models.map((model) {
                            final isSelected =
                                currentSelection != null &&
                                currentSelection['providerID'] == provider.id &&
                                currentSelection['modelID'] == model.id;

                            return GestureDetector(
                              onTap: () {
                                if (widget.onSelection != null) {
                                  widget.onSelection!(provider.id, model.id);
                                } else {
                                  ref
                                      .read(selectedModelProvider.notifier)
                                      .state = {
                                    'providerID': provider.id,
                                    'modelID': model.id,
                                  };
                                }
                                context.pop();
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.accentDim.withValues(
                                          alpha: 0.3,
                                        )
                                      : Colors.transparent,
                                  border: const Border(
                                    bottom: BorderSide(
                                      color: AppTheme.border,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            model.name ?? model.id,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? AppTheme.accent
                                                  : AppTheme.textPrimary,
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            model.id,
                                            style: const TextStyle(
                                              color: AppTheme.textTertiary,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: AppTheme.accent,
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                    const SizedBox(height: 16),
                    Text(
                      error.toString(),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(providersListProvider),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_FilteredProvider> _filterProviders(List<ProviderModel> providers) {
    if (_query.isEmpty) {
      return providers
          .map((p) => _FilteredProvider(provider: p, models: p.models))
          .toList();
    }

    final results = <_FilteredProvider>[];
    for (final provider in providers) {
      final providerNameMatch = (provider.name ?? provider.id)
          .toLowerCase()
          .contains(_query);

      final matchingModels = provider.models.where((m) {
        final name = (m.name ?? m.id).toLowerCase();
        final id = m.id.toLowerCase();
        return name.contains(_query) || id.contains(_query);
      }).toList();

      if (providerNameMatch) {
        results.add(
          _FilteredProvider(provider: provider, models: provider.models),
        );
      } else if (matchingModels.isNotEmpty) {
        results.add(
          _FilteredProvider(provider: provider, models: matchingModels),
        );
      }
    }
    return results;
  }
}

class _FilteredProvider {
  final ProviderModel provider;
  final List<ProviderModelInfo> models;

  const _FilteredProvider({required this.provider, required this.models});
}
