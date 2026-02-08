import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/provider.dart';
import '../models/project.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

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
    final defaultModel = ref.watch(defaultModelProvider);
    final projectModelState = ref.watch(projectModelProvider);
    final projectModel = projectModelState.model;
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
    final sessionSelection = ref.watch(selectedModelProvider);
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
                            final isActive =
                                activeSelection != null &&
                                activeSelection['providerID'] == provider.id &&
                                activeSelection['modelID'] == model.id;

                            return GestureDetector(
                              onTap: () {
                                _selectModel(
                                  providerId: provider.id,
                                  modelId: model.id,
                                  projectId: project?.id,
                                );
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
                                    if (isSelected || isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        color: isSelected
                                            ? AppTheme.accent
                                            : AppTheme.surfaceVariant,
                                        child: Text(
                                          isSelected
                                              ? 'SET $scopeLabel'
                                              : 'ACTIVE',
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : AppTheme.textSecondary,
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

    final queryTokens = _tokenize(_query);
    if (queryTokens.isEmpty) {
      return providers
          .map((p) => _FilteredProvider(provider: p, models: p.models))
          .toList();
    }

    final modelEntries = <_ModelEntry>[];
    for (final provider in providers) {
      for (final model in provider.models) {
        modelEntries.add(_ModelEntry(provider: provider, model: model));
      }
    }

    final docs = modelEntries
        .map(
          (entry) => _buildDocumentTokens(
            provider: entry.provider,
            model: entry.model,
          ),
        )
        .toList();

    final scores = _bm25Scores(queryTokens, docs);

    final grouped = <String, List<_ScoredModel>>{};
    for (var i = 0; i < modelEntries.length; i++) {
      final entry = modelEntries[i];
      final score = scores[i];
      if (score <= 0) continue;
      grouped
          .putIfAbsent(entry.provider.id, () => [])
          .add(_ScoredModel(model: entry.model, score: score));
    }

    final results = <_FilteredProvider>[];
    for (final provider in providers) {
      final scoredModels = grouped[provider.id];
      if (scoredModels == null || scoredModels.isEmpty) continue;
      scoredModels.sort((a, b) => b.score.compareTo(a.score));
      results.add(
        _FilteredProvider(
          provider: provider,
          models: scoredModels.map((m) => m.model).toList(),
        ),
      );
    }

    results.sort((a, b) {
      final aScore = _providerBestScore(a.provider.id, grouped);
      final bScore = _providerBestScore(b.provider.id, grouped);
      return bScore.compareTo(aScore);
    });

    return results;
  }

  List<String> _tokenize(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  List<String> _buildDocumentTokens({
    required ProviderModel provider,
    required ProviderModelInfo model,
  }) {
    final tokens = <String>[];
    final modelNameTokens = _tokenize(model.name ?? model.id);
    final modelIdTokens = _tokenize(model.id);
    final providerNameTokens = _tokenize(provider.name ?? provider.id);
    final providerIdTokens = _tokenize(provider.id);

    tokens.addAll(modelNameTokens);
    tokens.addAll(modelNameTokens);
    tokens.addAll(modelIdTokens);
    tokens.addAll(providerNameTokens);
    tokens.addAll(providerIdTokens);

    return tokens;
  }

  List<double> _bm25Scores(List<String> queryTokens, List<List<String>> docs) {
    final docCount = docs.length;
    if (docCount == 0) return [];

    final df = <String, int>{};
    var totalLength = 0;
    for (final doc in docs) {
      totalLength += doc.length;
      final seen = <String>{};
      for (final token in doc) {
        if (seen.add(token)) {
          df[token] = (df[token] ?? 0) + 1;
        }
      }
    }

    final avgdl = totalLength / docCount;
    const k1 = 1.2;
    const b = 0.75;

    final scores = List<double>.filled(docCount, 0);
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (doc.isEmpty) continue;

      final tf = <String, int>{};
      for (final token in doc) {
        tf[token] = (tf[token] ?? 0) + 1;
      }

      var score = 0.0;
      for (final token in queryTokens) {
        final termDf = df[token];
        if (termDf == null) continue;
        final termTf = tf[token] ?? 0;
        if (termTf == 0) continue;
        final idf = (docCount - termDf + 0.5) / (termDf + 0.5) + 1.0;
        final denom = termTf + k1 * (1 - b + b * (doc.length / avgdl));
        score += (termTf * (k1 + 1) / denom) * idf;
      }

      scores[i] = score;
    }

    return scores;
  }

  double _providerBestScore(
    String providerId,
    Map<String, List<_ScoredModel>> grouped,
  ) {
    final models = grouped[providerId];
    if (models == null || models.isEmpty) return 0;
    return models.map((m) => m.score).reduce((a, b) => a > b ? a : b);
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
