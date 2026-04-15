class LeaseModel {
  const LeaseModel({
    required this.id,
    required this.ownerName,
    required this.contactNumber,
    required this.barangay,
    required this.soilType,
    required this.areaHectares,
    required this.price,
    required this.description,
    this.status,
    this.createdAt,
  });

  final int id;
  final String ownerName;
  final String contactNumber;
  final String barangay;
  final String soilType;
  final double areaHectares;
  final double price;
  final String description;
  final String? status;
  final DateTime? createdAt;

  factory LeaseModel.fromJson(Map<String, dynamic> json) {
    return LeaseModel(
      id: json['id'] as int,
      ownerName: json['owner_name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      soilType: json['soil_type'] as String? ?? '',
      areaHectares: (json['area_hectares'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      status: json['status'] as String?,
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
