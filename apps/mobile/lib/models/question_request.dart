class QuestionOption {
  final String label;
  final String description;

  QuestionOption({required this.label, required this.description});

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'label': label, 'description': description};
  }
}

class QuestionInfo {
  final String id;
  final String question;
  final String header;
  final List<QuestionOption> options;
  final bool? multiple;
  final bool? custom;
  final bool? secret;

  QuestionInfo({
    required this.id,
    required this.question,
    required this.header,
    required this.options,
    this.multiple,
    this.custom,
    this.secret,
  });

  factory QuestionInfo.fromJson(Map<String, dynamic> json) {
    return QuestionInfo(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      header: json['header'] as String? ?? '',
      options:
          (json['options'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(QuestionOption.fromJson)
              .toList() ??
          [],
      multiple: json['multiple'] as bool?,
      custom: json['custom'] as bool?,
      secret: json['secret'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'header': header,
      'options': options.map((option) => option.toJson()).toList(),
      if (multiple != null) 'multiple': multiple,
      if (custom != null) 'custom': custom,
      if (secret != null) 'secret': secret,
    };
  }
}

class QuestionToolInfo {
  final String messageID;
  final String callID;

  QuestionToolInfo({required this.messageID, required this.callID});

  factory QuestionToolInfo.fromJson(Map<String, dynamic> json) {
    return QuestionToolInfo(
      messageID: json['messageID'] as String? ?? '',
      callID: json['callID'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'messageID': messageID, 'callID': callID};
  }
}

class QuestionRequest {
  final String id;
  final String sessionID;
  final List<QuestionInfo> questions;
  final QuestionToolInfo? tool;

  QuestionRequest({
    required this.id,
    required this.sessionID,
    required this.questions,
    this.tool,
  });

  factory QuestionRequest.fromJson(Map<String, dynamic> json) {
    return QuestionRequest(
      id: json['id'] as String? ?? '',
      sessionID: json['sessionID'] as String? ?? '',
      questions:
          (json['questions'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(QuestionInfo.fromJson)
              .toList() ??
          [],
      tool: json['tool'] is Map<String, dynamic>
          ? QuestionToolInfo.fromJson(json['tool'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'questions': questions.map((question) => question.toJson()).toList(),
      if (tool != null) 'tool': tool!.toJson(),
    };
  }
}
