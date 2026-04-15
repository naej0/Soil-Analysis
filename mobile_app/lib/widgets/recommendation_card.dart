import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
  });

  final RecommendationItem recommendation;

  Color _suitabilityColor(BuildContext context) {
    switch (recommendation.suitability.toLowerCase()) {
      case 'good':
      case 'high':
        return Colors.green.shade700;
      case 'moderate':
      case 'medium':
        return Colors.orange.shade700;
      case 'not ideal':
      case 'low':
        return Colors.red.shade700;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _suitabilityLabel() {
    switch (recommendation.suitability.toLowerCase()) {
      case 'good':
        return 'Good';
      case 'moderate':
      case 'medium':
        return 'Moderate';
      case 'high':
        return 'High';
      case 'not ideal':
        return 'Not Ideal';
      case 'low':
        return 'Low';
      default:
        final label = recommendation.suitability.trim();
        return label.isEmpty ? 'Info' : label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final suitabilityColor = _suitabilityColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          recommendation.cropName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            recommendation.notes?.trim().isNotEmpty == true
                ? recommendation.notes!
                : 'No additional notes provided.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: suitabilityColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: suitabilityColor.withOpacity(0.18),
            ),
          ),
          child: Text(
            _suitabilityLabel(),
            style: TextStyle(
              color: suitabilityColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
