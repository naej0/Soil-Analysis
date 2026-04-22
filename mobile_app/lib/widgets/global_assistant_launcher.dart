import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/assistant_screen.dart';
import '../services/api_service.dart';

class GlobalAssistantLauncher extends StatefulWidget {
  const GlobalAssistantLauncher({
    super.key,
    required this.child,
    required this.apiService,
    required this.navigatorKey,
  });

  final Widget child;
  final ApiService apiService;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<GlobalAssistantLauncher> createState() =>
      _GlobalAssistantLauncherState();
}

class _GlobalAssistantLauncherState extends State<GlobalAssistantLauncher> {
  bool _isAssistantOpen = false;

  Future<void> _openAssistant() async {
    if (_isAssistantOpen) {
      return;
    }

    final navigatorContext =
        widget.navigatorKey.currentState?.overlay?.context ??
            widget.navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }

    setState(() {
      _isAssistantOpen = true;
    });

    await showModalBottomSheet<void>(
      context: navigatorContext,
      useRootNavigator: true,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.18),
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final viewInsets = mediaQuery.viewInsets.bottom;
        final safeTop = mediaQuery.padding.top;
        final safeBottom = mediaQuery.padding.bottom;
        final maxWidth = math.min(mediaQuery.size.width - 24, 420.0);
        final maxHeight = mediaQuery.size.height - safeTop - viewInsets - 24;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(12, 12, 12, safeBottom + viewInsets + 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: _AssistantPanel(
                apiService: widget.apiService,
                onMinimize: () {
                  Navigator.of(sheetContext).maybePop();
                },
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isAssistantOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.padding.bottom;
    final safeRight = mediaQuery.padding.right;
    const horizontalMargin = 16.0;
    const verticalMargin = 16.0;
    final launcherBottom = verticalMargin + math.max(safeBottom, bottomInset);
    final launcherRight = horizontalMargin + safeRight;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          right: launcherRight,
          bottom: launcherBottom,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            scale: _isAssistantOpen ? 0.92 : 1,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _isAssistantOpen ? 0 : 1,
              child: IgnorePointer(
                ignoring: _isAssistantOpen,
                child: _AssistantBubble(
                  onTap: _openAssistant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 10,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.support_agent_outlined,
                size: 20,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Assistant',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel({
    required this.apiService,
    required this.onMinimize,
  });

  final ApiService apiService;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 20,
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: AssistantScreen(
        apiService: apiService,
        embedded: true,
        onMinimize: onMinimize,
      ),
    );
  }
}
