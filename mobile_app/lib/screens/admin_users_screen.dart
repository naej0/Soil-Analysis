import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
    this.restrictedOnly = false,
  });

  final ApiService apiService;
  final UserModel currentUser;
  final bool restrictedOnly;

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

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? 0}') ?? 0;
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

  List<Map<String, dynamic>> get _visibleUsers {
    if (!widget.restrictedOnly) {
      return _users;
    }

    return _users.where((user) => _asBool(user['is_restricted'])).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenTitle =
        widget.restrictedOnly ? 'Restricted Users' : 'Admin Users';

    if (_isLoading && _users.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(screenTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
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

            InfoCard(
              title: widget.restrictedOnly ? 'Restricted Users' : 'Read Only',
              icon: widget.restrictedOnly
                  ? Icons.block_outlined
                  : Icons.visibility_outlined,
              child: Text(
                widget.restrictedOnly
                    ? 'This admin view only shows users who are currently restricted.'
                    : 'This admin view lists current user accounts and moderation status without changing user records.',
              ),
            ),

            InfoCard(
              title: widget.restrictedOnly
                  ? 'Restricted User Count'
                  : 'User Count',
              icon: Icons.people_outline,
              child: Text('Total records loaded: ${_visibleUsers.length}'),
            ),

            if (_visibleUsers.isEmpty)
              InfoCard(
                title: widget.restrictedOnly
                    ? 'No Restricted Users'
                    : 'No Users',
                icon: Icons.people_outline,
                child: Text(
                  widget.restrictedOnly
                      ? 'No restricted user records are available right now.'
                      : 'No user records are available right now.',
                ),
              ),

            for (final user in _visibleUsers)
              InfoCard(
                title: _display(user['full_name']),
                icon: Icons.person_outline,
                child: Builder(
                  builder: (context) {
                    final userId = _asInt(user['id']);
                    final isRestricted = _asBool(user['is_restricted']);
                    final isActive = user['is_active'] == null
                        ? true
                        : _asBool(user['is_active']);
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
                            Chip(
                              label: Text('Role: ${_display(user['role'])}'),
                            ),
                            Chip(
                              label: Text(
                                isRestricted
                                    ? 'Restricted'
                                    : (isActive ? 'Active' : 'Inactive'),
                              ),
                            ),
                            if (isSelf)
                              const Chip(
                                label: Text('Current Admin'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Created: ${_formatDate(user['created_at'])}'),
                        const SizedBox(height: 4),
                        Text('Updated: ${_formatDate(user['updated_at'])}'),
                        if (isRestricted ||
                            _display(user['restriction_reason']) != 'N/A') ...[
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