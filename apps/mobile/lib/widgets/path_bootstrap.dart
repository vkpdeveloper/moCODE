import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class PathBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const PathBootstrap({super.key, required this.child});

  @override
  ConsumerState<PathBootstrap> createState() => _PathBootstrapState();
}

class _PathBootstrapState extends ConsumerState<PathBootstrap> {
  @override
  void initState() {
    super.initState();
    if (ref.read(settingsProvider).hasSelectedDevice) {
      ref.read(pathInfoProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
