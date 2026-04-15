class AssistantChatRequest {
  const AssistantChatRequest({
    required this.question,
    this.context,
    this.history,
  });

  final String question;
  final Map<String, dynamic>? context;
  final List<Map<String, dynamic>>? history;

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      if (context != null && context!.isNotEmpty) 'context': context,
      if (history != null && history!.isNotEmpty) 'history': history,
    };
  }
}

class AssistantChatResponse {
  const AssistantChatResponse({
    required this.status,
    required this.answer,
    required this.matchedTopics,
    this.usedContext,
    required this.message,
  });

  final String status;
  final String answer;
  final List<String> matchedTopics;
  final Map<String, dynamic>? usedContext;
  final String message;

  factory AssistantChatResponse.fromJson(Map<String, dynamic> json) {
    return AssistantChatResponse(
      status: json['status'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      matchedTopics: (json['matched_topics'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
      usedContext: _asNullableMap(json['used_context']),
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'answer': answer,
      'matched_topics': matchedTopics,
      if (usedContext != null && usedContext!.isNotEmpty)
        'used_context': usedContext,
      'message': message,
    };
  }
}

Map<String, dynamic>? _asNullableMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}
