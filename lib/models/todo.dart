class Todo {
  final String content;
  final String status;
  final String priority;
  final String id;

  Todo({
    required this.content,
    required this.status,
    required this.priority,
    required this.id,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      content: json['content'] as String,
      status: json['status'] as String,
      priority: json['priority'] as String,
      id: json['id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'status': status,
      'priority': priority,
      'id': id,
    };
  }
}
