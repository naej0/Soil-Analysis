class ProductivityRecord {
  const ProductivityRecord({
    required this.id,
    required this.userId,
    required this.soilType,
    required this.cropName,
    required this.areaHectares,
    required this.yieldAmount,
    this.notes,
    this.createdAt,
  });

  final int id;
  final int userId;
  final String soilType;
  final String cropName;
  final double areaHectares;
  final double yieldAmount;
  final String? notes;
  final DateTime? createdAt;

  factory ProductivityRecord.fromJson(Map<String, dynamic> json) {
    return ProductivityRecord(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      soilType: json['soil_type'] as String? ?? '',
      cropName: json['crop_name'] as String? ?? '',
      areaHectares: (json['area_hectares'] as num?)?.toDouble() ?? 0,
      yieldAmount: (json['yield_amount'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
