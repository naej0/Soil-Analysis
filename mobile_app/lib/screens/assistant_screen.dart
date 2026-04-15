import 'package:flutter/material.dart';

import '../models/assistant_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/info_card.dart';

class AssistantScreen extends StatefulWidget {
  AssistantScreen({
    super.key,
    ApiService? apiService,
    this.embedded = false,
    this.onMinimize,
  }) : apiService = apiService ?? ApiService();

  final ApiService apiService;
  final bool embedded;
  final VoidCallback? onMinimize;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const List<String> _suggestedQuestions = [
    'What crops are suitable for Loam?',
    'What fertilizer is good for Clay soil?',
    'Is today good for planting?',
    'How can I improve low productivity soil?',
    'What does Silty Clay mean?',
  ];

  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AssistantUiMessage> _messages = [];

  bool _isSending = false;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitQuestion([String? suggestedQuestion]) async {
    if (_isSending) {
      return;
    }

    final rawQuestion = suggestedQuestion ?? _questionController.text;
    final question = rawQuestion.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type a farm question first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final request = AssistantChatRequest(
      question: question,
      history: _buildHistory(),
    );

    setState(() {
      _messages.add(_AssistantUiMessage.user(question));
      _questionController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response = await widget.apiService.askAssistant(
        question: request.question,
        context: request.context,
        history: request.history,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(_AssistantUiMessage.assistant(response));
        _isSending = false;
      });
      _scrollToBottom();
    } on ApiException {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _AssistantUiMessage.assistantError(
            'I could not reach the farm assistant right now. Please try again.',
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _AssistantUiMessage.assistantError(
            'I could not reach the farm assistant right now. Please try again.',
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  List<Map<String, dynamic>>? _buildHistory() {
    if (_messages.isEmpty) {
      return null;
    }

    final history = _messages
        .map(
          (message) => {
            'role': message.isUser ? 'user' : 'assistant',
            'content': message.text,
          },
        )
        .toList(growable: false);

    return history.isEmpty ? null : history;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildScreenBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: !widget.embedded,
      bottom: !widget.embedded,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (widget.embedded) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.support_agent_outlined,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Farm Assistant',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onMinimize,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            InfoCard(
              title: 'Farm Assistant',
              icon: Icons.support_agent_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask about soil, crops, fertilizer, planting, or productivity.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Short, practical replies will appear here in a clean chat view based on the farm assistant backend.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _messages.isEmpty
                    ? _AssistantEmptyState(
                        suggestedQuestions: _suggestedQuestions,
                        onSuggestionTap: _submitQuestion,
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isSending ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index >= _messages.length) {
                            return const _AssistantLoadingBubble();
                          }

                          return _AssistantMessageBubble(
                            message: _messages[index],
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextField(
                      controller: _questionController,
                      label: 'Type your farm question',
                      maxLines: 3,
                      prefixIcon: Icons.edit_outlined,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Example: What crops are suitable for Loam?',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      label: 'Send Question',
                      icon: Icons.send_rounded,
                      isLoading: _isSending,
                      onPressed: () {
                        _submitQuestion();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildScreenBody(context);

    if (widget.embedded) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm Assistant'),
      ),
      body: content,
    );
  }
}

class _AssistantEmptyState extends StatelessWidget {
  const _AssistantEmptyState({
    required this.suggestedQuestions,
    required this.onSuggestionTap,
  });

  final List<String> suggestedQuestions;
  final Future<void> Function(String question) onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.forum_outlined,
                color: colorScheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ask your first farm question.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try one of the suggested questions below to get a short farm-focused reply.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Suggested questions',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestedQuestions
                  .map(
                    (question) => ActionChip(
                      avatar: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(question),
                      onPressed: () {
                        onSuggestionTap(question);
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantLoadingBubble extends StatelessWidget {
  const _AssistantLoadingBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.65),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Preparing farm assistant guidance...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  const _AssistantMessageBubble({
    required this.message,
  });

  final _AssistantUiMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest.withOpacity(0.55);
    final textColor =
        isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    final secondaryTextColor = isUser
        ? colorScheme.onPrimaryContainer.withOpacity(0.82)
        : colorScheme.onSurfaceVariant;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 18),
            ),
            border: Border.all(
              color: isUser
                  ? colorScheme.primary.withOpacity(0.18)
                  : colorScheme.outlineVariant.withOpacity(0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'You' : 'Farm Assistant',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      height: 1.4,
                    ),
              ),
              if (!isUser && message.matchedTopics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: message.matchedTopics
                      .map(
                        (topic) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            topic,
                            style:
                                Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (!isUser && message.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message.note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantUiMessage {
  const _AssistantUiMessage({
    required this.isUser,
    required this.text,
    this.matchedTopics = const [],
    this.note = '',
  });

  final bool isUser;
  final String text;
  final List<String> matchedTopics;
  final String note;

  factory _AssistantUiMessage.user(String text) {
    return _AssistantUiMessage(
      isUser: true,
      text: text,
    );
  }

  factory _AssistantUiMessage.assistant(AssistantChatResponse response) {
    return _AssistantUiMessage(
      isUser: false,
      text: response.answer,
      matchedTopics: response.matchedTopics,
      note: response.message,
    );
  }

  factory _AssistantUiMessage.assistantError(String text) {
    return _AssistantUiMessage(
      isUser: false,
      text: text,
    );
  }
}
