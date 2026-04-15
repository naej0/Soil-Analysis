import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/info_card.dart';
import 'image_analysis_screen.dart';

class SoilAnalysisScreen extends StatelessWidget {
  const SoilAnalysisScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soil Analysis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'Soil Photo Analysis',
                icon: Icons.image_search_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload a soil photo to identify the soil type and review crop recommendations and field guidance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Supported soil types',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...ApiConfig.supportedSoilTypes.map(
                      (soilType) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('- $soilType'),
                      ),
                    ),
                  ],
                ),
              ),
              CustomButton(
                label: 'Start Soil Analysis',
                icon: Icons.photo_library_outlined,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ImageAnalysisScreen(apiService: apiService),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
