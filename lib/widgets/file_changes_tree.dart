import 'package:flutter/material.dart';

import 'package:flutter/material.dart';

import '../models/file_diff.dart';
import '../theme/app_theme.dart';
import '../constants/file_icons.dart';

class FileChangesTree extends StatelessWidget {
  final List<FileDiff> diffs;

  const FileChangesTree({super.key, required this.diffs});

  @override
  Widget build(BuildContext context) {
    final tree = _buildTree(diffs);
    if (tree.isEmpty) {
      return const Center(
        child: Text(
          'No file changes',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: tree.map((node) => _TreeNodeWidget(node: node)).toList(),
    );
  }

  List<_TreeNode> _buildTree(List<FileDiff> diffs) {
    final root = _TreeNode(name: '', path: '');
    for (final diff in diffs) {
      final normalized = diff.file.trim();
      if (normalized.isEmpty) continue;
      final segments = normalized.split('/');
      var current = root;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (segment.isEmpty) continue;
        current = current.children.putIfAbsent(
          segment,
          () => _TreeNode(
            name: segment,
            path: current.path.isEmpty ? segment : '${current.path}/$segment',
          ),
        );
      }
      current.diff = diff;
    }

    return root.children.values.toList();
  }
}

class _TreeNode {
  final String name;
  final String path;
  final Map<String, _TreeNode> children = {};
  FileDiff? diff;

  _TreeNode({required this.name, required this.path});

  bool get isFile => diff != null || children.isEmpty;
}

class _TreeNodeWidget extends StatefulWidget {
  final _TreeNode node;

  const _TreeNodeWidget({required this.node});

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final children = node.children.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (node.isFile) {
      return _FileRow(diff: node.diff!, name: node.name);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.folder,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  node.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children
                  .map((child) => _TreeNodeWidget(node: child))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final FileDiff diff;
  final String name;

  const _FileRow({required this.diff, required this.name});

  @override
  Widget build(BuildContext context) {
    final status = diff.status?.toUpperCase();
    final additions = diff.additions;
    final deletions = diff.deletions;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            getIconForExtension(name.split('.').last),
            size: 14,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (status != null && status.isNotEmpty) ...[
            Text(
              status,
              style: const TextStyle(color: AppTheme.info, fontSize: 9),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '+$additions',
            style: const TextStyle(color: AppTheme.success, fontSize: 9),
          ),
          const SizedBox(width: 4),
          Text(
            '-$deletions',
            style: const TextStyle(color: AppTheme.error, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
