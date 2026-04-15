import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/dashboard_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/info_card.dart';

class ClimateAdvisoryScreen extends StatefulWidget {
  const ClimateAdvisoryScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ClimateAdvisoryScreen> createState() => _ClimateAdvisoryScreenState();
}

class _ClimateAdvisoryScreenState extends State<ClimateAdvisoryScreen> {
  DashboardModel? _dashboard;
  ClimateCurrentModel? _climateOnly;
  bool _isLoading = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _loadClimate() async {
    setState(() {
      _isLoading = true;
      _message = null;
      _messageIsError = false;
    });

    try {
      final permissionStatus = await Permission.locationWhenInUse.request();
      if (!permissionStatus.isGranted) {
        throw const ApiException(
          'Location permission is needed to check planting conditions for your area.',
        );
      }

      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        throw const ApiException(
          'Turn on location services to check planting conditions for your area.',
        );
      }

      var geolocatorPermission = await Geolocator.checkPermission();
      if (geolocatorPermission == LocationPermission.denied) {
        geolocatorPermission = await Geolocator.requestPermission();
      }
      if (geolocatorPermission == LocationPermission.denied ||
          geolocatorPermission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Location access is not available right now for this planting check.',
        );
      }

      final position = await Geolocator.getCurrentPosition();

      try {
        final dashboard = await widget.apiService.getDashboardByLocation(
          lat: position.latitude,
          lng: position.longitude,
        );
        ClimateCurrentModel? climateFallback;
        String? message;

        if (_shouldLoadClimateFallback(dashboard)) {
          try {
            climateFallback = await widget.apiService.getClimateCurrent(
              lat: position.latitude,
              lng: position.longitude,
            );
            message =
                'Some dashboard climate details were missing, so the latest available climate values are shown where possible.';
          } on ApiException {
            message =
                'Some climate details are still unavailable for this area, but the available weather values are shown below.';
          }
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _dashboard = dashboard;
          _climateOnly = climateFallback;
          _message = message;
          _messageIsError = false;
        });
      } on ApiException {
        ClimateCurrentModel? climate;
        String message;
        bool messageIsError;

        try {
          climate = await widget.apiService.getClimateCurrent(
            lat: position.latitude,
            lng: position.longitude,
          );
          message =
              'Full dashboard details could not be loaded, but current climate conditions are shown instead.';
          messageIsError = false;
        } on ApiException {
          message =
              'Today\'s planting conditions are currently unavailable for this location. Please try again shortly.';
          messageIsError = true;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _dashboard = null;
          _climateOnly = climate;
          _message = message;
          _messageIsError = messageIsError;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.message;
        _messageIsError = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'We could not load today\'s planting conditions right now. Please try again.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  _PlantingSuitabilityResult _buildPlantingSuitability(ClimateInfo climate) {
    final rainValue = _effectiveRainValue(climate);
    final windSpeed = climate.windSpeed;
    final humidity = climate.humidity;
    final temperature = climate.temperature;
    var riskScore = 0;

    if (rainValue != null) {
      if (rainValue >= 12) {
        riskScore += 2;
      } else if (rainValue >= 5) {
        riskScore += 1;
      }
    }

    if (windSpeed != null) {
      if (windSpeed >= 25) {
        riskScore += 2;
      } else if (windSpeed >= 15) {
        riskScore += 1;
      }
    }

    if (humidity != null && humidity >= 92) {
      riskScore += 1;
    }

    if (temperature != null && (temperature < 20 || temperature > 35)) {
      riskScore += 1;
    }

    if (riskScore >= 3) {
      return _PlantingSuitabilityResult(
        status: 'Not Ideal for Planting',
        explanation: _buildNotIdealExplanation(
          rainValue: rainValue,
          windSpeed: windSpeed,
          humidity: humidity,
          temperature: temperature,
        ),
      );
    }

    if (riskScore >= 1) {
      return _PlantingSuitabilityResult(
        status: 'Moderate for Planting',
        explanation: _buildModerateExplanation(
          rainValue: rainValue,
          windSpeed: windSpeed,
          humidity: humidity,
          temperature: temperature,
        ),
      );
    }

    return _PlantingSuitabilityResult(
      status: 'Good for Planting',
      explanation: _buildGoodExplanation(
        rainValue: rainValue,
        windSpeed: windSpeed,
        humidity: humidity,
        temperature: temperature,
      ),
    );
  }

  String _buildGoodExplanation({
    required double? rainValue,
    required double? windSpeed,
    required double? humidity,
    required double? temperature,
  }) {
    final notes = <String>[];

    if (rainValue != null) {
      notes.add('rain is light at ${_formatNumericValue(rainValue)} mm');
    }
    if (windSpeed != null) {
      notes.add('wind is gentle at ${_formatNumericValue(windSpeed)} km/h');
    }
    if (temperature != null) {
      notes.add('temperature is around ${_formatNumericValue(temperature)} deg C');
    }

    if (notes.isEmpty) {
      return 'Available weather conditions look steady today, so planting appears favorable.';
    }

    return 'Conditions look steady today. ${_joinNotes(notes.take(2).toList())}, which supports planting in most fields.';
  }

  String _buildModerateExplanation({
    required double? rainValue,
    required double? windSpeed,
    required double? humidity,
    required double? temperature,
  }) {
    final notes = <String>[];

    if (rainValue != null && rainValue >= 5) {
      notes.add('rain may reach about ${_formatNumericValue(rainValue)} mm');
    }
    if (windSpeed != null && windSpeed >= 15) {
      notes.add('wind may reach about ${_formatNumericValue(windSpeed)} km/h');
    }
    if (humidity != null && humidity >= 92) {
      notes.add('air moisture is quite high');
    }
    if (temperature != null && (temperature < 20 || temperature > 35)) {
      notes.add('temperature is a bit outside the comfortable range');
    }

    if (notes.isEmpty) {
      return 'Planting may still be possible today, but one condition looks slightly borderline.';
    }

    return 'Planting may still be possible today, but ${_joinNotes(notes.take(2).toList())}. Field timing and care will matter.';
  }

  String _buildNotIdealExplanation({
    required double? rainValue,
    required double? windSpeed,
    required double? humidity,
    required double? temperature,
  }) {
    final notes = <String>[];

    if (rainValue != null && rainValue >= 12) {
      notes.add('rain is high at about ${_formatNumericValue(rainValue)} mm');
    }
    if (windSpeed != null && windSpeed >= 25) {
      notes.add('wind is strong at about ${_formatNumericValue(windSpeed)} km/h');
    }
    if (humidity != null && humidity >= 92) {
      notes.add('air moisture is very high');
    }
    if (temperature != null && (temperature < 20 || temperature > 35)) {
      notes.add('temperature is less favorable for planting');
    }

    if (notes.isEmpty) {
      return 'Conditions look unstable today, so waiting a bit before planting may be safer.';
    }

    return 'It may be better to delay planting today because ${_joinNotes(notes.take(2).toList())}.';
  }

  String _joinNotes(List<String> notes) {
    if (notes.isEmpty) {
      return '';
    }
    if (notes.length == 1) {
      return notes.first;
    }
    return '${notes[0]} and ${notes[1]}';
  }

  double? _effectiveRainValue(ClimateInfo climate) {
    final rain = climate.rain;
    final precipitation = climate.precipitation;

    if (rain == null && precipitation == null) {
      return null;
    }

    return math.max(rain ?? 0, precipitation ?? 0).toDouble();
  }

  Color _suitabilityColor(BuildContext context, String status) {
    switch (status) {
      case 'Good for Planting':
        return Colors.green.shade700;
      case 'Moderate for Planting':
        return Colors.orange.shade700;
      case 'Not Ideal for Planting':
        return Colors.red.shade700;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _messageColor(BuildContext context) {
    return _messageIsError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSummary(
    BuildContext context,
    LocationInfo location,
    ClimateInfo climate,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final locationParts = <String>[];

    if (location.barangay != null && location.barangay!.trim().isNotEmpty) {
      locationParts.add(location.barangay!.trim());
    }
    if (location.lat != 0 || location.lng != 0) {
      locationParts.add(
        '${_formatCoordinate(location, location.lat)}, ${_formatCoordinate(location, location.lng)}',
      );
    }
    if (climate.time?.trim().isNotEmpty ?? false) {
      locationParts.add('Updated: ${_formatTimestamp(climate.time)}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.12),
        ),
      ),
      child: Text(
        locationParts.isEmpty
            ? 'Current area'
            : locationParts.join(' \u2022 '),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final dashboardLocation = dashboard?.location;
    final dashboardClimate = dashboard?.climate;
    final location = _hasLocationData(dashboardLocation)
        ? dashboardLocation
        : (_climateOnly?.location ?? dashboardLocation);
    final climate = _hasClimateData(dashboardClimate)
        ? dashboardClimate
        : (_climateOnly?.climate ?? dashboardClimate);
    final advisoryItems = (dashboard?.advisory ?? <String>[])
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final plantingSuitability = climate != null && _hasClimateData(climate)
        ? _buildPlantingSuitability(climate)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Climate Advisory')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'Planting Advisory',
                icon: Icons.cloud_queue_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Check today\'s planting conditions for your current location and review simple field guidance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      label: 'Check Today\'s Conditions',
                      icon: Icons.refresh,
                      isLoading: _isLoading,
                      onPressed: _loadClimate,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          'Checking your location and loading the latest planting weather for your area...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                    if (!_isLoading && location == null && climate == null && _message == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'No planting check yet. Tap the button above to load today\'s weather-based planting guidance.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        style: TextStyle(color: _messageColor(context)),
                      ),
                    ],
                  ],
                ),
              ),
              if (location != null && climate != null && plantingSuitability != null)
                InfoCard(
                  title: 'Planting Suitability Today',
                  icon: Icons.agriculture_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withOpacity(0.9),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(0.12),
                                ),
                              ),
                              child: Text(
                                'Today\'s planting outlook',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              plantingSuitability.status,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _suitabilityColor(
                                      context,
                                      plantingSuitability.status,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              plantingSuitability.explanation,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'This result uses the currently loaded rain, wind, temperature, and humidity values only.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (location != null && climate != null)
                InfoCard(
                  title: 'Today\'s Field Weather',
                  icon: Icons.thermostat_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Use these values to support today\'s planting decision for your current area.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildLocationSummary(context, location, climate),
                      const SizedBox(height: 12),
                      if (!_hasLocationData(location) || !_hasClimateData(climate)) ...[
                        Text(
                          _buildConditionsFallbackMessage(location, climate),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 360;
                          final itemWidth = isCompact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2;

                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: itemWidth,
                                child: _buildMetricTile(
                                  context,
                                  label: 'Temperature',
                                  value: _formatMeasurement(
                                    climate.temperature,
                                    'deg C',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildMetricTile(
                                  context,
                                  label: 'Humidity',
                                  value: _formatMeasurement(
                                    climate.humidity,
                                    '%',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildMetricTile(
                                  context,
                                  label: 'Precipitation',
                                  value: _formatMeasurement(
                                    climate.precipitation,
                                    'mm',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildMetricTile(
                                  context,
                                  label: 'Rain',
                                  value: _formatMeasurement(
                                    climate.rain,
                                    'mm',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildMetricTile(
                                  context,
                                  label: 'Wind Speed',
                                  value: _formatMeasurement(
                                    climate.windSpeed,
                                    'km/h',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              if (advisoryItems.isNotEmpty)
                InfoCard(
                  title: 'Additional Climate Notes',
                  icon: Icons.warning_amber_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: advisoryItems
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('- $item'),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasLocationData(LocationInfo? location) {
    if (location == null) {
      return false;
    }
    return location.barangay != null || location.lat != 0 || location.lng != 0;
  }

  bool _hasClimateData(ClimateInfo? climate) {
    if (climate == null) {
      return false;
    }
    return climate.temperature != null ||
        climate.humidity != null ||
        climate.precipitation != null ||
        climate.rain != null ||
        climate.weatherCode != null ||
        climate.windSpeed != null ||
        (climate.time?.trim().isNotEmpty ?? false);
  }

  bool _shouldLoadClimateFallback(DashboardModel dashboard) {
    return !_hasLocationData(dashboard.location) || !_hasClimateData(dashboard.climate);
  }

  String _buildConditionsFallbackMessage(
    LocationInfo? location,
    ClimateInfo? climate,
  ) {
    final hasLocationData = _hasLocationData(location);
    final hasClimateData = _hasClimateData(climate);

    if (!hasLocationData && !hasClimateData) {
      return 'Location and weather details are still incomplete for this area.';
    }
    if (!hasLocationData) {
      return 'Location details are still unavailable for this area.';
    }
    return 'Some weather details are still unavailable for this area.';
  }

  String _formatCoordinate(LocationInfo? location, double value) {
    if (!_hasLocationData(location)) {
      return 'N/A';
    }
    return value.toStringAsFixed(6);
  }

  String _formatMeasurement(double? value, String unit) {
    if (value == null) {
      return 'N/A';
    }
    return '${_formatNumericValue(value)} $unit';
  }

  String _formatNumericValue(double value) {
    final roundedWhole = value.roundToDouble();
    if ((value - roundedWhole).abs() < 0.05) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatTimestamp(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'N/A';
    }

    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      return normalized;
    }

    final local = parsed.toLocal();
    final month = _monthLabel(local.month);
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$month ${local.day}, ${local.year} \u2022 $hour:$minute $period';
  }

  String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _PlantingSuitabilityResult {
  const _PlantingSuitabilityResult({
    required this.status,
    required this.explanation,
  });

  final String status;
  final String explanation;
}
