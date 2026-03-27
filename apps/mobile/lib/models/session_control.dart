class SessionModeOption {
  final String id;
  final String name;
  final String? description;

  const SessionModeOption({
    required this.id,
    required this.name,
    this.description,
  });

  factory SessionModeOption.fromJson(Map<String, dynamic> json) {
    return SessionModeOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}

class SessionConfigChoice {
  final String value;
  final String name;
  final String? description;
  final String? group;

  const SessionConfigChoice({
    required this.value,
    required this.name,
    this.description,
    this.group,
  });
}

class SessionConfigOptionItem {
  final String id;
  final String name;
  final String? category;
  final String? description;
  final String type;
  final String? currentValue;
  final bool? currentBoolValue;
  final List<SessionConfigChoice> choices;

  const SessionConfigOptionItem({
    required this.id,
    required this.name,
    required this.type,
    this.category,
    this.description,
    this.currentValue,
    this.currentBoolValue,
    this.choices = const [],
  });

  bool get isBoolean => type == 'boolean';
  bool get isSelect => type == 'select';

  factory SessionConfigOptionItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'select';
    final optionsRaw = json['options'];
    final choices = <SessionConfigChoice>[];

    if (optionsRaw is List) {
      for (final item in optionsRaw) {
        if (item is! Map) {
          continue;
        }
        final object = Map<String, dynamic>.from(item);
        final groupName = object['name'] as String?;
        final groupedOptions = object['options'];
        if (groupedOptions is List && object.containsKey('group')) {
          for (final grouped in groupedOptions) {
            if (grouped is! Map) {
              continue;
            }
            final option = Map<String, dynamic>.from(grouped);
            final value = option['value']?.toString() ?? '';
            if (value.isEmpty) {
              continue;
            }
            choices.add(
              SessionConfigChoice(
                value: value,
                name: option['name']?.toString() ?? value,
                description: option['description']?.toString(),
                group: groupName,
              ),
            );
          }
          continue;
        }

        final value = object['value']?.toString() ?? '';
        if (value.isEmpty) {
          continue;
        }
        choices.add(
          SessionConfigChoice(
            value: value,
            name: object['name']?.toString() ?? value,
            description: object['description']?.toString(),
          ),
        );
      }
    }

    return SessionConfigOptionItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: type,
      category: json['category'] as String?,
      description: json['description'] as String?,
      currentValue: type == 'select' ? json['currentValue']?.toString() : null,
      currentBoolValue: type == 'boolean' ? json['currentValue'] as bool? : null,
      choices: choices,
    );
  }

  SessionConfigChoice? get selectedChoice {
    final current = currentValue;
    if (current == null || current.isEmpty) {
      return null;
    }
    for (final choice in choices) {
      if (choice.value == current) {
        return choice;
      }
    }
    return null;
  }
}

class SessionControl {
  final String sessionId;
  final String? currentModeId;
  final List<SessionModeOption> modes;
  final List<SessionConfigOptionItem> configOptions;

  const SessionControl({
    required this.sessionId,
    this.currentModeId,
    this.modes = const [],
    this.configOptions = const [],
  });

  factory SessionControl.fromJson(Map<String, dynamic> json) {
    final modesRaw = json['modes'];
    final availableModes =
        modesRaw is Map<String, dynamic>
        ? (modesRaw['availableModes'] as List<dynamic>? ?? const [])
        : const <dynamic>[];
    return SessionControl(
      sessionId: json['sessionId'] as String? ?? '',
      currentModeId: modesRaw is Map<String, dynamic>
          ? modesRaw['currentModeId'] as String?
          : null,
      modes: availableModes
          .map((item) => SessionModeOption.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      configOptions: (json['configOptions'] as List<dynamic>? ?? const [])
          .map(
            (item) => SessionConfigOptionItem.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
  }

  SessionConfigOptionItem? optionByCategory(String category) {
    for (final option in configOptions) {
      if (option.category == category) {
        return option;
      }
    }
    return null;
  }
}
