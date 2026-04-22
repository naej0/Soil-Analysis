import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/api_config.dart';
import '../models/dashboard_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';
import '../widgets/recommendation_card.dart';

class GISMappingScreen extends StatefulWidget {
  const GISMappingScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<GISMappingScreen> createState() => _GISMappingScreenState();
}

class _GISMappingScreenState extends State<GISMappingScreen> {
  static const LatLng _surigaoCityCenter = LatLng(9.7844, 125.4881);
  static const double _surigaoCityZoom = 11.2;
  static const double _currentLocationZoom = 14.2;
  static const double _mapHeight = 460;
  static const double _minZoom = 10;
  static const double _maxZoom = 19;
  static const double _zoomStep = 1;
  static const double _defaultPolygonFillOpacity = 0.28;
  static const double _highlightedPolygonFillOpacity = 0.38;

  static const Map<String, Color> _soilColors = {
    'Clay': Color(0xFF9C5F3D),
    'Clay Loam': Color(0xFFC28B47),
    'Loam': Color(0xFF6F9B52),
    'Rock Land': Color(0xFF6C757D),
    'Silty Clay': Color(0xFF4F7A87),
  };

  final MapController _mapController = MapController();

  DashboardModel? _dashboard;
  GeoJsonFeatureCollection? _polygons;
  LatLng? _currentLocation;
  bool _loadingDashboard = false;
  bool _loadingPolygons = false;
  bool _mapReady = false;
  String? _locationMessage;
  String? _polygonMessage;
  bool _locationMessageIsError = false;
  bool _polygonMessageIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreen();
    });
  }

  Future<void> _initializeScreen() async {
    await _loadPolygons();
    await _loadDashboard();
  }

  Future<Position> _resolveCurrentPosition() async {
    final permissionStatus = await Permission.locationWhenInUse.request();
    if (!permissionStatus.isGranted) {
      throw const ApiException(
        'Location permission was denied. You can still browse the soil polygons on the map.',
      );
    }

    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw const ApiException(
        'Location services are disabled. You can still browse the soil polygons on the map.',
      );
    }

    var geolocatorPermission = await Geolocator.checkPermission();
    if (geolocatorPermission == LocationPermission.denied) {
      geolocatorPermission = await Geolocator.requestPermission();
    }

    if (geolocatorPermission == LocationPermission.denied ||
        geolocatorPermission == LocationPermission.deniedForever) {
      throw const ApiException(
        'Location access is not available. You can still browse the soil polygons on the map.',
      );
    }

    return Geolocator.getCurrentPosition(
      // ignore: deprecated_member_use
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loadingDashboard = true;
      _locationMessage = null;
      _locationMessageIsError = false;
    });

    try {
      final position = await _resolveCurrentPosition();
      final currentLocation = LatLng(position.latitude, position.longitude);

      if (!mounted) {
        return;
      }

      setState(() {
        _currentLocation = currentLocation;
      });
      _centerMapOnAvailableData();

      final dashboard = await widget.apiService.getDashboardByLocation(
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _dashboard = dashboard;
        _locationMessage = null;
        _locationMessageIsError = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = error.message;
        _locationMessageIsError = _isLocationErrorMessage(error.message);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('Dashboard unexpected error: $error');
      setState(() {
        _locationMessage =
            'We could not load location-based soil data right now. You can still browse the soil polygons on the map.';
        _locationMessageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDashboard = false;
        });
      }
    }
  }

  Future<void> _loadPolygons() async {
    setState(() {
      _loadingPolygons = true;
      _polygonMessage = null;
      _polygonMessageIsError = false;
    });

    try {
      final polygons = await widget.apiService.getSoilPolygons();
      if (!mounted) {
        return;
      }
      setState(() {
        _polygons = polygons;
        _polygonMessage = polygons.features.isEmpty
            ? 'No soil map shapes are available right now.'
            : null;
        _polygonMessageIsError = false;
      });
      _centerMapOnAvailableData();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _polygonMessage = error.message;
        _polygonMessageIsError = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _polygonMessage =
            'We could not load the soil polygons right now. Please try again.';
        _polygonMessageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPolygons = false;
        });
      }
    }
  }

  void _centerMapOnAvailableData() {
    if (!_mapReady) {
      return;
    }

    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      _mapController.move(currentLocation, _currentLocationZoom);
      return;
    }

    final polygonBounds = _buildPolygonBounds();
    if (polygonBounds != null) {
      _mapController.move(polygonBounds.center, _surigaoCityZoom);
      return;
    }

    _mapController.move(_surigaoCityCenter, _surigaoCityZoom);
  }

  void _zoomIn() {
    if (!_mapReady) {
      return;
    }
    final currentZoom = _mapController.camera.zoom;
    final nextZoom = (currentZoom + _zoomStep).clamp(_minZoom, _maxZoom);
    _mapController.move(_mapController.camera.center, nextZoom);
  }

  void _zoomOut() {
    if (!_mapReady) {
      return;
    }
    final currentZoom = _mapController.camera.zoom;
    final nextZoom = (currentZoom - _zoomStep).clamp(_minZoom, _maxZoom);
    _mapController.move(_mapController.camera.center, nextZoom);
  }

  void _recenterMap() {
    if (!_mapReady) {
      return;
    }
    _centerMapOnAvailableData();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final polygonData = _buildRenderablePolygons();
    final mapPolygons = _buildMapPolygons(polygonData);
    final highlightedPolygons = _buildHighlightedPolygons(polygonData);
    final markers = _buildMarkers();

    return Scaffold(
      appBar: AppBar(title: const Text('GIS Mapping')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'Surigao City Soil Map',
                icon: Icons.map_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Browse the live basemap with soil polygons, clear boundaries, and your current location.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: _mapHeight,
                          child: Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _surigaoCityCenter,
                                  initialZoom: _surigaoCityZoom,
                                  minZoom: _minZoom,
                                  maxZoom: _maxZoom,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.drag |
                                        InteractiveFlag.pinchZoom |
                                        InteractiveFlag.doubleTapZoom |
                                        InteractiveFlag.scrollWheelZoom |
                                        InteractiveFlag.flingAnimation,
                                  ),
                                  onMapReady: () {
                                    _mapReady = true;
                                    _centerMapOnAvailableData();
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.example.soil_mobile_app',
                                  ),
                                  PolygonLayer(polygons: mapPolygons),
                                  if (highlightedPolygons.isNotEmpty)
                                    PolygonLayer(polygons: highlightedPolygons),
                                  MarkerLayer(markers: markers),
                                ],
                              ),
                              Positioned(
                                top: 14,
                                right: 14,
                                child: Column(
                                  children: [
                                    _buildMapActionButton(
                                      context,
                                      icon: Icons.my_location,
                                      tooltip: 'Use current location',
                                      onPressed: _loadDashboard,
                                      isLoading: _loadingDashboard,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildMapActionButton(
                                      context,
                                      icon: Icons.add,
                                      tooltip: 'Zoom in',
                                      onPressed: _zoomIn,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildMapActionButton(
                                      context,
                                      icon: Icons.remove,
                                      tooltip: 'Zoom out',
                                      onPressed: _zoomOut,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildMapActionButton(
                                      context,
                                      icon: Icons.center_focus_strong,
                                      tooltip: _currentLocation != null
                                          ? 'Recenter to current location'
                                          : 'Recenter to map extent',
                                      onPressed: _recenterMap,
                                    ),
                                  ],
                                ),
                              ),
                              if (_loadingPolygons)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.08),
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withOpacity(0.92),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_polygonMessage != null)
                      Text(
                        _polygonMessage!,
                        style: TextStyle(
                          color: _messageColor(
                            context,
                            isError: _polygonMessageIsError,
                          ),
                        ),
                      ),
                    if (_locationMessage != null) ...[
                      if (_polygonMessage != null) const SizedBox(height: 8),
                      Text(
                        _locationMessage!,
                        style: TextStyle(
                          color: _messageColor(
                            context,
                            isError: _locationMessageIsError,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.72),
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
                          Text(
                            'Soil Type Legend',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Each soil type keeps its own polygon color and boundary on the real map.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 360;
                              final itemWidth = isCompact
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 12) / 2;

                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: ApiConfig.supportedSoilTypes
                                    .map(
                                      (soilType) => SizedBox(
                                        width: itemWidth,
                                        child: _buildLegendItem(soilType),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (dashboard != null) ...[
                InfoCard(
                  title: 'Location and Soil Details',
                  icon: Icons.place_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hasLocationData(dashboard.location) ||
                          !_hasSoilData(dashboard.soil)) ...[
                        Text(
                          _buildLocationSoilFallbackMessage(dashboard),
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text('Barangay: ${dashboard.location.barangay ?? 'N/A'}'),
                      const SizedBox(height: 4),
                      Text(
                        'Latitude: ${_formatCoordinate(dashboard.location, dashboard.location.lat)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Longitude: ${_formatCoordinate(dashboard.location, dashboard.location.lng)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Soil Type: ${_displayValue(dashboard.soil.soilType)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Soil Name: ${_displayValue(dashboard.soil.soilName)}',
                      ),
                    ],
                  ),
                ),
                InfoCard(
                  title: 'Climate Snapshot',
                  icon: Icons.thermostat_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hasClimateData(dashboard.climate)) ...[
                        Text(
                          'Climate details are currently unavailable for this location.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Temperature: ${_formatMeasurement(dashboard.climate.temperature, 'deg C')}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Humidity: ${_formatMeasurement(dashboard.climate.humidity, '%')}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Precipitation: ${_formatMeasurement(dashboard.climate.precipitation, 'mm')}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rain: ${_formatMeasurement(dashboard.climate.rain, 'mm')}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Wind Speed: ${_formatMeasurement(dashboard.climate.windSpeed, 'km/h')}',
                      ),
                    ],
                  ),
                ),
                InfoCard(
                  title: 'Recommended Crops',
                  icon: Icons.eco_outlined,
                  child: dashboard.recommendations.isEmpty
                      ? const Text(
                          'No crop recommendations are available for this area right now.',
                        )
                      : Column(
                          children: dashboard.recommendations
                              .map(
                                (item) =>
                                    RecommendationCard(recommendation: item),
                              )
                              .toList(),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_MapPolygonData> _buildRenderablePolygons() {
    final polygons = <_MapPolygonData>[];
    final features = _polygons?.features ?? const <Map<String, dynamic>>[];
    final currentLocation = _currentLocation;

    for (final feature in features) {
      final soilType = _soilTypeFromFeature(feature);

      for (final points in _polygonPointsFromFeature(feature)) {
        if (points.length < 3) {
          continue;
        }

        polygons.add(
          _MapPolygonData(
            soilType: soilType,
            points: points,
            containsCurrentLocation: currentLocation != null
                ? _isPointInsidePolygon(currentLocation, points)
                : false,
          ),
        );
      }
    }

    return polygons;
  }

  List<Polygon> _buildMapPolygons(List<_MapPolygonData> polygonData) {
    final polygons = <Polygon>[];

    for (final polygonDataItem in polygonData) {
      final baseColor = _soilColorFor(polygonDataItem.soilType);

      polygons.add(
        Polygon(
          points: polygonDataItem.points,
          color: polygonDataItem.containsCurrentLocation
              ? baseColor.withOpacity(_highlightedPolygonFillOpacity)
              : baseColor.withOpacity(_defaultPolygonFillOpacity),
          borderColor: polygonDataItem.containsCurrentLocation
              ? baseColor.withOpacity(0.98)
              : baseColor.withOpacity(0.94),
          borderStrokeWidth:
              polygonDataItem.containsCurrentLocation ? 2.4 : 1.8,
        ),
      );
    }

    return polygons;
  }

  List<Polygon> _buildHighlightedPolygons(List<_MapPolygonData> polygonData) {
    return polygonData
        .where((polygon) => polygon.containsCurrentLocation)
        .map(
          (polygon) => Polygon(
            points: polygon.points,
            color: Colors.white.withOpacity(0.03),
            borderColor: Colors.white.withOpacity(0.96),
            borderStrokeWidth: 3,
          ),
        )
        .toList();
  }

  List<Marker> _buildMarkers() {
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      return const <Marker>[];
    }

    return [
      Marker(
        point: currentLocation,
        width: 24,
        height: 24,
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.92),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildMapActionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.94),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        onPressed: isLoading ? null : onPressed,
        tooltip: tooltip,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildLegendItem(String soilType) {
    final color = _soilColorFor(soilType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withOpacity(0.92)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              soilType,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  _CoordinateBounds? _buildPolygonBounds() {
    final features = _polygons?.features ?? const <Map<String, dynamic>>[];
    double? minLatitude;
    double? maxLatitude;
    double? minLongitude;
    double? maxLongitude;

    for (final feature in features) {
      for (final polygonPoints in _polygonPointsFromFeature(feature)) {
        for (final point in polygonPoints) {
          minLatitude = minLatitude == null
              ? point.latitude
              : (point.latitude < minLatitude ? point.latitude : minLatitude);
          maxLatitude = maxLatitude == null
              ? point.latitude
              : (point.latitude > maxLatitude ? point.latitude : maxLatitude);
          minLongitude = minLongitude == null
              ? point.longitude
              : (point.longitude < minLongitude ? point.longitude : minLongitude);
          maxLongitude = maxLongitude == null
              ? point.longitude
              : (point.longitude > maxLongitude ? point.longitude : maxLongitude);
        }
      }
    }

    if (minLatitude == null ||
        maxLatitude == null ||
        minLongitude == null ||
        maxLongitude == null) {
      return null;
    }

    return _CoordinateBounds(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }

  Color _soilColorFor(String soilType) {
    final normalizedSoilType = soilType.trim();
    return _soilColors[normalizedSoilType] ?? const Color(0xFF8C8C8C);
  }

  String _soilTypeFromFeature(Map<String, dynamic> feature) {
    final properties = _asMap(feature['properties']);
    return _asString(properties['soil_type']);
  }

  List<List<LatLng>> _polygonPointsFromFeature(Map<String, dynamic> feature) {
    final geometry = _asMap(feature['geometry']);
    final geometryType = _asString(geometry['type']);
    final coordinates = geometry['coordinates'];

    if (geometryType == 'Polygon') {
      final polygonPoints = _polygonPointsFromCoordinates(coordinates);
      return polygonPoints.isEmpty
          ? const <List<LatLng>>[]
          : <List<LatLng>>[polygonPoints];
    }

    if (geometryType == 'MultiPolygon' && coordinates is List) {
      final polygons = <List<LatLng>>[];
      for (final polygonCoordinates in coordinates) {
        final polygonPoints = _polygonPointsFromCoordinates(polygonCoordinates);
        if (polygonPoints.isNotEmpty) {
          polygons.add(polygonPoints);
        }
      }
      return polygons;
    }

    return const <List<LatLng>>[];
  }

  List<LatLng> _polygonPointsFromCoordinates(dynamic polygonCoordinates) {
    if (polygonCoordinates is! List || polygonCoordinates.isEmpty) {
      return const <LatLng>[];
    }

    final exteriorRing = polygonCoordinates.first;
    if (exteriorRing is! List) {
      return const <LatLng>[];
    }

    final points = <LatLng>[];
    for (final coordinatePair in exteriorRing) {
      final point = _latLngFromGeoJsonCoordinate(coordinatePair);
      if (point != null) {
        points.add(point);
      }
    }
    return points;
  }

  LatLng? _latLngFromGeoJsonCoordinate(dynamic coordinatePair) {
    if (coordinatePair is! List || coordinatePair.length < 2) {
      return null;
    }

    final longitude = _asDouble(coordinatePair[0]);
    final latitude = _asDouble(coordinatePair[1]);
    if (longitude == null || latitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  bool _isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) {
      return false;
    }

    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final currentPoint = polygon[i];
      final previousPoint = polygon[j];
      final currentLatitude = currentPoint.latitude;
      final previousLatitude = previousPoint.latitude;
      final currentLongitude = currentPoint.longitude;
      final previousLongitude = previousPoint.longitude;

      final intersects =
          ((currentLatitude > point.latitude) !=
                  (previousLatitude > point.latitude)) &&
              (point.longitude <
                  (previousLongitude - currentLongitude) *
                          (point.latitude - currentLatitude) /
                          ((previousLatitude - currentLatitude) == 0
                              ? 0.0000001
                              : (previousLatitude - currentLatitude)) +
                      currentLongitude);

      if (intersects) {
        inside = !inside;
      }
    }

    return inside;
  }

  bool _isLocationErrorMessage(String message) {
    final normalized = message.toLowerCase();
    return !(normalized.contains('denied') ||
        normalized.contains('disabled') ||
        normalized.contains('not available'));
  }

  Color _messageColor(BuildContext context, {required bool isError}) {
    return isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
  }

  String _displayValue(dynamic value, {String fallback = 'N/A'}) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  bool _hasLocationData(LocationInfo location) {
    return location.barangay != null || location.lat != 0 || location.lng != 0;
  }

  bool _hasSoilData(SoilInfo soil) {
    return soil.soilType.trim().isNotEmpty || soil.soilName.trim().isNotEmpty;
  }

  bool _hasClimateData(ClimateInfo climate) {
    return climate.temperature != null ||
        climate.humidity != null ||
        climate.precipitation != null ||
        climate.rain != null ||
        climate.weatherCode != null ||
        climate.windSpeed != null ||
        (climate.time?.trim().isNotEmpty ?? false);
  }

  String _buildLocationSoilFallbackMessage(DashboardModel dashboard) {
    final hasLocationData = _hasLocationData(dashboard.location);
    final hasSoilData = _hasSoilData(dashboard.soil);

    if (!hasLocationData && !hasSoilData) {
      return 'Location and soil details are currently unavailable for this area.';
    }
    if (!hasLocationData) {
      return 'Location details are currently unavailable for this area.';
    }
    return 'Soil details are currently unavailable for this area.';
  }

  String _formatCoordinate(LocationInfo location, double value) {
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

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return const <String, dynamic>{};
  }

  String _asString(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized;
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}

class _CoordinateBounds {
  const _CoordinateBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  LatLng get center => LatLng(
        (minLatitude + maxLatitude) / 2,
        (minLongitude + maxLongitude) / 2,
      );
}

class _MapPolygonData {
  const _MapPolygonData({
    required this.soilType,
    required this.points,
    required this.containsCurrentLocation,
  });

  final String soilType;
  final List<LatLng> points;
  final bool containsCurrentLocation;
}