class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const List<String> supportedSoilTypes = [
    'Silty Clay',
    'Loam',
    'Clay Loam',
    'Clay',
    'Rock Land',
  ];
}
