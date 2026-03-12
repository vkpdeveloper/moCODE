import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/provider.dart';
import '../models/project.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/fuzzysort.dart';

Map<String, String>? _normalizeModelSelection(Map<String, String>? model) {
  if (model == null) {
    return null;
  }
  return model['providerID'] == 'local' ? null : model;
}

class ModelPickerScreen extends ConsumerStatefulWidget {
  final String? mode;

  const ModelPickerScreen({super.key, this.mode});

  @override
  ConsumerState<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends ConsumerState<ModelPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectionScope = 'session';
  String _selectedTab = 'configured'; // 'configured' or 'all'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final mode = widget.mode;
    if (mode == 'default') {
      _selectionScope = 'default';
    } else if (mode == 'project') {
      _selectionScope = 'project';
    } else if (mode == 'session') {
      _selectionScope = 'session';
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(providersListProvider);
    final project = ref.watch(selectedProjectProvider);
    final defaultModel = _normalizeModelSelection(
      ref.watch(defaultModelProvider),
    );
    final projectModelState = ref.watch(projectModelProvider);
    final projectModel = _normalizeModelSelection(projectModelState.model);
    if (project != null &&
        (projectModelState.isLoading ||
            projectModelState.projectId != project.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(projectModelProvider.notifier).load(project.id);
      });
    }
    if (project == null && _selectionScope == 'project') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectionScope = 'default');
        }
      });
    }
    final sessionSelection = _normalizeModelSelection(
      ref.watch(selectedModelProvider),
    );
    Map<String, String>? currentSelection;
    if (_selectionScope == 'session') {
      currentSelection = sessionSelection;
    } else if (_selectionScope == 'project') {
      currentSelection = projectModel;
    } else {
      currentSelection = defaultModel;
    }

    final activeSelection = ref.watch(activeModelProvider);
    String? activeSource;
    if (sessionSelection != null) {
      activeSource = 'Session';
    } else if (projectModel != null) {
      activeSource = 'Project';
    } else if (defaultModel != null) {
      activeSource = 'Default';
    }

    String scopeLabel;
    if (_selectionScope == 'session') {
      scopeLabel = 'SESSION';
    } else if (_selectionScope == 'project') {
      scopeLabel = 'PROJECT';
    } else {
      scopeLabel = 'DEFAULT';
    }

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
                _clearSelection(project);
              },
              child: Text(
                _selectionScope == 'session'
                    ? 'CLEAR SESSION'
                    : _selectionScope == 'project'
                    ? 'CLEAR PROJECT'
                    : 'CLEAR DEFAULT',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _scopeBar(
            project: project,
            defaultModel: defaultModel,
            projectModel: projectModel,
            projectModelState: projectModelState,
            activeSource: activeSource,
            activeSelection: activeSelection,
          ),
          _buildTabBar(),
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
                final favourites = ref.watch(favouriteModelsProvider);
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
                          'No models available',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                final filtered = _filterProviders(
                  providers,
                  favourites,
                  providerList.connected,
                );

                if (filtered.isEmpty && _query.isNotEmpty) {
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
                          _query.isEmpty
                              ? 'No models available'
                              : 'No results. Try shorter or different keywords.',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Build favourite models list for display
                final favouriteModels = <_FavouriteDisplayModel>[];
                for (final fav in favourites) {
                  final providerId = fav['providerId'] as String?;
                  final modelId = fav['modelId'] as String?;
                  if (providerId == null || modelId == null) continue;

                  // Check if matches search query
                  if (_query.isNotEmpty) {
                    final providerName =
                        (fav['providerName'] as String?) ?? providerId;
                    final modelName = (fav['modelName'] as String?) ?? modelId;
                    final searchText = '$providerName $modelName $modelId'
                        .toLowerCase();
                    if (!searchText.contains(_query)) continue;
                  }

                  favouriteModels.add(
                    _FavouriteDisplayModel(
                      providerId: providerId,
                      providerName: fav['providerName'] as String?,
                      modelId: modelId,
                      modelName: fav['modelName'] as String?,
                      family: fav['family'] as String?,
                      status: fav['status'] as String?,
                      reasoning: fav['reasoning'] as bool?,
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount:
                      filtered.length + (favouriteModels.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Show favourites section first
                    if (favouriteModels.isNotEmpty && index == 0) {
                      return _buildFavouritesSection(
                        favouriteModels: favouriteModels,
                        currentSelection: currentSelection,
                        activeSelection: activeSelection,
                        scopeLabel: scopeLabel,
                        project: project,
                        favourites: favourites,
                      );
                    }

                    final adjustedIndex = favouriteModels.isNotEmpty
                        ? index - 1
                        : index;
                    final entry = filtered[adjustedIndex];
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
                            final isActive =
                                activeSelection != null &&
                                activeSelection['providerID'] == provider.id &&
                                activeSelection['modelID'] == model.id;
                            final isFav = ref
                                .read(favouriteModelsProvider.notifier)
                                .isFavourite(provider.id, model.id);

                            return _buildModelRow(
                              providerId: provider.id,
                              providerName: provider.name,
                              modelId: model.id,
                              modelName: model.name,
                              family: model.family,
                              status: model.status,
                              reasoning: model.reasoning,
                              isSelected: isSelected,
                              isActive: isActive,
                              isFavourite: isFav,
                              scopeLabel: scopeLabel,
                              project: project,
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

  Widget _buildFavouritesSection({
    required List<_FavouriteDisplayModel> favouriteModels,
    required Map<String, String>? currentSelection,
    required Map<String, String>? activeSelection,
    required String scopeLabel,
    required Project? project,
    required List<Map<String, dynamic>> favourites,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              border: Border(bottom: BorderSide(color: AppTheme.warning)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, size: 14, color: AppTheme.warning),
                const SizedBox(width: 8),
                const Text(
                  'FAVOURITES',
                  style: TextStyle(
                    color: AppTheme.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${favouriteModels.length} models',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          ...favouriteModels.map((fav) {
            final isSelected =
                currentSelection != null &&
                currentSelection['providerID'] == fav.providerId &&
                currentSelection['modelID'] == fav.modelId;
            final isActive =
                activeSelection != null &&
                activeSelection['providerID'] == fav.providerId &&
                activeSelection['modelID'] == fav.modelId;

            return _buildModelRow(
              providerId: fav.providerId,
              providerName: fav.providerName,
              modelId: fav.modelId,
              modelName: fav.modelName,
              family: fav.family,
              status: fav.status,
              reasoning: fav.reasoning,
              isSelected: isSelected,
              isActive: isActive,
              isFavourite: true,
              scopeLabel: scopeLabel,
              project: project,
              showProvider: true,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModelRow({
    required String providerId,
    required String? providerName,
    required String modelId,
    required String? modelName,
    String? family,
    String? status,
    bool? reasoning,
    required bool isSelected,
    required bool isActive,
    required bool isFavourite,
    required String scopeLabel,
    required Project? project,
    bool showProvider = false,
  }) {
    return GestureDetector(
      onTap: () {
        _selectModel(
          providerId: providerId,
          modelId: modelId,
          projectId: project?.id,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentDim.withValues(alpha: 0.3)
              : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                ref.read(favouriteModelsProvider.notifier).toggleFavourite({
                  'providerId': providerId,
                  'providerName': providerName,
                  'modelId': modelId,
                  'modelName': modelName,
                  'family': family,
                  'status': status,
                  'reasoning': reasoning,
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isFavourite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: isFavourite ? AppTheme.warning : AppTheme.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelName ?? modelId,
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
                    showProvider
                        ? '${providerName ?? providerId} • $modelId'
                        : modelId,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected || isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: isSelected ? AppTheme.accent : AppTheme.surfaceVariant,
                child: Text(
                  isSelected ? 'SET $scopeLabel' : 'ACTIVE',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_FilteredProvider> _filterProviders(
    List<ProviderModel> providers,
    List<Map<String, dynamic>> favourites,
    List<String> connected,
  ) {
    // Filter providers based on tab selection
    List<ProviderModel> filteredProviders;
    if (_selectedTab == 'configured') {
      filteredProviders = providers
          .where((p) => connected.contains(p.id))
          .toList();
    } else {
      filteredProviders = providers;
    }

    // Helper to filter out deprecated models
    List<ProviderModelInfo> filterNonDeprecated(
      List<ProviderModelInfo> models,
    ) {
      return models.where((m) => m.status != 'deprecated').toList();
    }

    // Helper to check if a model is favourite
    bool isFav(String providerId, String modelId) {
      return favourites.any(
        (f) => f['providerId'] == providerId && f['modelId'] == modelId,
      );
    }

    // Helper to sort models with favourites first
    List<ProviderModelInfo> sortModels(
      ProviderModel provider,
      List<ProviderModelInfo> models,
    ) {
      final nonDeprecated = filterNonDeprecated(models);
      final sorted = List<ProviderModelInfo>.from(nonDeprecated);
      sorted.sort((a, b) {
        final aFav = isFav(provider.id, a.id);
        final bFav = isFav(provider.id, b.id);
        if (aFav && !bFav) return -1;
        if (!aFav && bFav) return 1;
        return 0;
      });
      return sorted;
    }

    if (_query.isEmpty) {
      // Sort providers with favourites to top
      final sorted = List<ProviderModel>.from(filteredProviders);
      sorted.sort((a, b) {
        final aHasFav = filterNonDeprecated(
          a.models,
        ).any((m) => isFav(a.id, m.id));
        final bHasFav = filterNonDeprecated(
          b.models,
        ).any((m) => isFav(b.id, m.id));
        if (aHasFav && !bHasFav) return -1;
        if (!aHasFav && bHasFav) return 1;
        return 0;
      });
      return sorted
          .map((p) {
            final models = sortModels(p, p.models);
            if (models.isEmpty) return null;
            return _FilteredProvider(provider: p, models: models);
          })
          .whereType<_FilteredProvider>()
          .toList();
    }

    // Build flat list of model entries for fuzzysort (using filtered providers)
    final modelEntries = <_ModelEntry>[];
    for (final provider in filteredProviders) {
      for (final model in filterNonDeprecated(provider.models)) {
        modelEntries.add(_ModelEntry(provider: provider, model: model));
      }
    }

    // Use fuzzysort with keys for model name (title) and provider name (category)
    // Prioritize model name matches (weight: 2) over provider name matches (weight: 1)
    final results = Fuzzysort.go<_ModelEntry>(
      _query,
      modelEntries,
      FuzzysortOptions(
        keys: ['modelName', 'providerName'],
        getValue: (entry, key) {
          if (key == 'modelName') {
            return entry.model.name ?? entry.model.id;
          } else if (key == 'providerName') {
            return entry.provider.name ?? entry.provider.id;
          }
          return null;
        },
        scoreFn: (r) {
          // Weight model name matches 2x, provider name 1x
          final modelScore = r[0]?.score ?? 0;
          final providerScore = r[1]?.score ?? 0;
          return modelScore * 2 + providerScore;
        },
      ),
    );

    // Group matched models by provider
    final grouped = <String, List<_ScoredModel>>{};
    for (final result in results) {
      final entry = result.obj as _ModelEntry;
      grouped
          .putIfAbsent(entry.provider.id, () => [])
          .add(_ScoredModel(model: entry.model, score: result.score));
    }

    // Build filtered provider list maintaining original provider order but sorted by score
    final filteredResults = <_FilteredProvider>[];
    for (final provider in filteredProviders) {
      final scoredModels = grouped[provider.id];
      if (scoredModels == null || scoredModels.isEmpty) continue;

      // Models are already sorted by fuzzysort score (best first)
      // But also sort favourites first within each provider
      var modelsList = scoredModels.map((m) => m.model).toList();
      modelsList.sort((a, b) {
        final aFav = isFav(provider.id, a.id);
        final bFav = isFav(provider.id, b.id);
        if (aFav && !bFav) return -1;
        if (!aFav && bFav) return 1;
        return 0;
      });
      filteredResults.add(
        _FilteredProvider(provider: provider, models: modelsList),
      );
    }

    // Sort providers by their best matching model score
    filteredResults.sort((a, b) {
      final aScore = grouped[a.provider.id]?.first.score ?? 0;
      final bScore = grouped[b.provider.id]?.first.score ?? 0;
      return bScore.compareTo(aScore);
    });

    return filteredResults;
  }

  void _selectModel({
    required String providerId,
    required String modelId,
    required String? projectId,
  }) {
    if (_selectionScope == 'default') {
      ref.read(defaultModelProvider.notifier).setModel(providerId, modelId);
      _clearSessionOverride();
      _notify('Default model set');
    } else if (_selectionScope == 'project') {
      if (projectId == null) return;
      ref
          .read(projectModelProvider.notifier)
          .setModel(projectId, providerId, modelId);
      _clearSessionOverride();
      _notify('Project model set');
    } else {
      ref.read(selectedModelProvider.notifier).state = {
        'providerID': providerId,
        'modelID': modelId,
      };
      final session = ref.read(selectedSessionProvider);
      if (session != null) {
        ref
            .read(preferencesServiceProvider)
            .saveSessionModel(session.id, providerId, modelId);
      }
      _notify('Session model set');
    }
    context.pop();
  }

  void _clearSelection(Project? project) {
    if (_selectionScope == 'default') {
      ref.read(defaultModelProvider.notifier).clearModel();
      _clearSessionOverride();
      _notify('Default model cleared');
    } else if (_selectionScope == 'project') {
      final projectId = project?.id;
      if (projectId == null) return;
      ref.read(projectModelProvider.notifier).clearModel(projectId);
      _clearSessionOverride();
      _notify('Project model cleared');
    } else {
      final session = ref.read(selectedSessionProvider);
      if (session != null) {
        ref.read(preferencesServiceProvider).clearSessionModel(session.id);
      }
      ref.read(selectedModelProvider.notifier).state = null;
      _notify('Session model cleared');
    }
    context.pop();
  }

  void _clearSessionOverride() {
    final session = ref.read(selectedSessionProvider);
    if (session != null) {
      ref.read(preferencesServiceProvider).clearSessionModel(session.id);
    }
    ref.read(selectedModelProvider.notifier).state = null;
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _buildTabButton('configured', 'CONFIGURED'),
          const SizedBox(width: 8),
          _buildTabButton('all', 'ALL MODELS'),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String label) {
    final isSelected = _selectedTab == tabId;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = tabId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _scopeBar({
    required Project? project,
    required Map<String, String>? defaultModel,
    required Map<String, String>? projectModel,
    required ProjectModelState projectModelState,
    required String? activeSource,
    required Map<String, String>? activeSelection,
  }) {
    final hasProject = project != null;
    final hasSession = ref.read(selectedSessionProvider) != null;
    final scopeItems = <_ScopeItem>[
      _ScopeItem(
        id: 'session',
        label: 'Session',
        enabled: hasSession,
        helper: 'Temporary override for this chat',
      ),
      if (hasProject)
        _ScopeItem(
          id: 'project',
          label: 'Project',
          enabled: true,
          helper: projectModel == null
              ? (projectModelState.isLoading
                    ? 'Loading project default...'
                    : 'No project default set')
              : 'Current: ${projectModel['modelID']}',
        ),
      _ScopeItem(
        id: 'default',
        label: 'Default',
        enabled: true,
        helper: defaultModel == null
            ? 'No default set'
            : 'Current: ${defaultModel['modelID']}',
      ),
    ];

    if (!hasSession && _selectionScope == 'session') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectionScope = hasProject ? 'project' : 'default');
        }
      });
    }
    final selectedItem = scopeItems.firstWhere(
      (item) => item.id == _selectionScope,
      orElse: () => scopeItems.first,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SET MODEL FOR',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: scopeItems.map((item) {
              final isSelected = _selectionScope == item.id;
              return GestureDetector(
                onTap: item.enabled
                    ? () => setState(() => _selectionScope = item.id)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accent.withValues(alpha: 0.15)
                        : AppTheme.surfaceVariant,
                    border: Border.all(
                      color: isSelected ? AppTheme.accent : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    item.label.toUpperCase(),
                    style: TextStyle(
                      color: item.enabled
                          ? (isSelected
                                ? AppTheme.accent
                                : AppTheme.textSecondary)
                          : AppTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedItem.helper,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
              if (activeSource != null && activeSelection != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    "ACTIVE: ${activeSource.toUpperCase()} - ${activeSelection['modelID']}",
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScopeItem {
  final String id;
  final String label;
  final bool enabled;
  final String helper;

  const _ScopeItem({
    required this.id,
    required this.label,
    required this.enabled,
    required this.helper,
  });
}

class _FilteredProvider {
  final ProviderModel provider;
  final List<ProviderModelInfo> models;

  const _FilteredProvider({required this.provider, required this.models});
}

class _ModelEntry {
  final ProviderModel provider;
  final ProviderModelInfo model;

  const _ModelEntry({required this.provider, required this.model});
}

class _ScoredModel {
  final ProviderModelInfo model;
  final double score;

  const _ScoredModel({required this.model, required this.score});
}

class _FavouriteDisplayModel {
  final String providerId;
  final String? providerName;
  final String modelId;
  final String? modelName;
  final String? family;
  final String? status;
  final bool? reasoning;

  const _FavouriteDisplayModel({
    required this.providerId,
    this.providerName,
    required this.modelId,
    this.modelName,
    this.family,
    this.status,
    this.reasoning,
  });
}
