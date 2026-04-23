import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';
import 'admin_leases_screen.dart';
import 'admin_productivity_screen.dart';
import 'admin_soil_logs_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
    required this.onLogout,
  });

  final ApiService apiService;
  final UserModel currentUser;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _dashboard;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final dashboard = await widget.apiService.getAdminDashboard(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _openUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminUsersScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

Future <void> _openRestrictedUsers() async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminUsersScreen(
        apiService: widget.apiService,
        currentUser: widget.currentUser,
        restrictedOnly: true,
      ),
    ),
  );
}

  Future<void> _openLeases() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminLeasesScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openProductivity() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminProductivityScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openSoilLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminSoilLogsScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Map<String, dynamic> _section(String key) {
    final section = _dashboard?[key];
    if (section is Map<String, dynamic>) {
      return section;
    }
    if (section is Map) {
      return Map<String, dynamic>.from(section);
    }
    return <String, dynamic>{};
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  int _metricCount({
    required String sectionKey,
    required String nestedKey,
    List<String> flatFallbackKeys = const [],
  }) {
    final section = _section(sectionKey);

    if (section.containsKey(nestedKey)) {
      return _asInt(section[nestedKey]);
    }

    final dashboard = _dashboard;
    if (dashboard != null) {
      for (final key in flatFallbackKeys) {
        if (dashboard.containsKey(key)) {
          return _asInt(dashboard[key]);
        }
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalUsers = _metricCount(
      sectionKey: 'users',
      nestedKey: 'total',
      flatFallbackKeys: const ['total_users'],
    );

    final restrictedUsers = _metricCount(
      sectionKey: 'users',
      nestedKey: 'restricted',
      flatFallbackKeys: const ['restricted_users'],
    );

    final activeLeases = _metricCount(
      sectionKey: 'leases',
      nestedKey: 'active',
      flatFallbackKeys: const ['active_lease_listings'],
    );

    final flaggedLeases = _metricCount(
      sectionKey: 'leases',
      nestedKey: 'flagged',
      flatFallbackKeys: const [
        'flagged_lease_listings',
        'total_flagged_leases',
      ],
    );

    final totalProductivity = _metricCount(
      sectionKey: 'productivity',
      nestedKey: 'total_records',
      flatFallbackKeys: const ['total_productivity_records'],
    );

    final totalSoilLogs = _metricCount(
      sectionKey: 'soil_analysis_logs',
      nestedKey: 'total_logs',
      flatFallbackKeys: const [
        'total_soil_analyses',
        'total_soil_analysis_logs',
      ],
    );

    final metrics = <_AdminMetric>[
      _AdminMetric(
        label: 'Users',
        value: '$totalUsers',
        icon: Icons.people_outline,
        onTap: _openUsers,
      ),
      _AdminMetric(
        label: 'Restricted Users',
        value: '$restrictedUsers',
        icon: Icons.block_outlined,
        onTap: _openRestrictedUsers,
      ),
      _AdminMetric(
        label: 'Active Leases',
        value: '$activeLeases',
        icon: Icons.storefront_outlined,
        onTap: _openLeases,
      ),
      _AdminMetric(
        label: 'Flagged Leases',
        value: '$flaggedLeases',
        icon: Icons.flag_outlined,
        onTap: _openLeases,
      ),
      _AdminMetric(
        label: 'Productivity Records',
        value: '$totalProductivity',
        icon: Icons.insights_outlined,
        onTap: _openProductivity,
      ),
      _AdminMetric(
        label: 'Soil Logs',
        value: '$totalSoilLogs',
        icon: Icons.history_edu_outlined,
        onTap: _openSoilLogs,
      ),
    ];

    final modules = <_AdminModuleEntry>[
      _AdminModuleEntry(
        title: 'Users',
        subtitle: 'View registered accounts and current moderation status.',
        icon: Icons.manage_accounts_outlined,
        onTap: _openUsers,
      ),
      _AdminModuleEntry(
        title: 'Leases',
        subtitle: 'View lease listings and their current review state.',
        icon: Icons.fact_check_outlined,
        onTap: _openLeases,
      ),
      _AdminModuleEntry(
        title: 'Productivity',
        subtitle: 'Review submitted productivity records across users.',
        icon: Icons.bar_chart_outlined,
        onTap: _openProductivity,
      ),
      _AdminModuleEntry(
        title: 'Soil Logs',
        subtitle: 'Review soil analysis log history from the backend.',
        icon: Icons.analytics_outlined,
        onTap: _openSoilLogs,
      ),
    ];

    if (_isLoading && _dashboard == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _dashboard == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadDashboard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

final width = MediaQuery.of(context).size.width;

final metricCrossAxisCount = width >= 900 ? 3 : 2;
final metricAspectRatio = width >= 900
    ? 2.1
    : width >= 600
        ? 1.7
        : 1.35;

final moduleCrossAxisCount = width >= 1100
    ? 3
    : width >= 700
        ? 2
        : 1;

final moduleAspectRatio = moduleCrossAxisCount == 1 ? 1.85 : 1.45;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
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
              title: 'Administrator',
              icon: Icons.admin_panel_settings_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currentUser.fullName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(widget.currentUser.email),
                  const SizedBox(height: 8),
                  Text(
                    'Use the admin tools below to review users, leases, productivity records, and soil analysis logs.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            InfoCard(
              title: 'System Overview',
              icon: Icons.dashboard_outlined,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: metricCrossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: metricAspectRatio,
                ),
                itemBuilder: (context, index) {
                  return _AdminMetricCard(metric: metrics[index]);
                },
              ),
            ),
            Text(
              'Admin Modules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modules.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: moduleCrossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: moduleAspectRatio,
              ),
              itemBuilder: (context, index) {
                return _AdminModuleCard(module: modules[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMetric {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.metric});

  final _AdminMetric metric;



  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: metric.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(metric.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminModuleEntry {
  const _AdminModuleEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _AdminModuleCard extends StatelessWidget {
  const _AdminModuleCard({required this.module});

  final _AdminModuleEntry module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: module.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  module.icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                module.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
             Text(
  module.subtitle,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
),
            ],
          ),
        ),
      ),
    );
  }
}