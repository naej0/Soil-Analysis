import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
  });

  final ApiService apiService;
  final UserModel currentUser;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers({bool showLoader = true}) async {
    if (mounted && (showLoader || _users.isEmpty)) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final users = await widget.apiService.getAdminUsers(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _isLoading = false;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    }
  }

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'N/A' : text;
  }

  String _formatDate(dynamic value) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.isEmpty ? 'N/A' : text;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _users.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Users')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Users'),
        actions: [
          IconButton(
            onPressed: () {
              _loadUsers();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadUsers(showLoader: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const InfoCard(
              title: 'Read Only',
              icon: Icons.visibility_outlined,
              child: Text(
                'This admin view lists current user accounts and moderation status without changing user records.',
              ),
            ),
            if (_users.isEmpty)
              const InfoCard(
                title: 'No Users',
                icon: Icons.people_outline,
                child: Text('No user records are available right now.'),
              ),
            for (final user in _users)
              InfoCard(
                title: _display(user['full_name']),
                icon: Icons.person_outline,
                child: Builder(
                  builder: (context) {
                    final userId = user['id'] as int? ?? 0;
                    final isActive = user['is_active'] != false;
                    final isRestricted = user['is_restricted'] == true;
                    final isSelf = userId == widget.currentUser.id;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_display(user['email'])),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('ID $userId')),
                            Chip(label: Text('Role: ${_display(user['role'])}')),
                            Chip(
                              label: Text(
                                isRestricted
                                    ? 'Restricted'
                                    : (isActive ? 'Active' : 'Inactive'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Created: ${_formatDate(user['created_at'])}'),
                        if (isRestricted || _display(user['restriction_reason']) != 'N/A') ...[
                          const SizedBox(height: 8),
                          Text(
                            'Restriction reason: ${_display(user['restriction_reason'])}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Restricted at: ${_formatDate(user['restricted_at'])}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Restricted by: ${_display(user['restricted_by'])}',
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (isSelf)
                          Text(
                            'This is your current admin account.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
