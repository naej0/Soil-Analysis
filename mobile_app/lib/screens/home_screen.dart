import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';
import 'admin_dashboard_screen.dart';
import 'climate_advisory_screen.dart';
import 'gis_mapping_screen.dart';
import 'land_lease_screen.dart';
import 'productivity_screen.dart';
import 'soil_analysis_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
    required this.onLogout,
  });

  final ApiService apiService;
  final UserModel currentUser;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final isAdmin = (currentUser.role ?? '').trim().toLowerCase() == 'admin';
    final modules = <_ModuleEntry>[
      _ModuleEntry(
        title: 'Soil Analysis',
        subtitle: 'Identify soil type from a soil photo and review field guidance.',
        icon: Icons.photo_camera_back_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SoilAnalysisScreen(apiService: apiService),
            ),
          );
        },
      ),
      _ModuleEntry(
        title: 'GIS Mapping',
        subtitle: 'View soil zones, location details, and crop guidance on the map.',
        icon: Icons.map_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GISMappingScreen(apiService: apiService),
            ),
          );
        },
      ),
      _ModuleEntry(
        title: 'Climate Advisory',
        subtitle: 'Check today\'s planting conditions and field weather for your area.',
        icon: Icons.cloud_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClimateAdvisoryScreen(apiService: apiService),
            ),
          );
        },
      ),
      _ModuleEntry(
        title: 'Land Lease Marketplace',
        subtitle: 'Browse or post agricultural land lease listings.',
        icon: Icons.storefront_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LandLeaseScreen(apiService: apiService),
            ),
          );
        },
      ),
      _ModuleEntry(
        title: 'Productivity Monitor',
        subtitle: 'Save harvest results and review productivity history.',
        icon: Icons.insights_outlined,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductivityScreen(
                apiService: apiService,
                currentUser: currentUser,
              ),
            ),
          );
        },
      ),
      if (isAdmin)
        _ModuleEntry(
          title: 'Admin Dashboard',
          subtitle: 'Open admin tools while keeping access to the normal farm modules.',
          icon: Icons.admin_panel_settings_outlined,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminDashboardScreen(
                  apiService: apiService,
                  currentUser: currentUser,
                  onLogout: onLogout,
                ),
              ),
            );
          },
        ),
    ];

    final crossAxisCount = MediaQuery.of(context).size.width > 700 ? 3 : 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surigao City Farm Dashboard'),
        actions: [
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'Welcome Back',
                icon: Icons.person_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentUser.fullName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(currentUser.email),
                    const SizedBox(height: 8),
                    Text(
                      'Open a module below to check soil, planting conditions, lease listings, and farm productivity.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Farm Support Modules',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: modules.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final module = modules[index];
                  return _ModuleCard(module: module);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleEntry {
  const _ModuleEntry({
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

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final _ModuleEntry module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: module.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  module.icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                module.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  module.subtitle,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
