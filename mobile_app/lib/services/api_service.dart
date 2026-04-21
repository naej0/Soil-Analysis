import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/assistant_model.dart';
import '../models/ai_prediction_model.dart';
import '../models/dashboard_model.dart';
import '../models/lease_model.dart';
import '../models/productivity_model.dart';
import '../models/soil_analysis_support_model.dart';
import '../models/user_model.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}


class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const List<String> _supportedSoilImageExtensions = [
    '.bmp',
    '.jpeg',
    '.jpg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  ];

  bool isSupportedSoilImagePath(String path) {
    final lowerPath = path.toLowerCase();
    return _supportedSoilImageExtensions.any((ext) => lowerPath.endsWith(ext));
  }

  String get supportedSoilImageExtensionsLabel =>
      _supportedSoilImageExtensions.join(', ');

  String get _baseUrl => ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;

  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final query = <String, String>{};
    queryParameters?.forEach((key, value) {
      if (value != null && value.toString().trim().isNotEmpty) {
        query[key] = value.toString();
      }
    });

    return Uri.parse('$_baseUrl$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );
  }


  Map<String, dynamic> _adminQueryParameters(int adminUserId) {
    return {
      'admin_id': adminUserId,
      'admin_user_id': adminUserId,
    };
  }

  Map<String, String> _adminHeaders(int adminUserId) {
    return {
      'X-Admin-User-Id': adminUserId.toString(),
    };
  }

  Future<AuthResponse> registerUser({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final data = await _post(
      '/users/register',
      queryParameters: {
        'full_name': fullName,
        'email': email,
        'password': password,
      },
    );
    return AuthResponse.fromJson(data);
  }

  Future<AuthResponse> loginUser({
    required String email,
    required String password,
  }) async {
    final data = await _post(
      '/users/login',
      queryParameters: {
        'email': email,
        'password': password,
      },
    );
    return AuthResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> getAdminDashboard({
    required int adminUserId,
  }) async {
    final data = await _get(
      '/admin/dashboard',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
    );

    return {
      'users': {
        'total': data['total_users'] ?? 0,
        'active': data['active_users'] ?? 0,
        'restricted': data['restricted_users'] ?? 0,
      },
      'leases': {
        'total': data['total_lease_listings'] ?? 0,
        'active': data['active_lease_listings'] ?? 0,
        'flagged': data['flagged_lease_listings'] ?? 0,
      },
      'productivity': {
        'total_records': data['total_productivity_records'] ?? 0,
      },
      'soil_analysis_logs': {
        'total_logs': data['total_soil_analyses'] ?? 0,
        'common_soil_types': data['common_soil_types'] ?? [],
      },
    };
  }

  Future<List<Map<String, dynamic>>> getAdminUsers({
    required int adminUserId,
  }) async {
    final data = await _get(
      '/admin/users',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
    );
    return _mapList(data['users']);
  }

  Future<Map<String, dynamic>> restrictUser({
    required int adminUserId,
    required int userId,
    String? reason,
  }) async {
    final trimmedReason = reason?.trim();
    final data = await _patchJson(
      '/admin/users/$userId/restrict',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
      body: {
        'admin_id': adminUserId,
        'violation_type': 'policy_violation',
        'reason': (trimmedReason != null && trimmedReason.isNotEmpty)
            ? trimmedReason
            : 'Restricted by admin',
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> reactivateUser({
    required int adminUserId,
    required int userId,
  }) async {
    final data = await _patchJson(
      '/admin/users/$userId/reactivate',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
      body: {
        'admin_id': adminUserId,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminLeases({
    required int adminUserId,
  }) async {
    final data = await _get(
      '/admin/leases',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
    );
    return _mapList(data['leases']);
  }

  Future<Map<String, dynamic>> hideLease({
    required int adminUserId,
    required int leaseId,
    String? reason,
  }) async {
    final trimmedReason = reason?.trim();
    final data = await _patchJson(
      '/admin/leases/$leaseId/hide',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
      body: {
        'admin_id': adminUserId,
        if (trimmedReason != null && trimmedReason.isNotEmpty)
          'reason': trimmedReason,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> flagLease({
    required int adminUserId,
    required int leaseId,
    String? reason,
  }) async {
    final trimmedReason = reason?.trim();
    final data = await _patchJson(
      '/admin/leases/$leaseId/flag',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
      body: {
        'admin_id': adminUserId,
        'reason': (trimmedReason != null && trimmedReason.isNotEmpty)
            ? trimmedReason
            : 'Flagged by admin',
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> restoreLease({
    required int adminUserId,
    required int leaseId,
  }) async {
    final data = await _patchJson(
      '/admin/leases/$leaseId/restore',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
      body: {
        'admin_id': adminUserId,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminProductivity({
    required int adminUserId,
  }) async {
    final data = await _get(
      '/admin/productivity',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
    );
    return _mapList(data['productivity_records']);
  }

  Future<List<Map<String, dynamic>>> getAdminSoilLogs({
    required int adminUserId,
  }) async {
    final data = await _get(
      '/admin/soil-analysis-logs',
      queryParameters: _adminQueryParameters(adminUserId),
      headers: _adminHeaders(adminUserId),
    );
    return _mapList(data['soil_analysis_logs']);
  }

  Future<DashboardModel> getDashboardByLocation({
    required double lat,
    required double lng,
  }) async {
    final data = await _get(
      '/dashboard/by-location',
      queryParameters: {'lat': lat, 'lng': lng},
    );

    if (data['location'] == null || data['soil'] == null) {
      throw ApiException(
        (data['message'] as String?) ?? 'Dashboard data is incomplete.',
      );
    }

    return DashboardModel.fromJson(data);
  }

  Future<ClimateCurrentModel> getClimateCurrent({
    required double lat,
    required double lng,
  }) async {
    final data = await _get(
      '/climate/current',
      queryParameters: {'lat': lat, 'lng': lng},
    );

    if (data['location'] == null || data['climate'] == null) {
      throw ApiException(
        (data['message'] as String?) ?? 'Climate data is incomplete.',
      );
    }

    return ClimateCurrentModel.fromJson(data);
  }

  Future<List<RecommendationItem>> getRecommendationsBySoil(
    String soilType,
  ) async {
    final data = await _get(
      '/recommendations/by-soil',
      queryParameters: {'soil_type': soilType},
    );

    final items = data['recommendations'] as List? ?? [];
    return items
        .map(
          (item) => RecommendationItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<SoilAnalysisSupportResponse> fetchSoilAnalysisSupport(
    String soilType, {
    String? cropName,
  }) async {
    final trimmedSoilType = soilType.trim();
    final encodedSoilType = Uri.encodeComponent(trimmedSoilType);
    final data = await _get(
      '/soil-analysis/support/$encodedSoilType',
      queryParameters: {
        'crop_name': cropName,
      },
    );
    return SoilAnalysisSupportResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> getCropRecommendationsBySoilType(
    String soilType,
  ) async {
    final trimmedSoilType = soilType.trim();
    final encodedSoilType = Uri.encodeComponent(trimmedSoilType);
    final data = await _get(
      '/soil-analysis/crop-recommendations/$encodedSoilType',
    );

    return Map<String, dynamic>.from(data as Map);
  }

  Future<GeoJsonFeatureCollection> getSoilPolygons() async {
    final data = await _get('/soil/polygons');
    if (data['type'] == null && data['features'] == null) {
      throw ApiException(
        (data['message'] as String?) ?? 'Soil polygon data is unavailable.',
      );
    }
    return GeoJsonFeatureCollection.fromJson(data);
  }

  Future<List<LeaseModel>> getLeases() async {
    final data = await _get('/leases');
    final leases = data['leases'] as List? ?? [];
    return leases
        .map(
          (item) => LeaseModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<LeaseModel> createLease({
    required String ownerName,
    required String contactNumber,
    required String barangay,
    required String soilType,
    required String areaHectares,
    required String price,
    required String description,
  }) async {
    final data = await _post(
      '/leases',
      queryParameters: {
        'owner_name': ownerName,
        'contact_number': contactNumber,
        'barangay': barangay,
        'soil_type': soilType,
        'area_hectares': areaHectares,
        'price': price,
        'description': description,
      },
    );
    return LeaseModel.fromJson(
      Map<String, dynamic>.from(data['lease'] as Map),
    );
  }

  Future<List<ProductivityRecord>> getProductivityRecords(int userId) async {
    final data = await _get('/productivity/$userId');
    final records = data['records'] as List? ?? [];
    return records
        .map(
          (item) => ProductivityRecord.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<ProductivityRecord> createProductivityRecord({
    required int userId,
    required String soilType,
    required String cropName,
    required String areaHectares,
    required String yieldAmount,
    required String notes,
  }) async {
    final data = await _post(
      '/productivity',
      queryParameters: {
        'user_id': userId,
        'soil_type': soilType,
        'crop_name': cropName,
        'area_hectares': areaHectares,
        'yield_amount': yieldAmount,
        'notes': notes,
      },
    );
    return ProductivityRecord.fromJson(
      Map<String, dynamic>.from(data['record'] as Map),
    );
  }

  Future<AiUploadResponse> uploadSoilImage(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _buildUri('/ai/upload-soil-image'),
      );
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = _decodeResponse(response);
      return AiUploadResponse.fromJson(data);
    } on SocketException {
      throw ApiException('Could not connect to backend at $_baseUrl');
    } on http.ClientException {
      throw const ApiException(
        'Network request failed while uploading the image.',
      );
    }
  }

  Future<AiPredictionResponse> predictSoil({
    required String fileName,
    int? userId,
    String? originalFileName,
    double? lat,
    double? lng,
    String? barangay,
    String? soilName,
  }) async {
    final body = <String, dynamic>{
      'file_name': fileName,
      if (userId != null) 'user_id': userId,
      if (originalFileName != null && originalFileName.trim().isNotEmpty)
        'original_file_name': originalFileName,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (barangay != null && barangay.trim().isNotEmpty)
        'barangay': barangay,
      if (soilName != null && soilName.trim().isNotEmpty)
        'soil_name': soilName,
    };

    final data = await _postJson(
      '/ai/predict',
      body: body,
    );

    return AiPredictionResponse.fromJson(data);
  }

  Future<AssistantChatResponse> askAssistant({
    required String question,
    Map<String, dynamic>? context,
    List<Map<String, dynamic>>? history,
  }) async {
    final request = AssistantChatRequest(
      question: question,
      context: context,
      history: history,
    );

    final data = await _postJson(
      '/assistant/chat',
      body: request.toJson(),
    );
    return AssistantChatResponse.fromJson(data);
  }

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _client.get(
        _buildUri(path, queryParameters),
        headers: {
          'Accept': 'application/json',
          if (headers != null) ...headers,
        },
      );
      return _decodeResponse(response);
    } on SocketException {
      throw ApiException('Could not connect to backend at $_baseUrl');
    } on http.ClientException {
      throw const ApiException(
        'Network request failed while contacting the backend.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _client.post(
        _buildUri(path, queryParameters),
        headers: {'Accept': 'application/json'},
      );
      return _decodeResponse(response);
    } on SocketException {
      throw ApiException('Could not connect to backend at $_baseUrl');
    } on http.ClientException {
      throw const ApiException(
        'Network request failed while contacting the backend.',
      );
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _client.post(
        _buildUri(path),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      return _decodeResponse(response);
    } on SocketException {
      throw ApiException('Could not connect to backend at $_baseUrl');
    } on http.ClientException {
      throw const ApiException(
        'Network request failed while contacting the backend.',
      );
    }
  }

  Future<Map<String, dynamic>> _patchJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    try {
      final requestHeaders = <String, String>{
        'Accept': 'application/json',
        if (headers != null) ...headers,
      };

      String? encodedBody;
      if (body != null) {
        requestHeaders['Content-Type'] = 'application/json';
        encodedBody = jsonEncode(body);
      }

      final response = await _client.patch(
        _buildUri(path, queryParameters),
        headers: requestHeaders,
        body: encodedBody,
      );
      return _decodeResponse(response);
    } on SocketException {
      throw ApiException('Could not connect to backend at $_baseUrl');
    } on http.ClientException {
      throw const ApiException(
        'Network request failed while contacting the backend.',
      );
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    final items = value as List? ?? [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    dynamic decodedBody;
    if (response.body.isNotEmpty) {
      try {
        decodedBody = jsonDecode(response.body);
      } on FormatException {
        decodedBody = {'message': response.body};
      }
    } else {
      decodedBody = <String, dynamic>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decodedBody is Map<String, dynamic>) {
        return decodedBody;
      }
      if (decodedBody is Map) {
        return Map<String, dynamic>.from(decodedBody);
      }
      if (decodedBody is List) {
        return {'data': decodedBody};
      }
      return {'data': decodedBody};
    }

    throw ApiException(
      _extractErrorMessage(decodedBody, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  String _extractErrorMessage(dynamic decodedBody, int statusCode) {
    if (decodedBody is Map) {
      final detail = decodedBody['detail'];
      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      if (detail is Map) {
        final message = detail['message'];
        final supported = detail['supported_soil_types'];
        if (message is String && supported is List && supported.isNotEmpty) {
          return '$message. Supported: ${supported.join(', ')}';
        }
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }

      final message = decodedBody['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }

    return 'Request failed with status code $statusCode';
  }
}
