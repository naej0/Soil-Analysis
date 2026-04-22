import 'package:flutter/material.dart';

import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'widgets/global_assistant_launcher.dart';

void main() {
  runApp(const SoilMobileApp());
}

class SoilMobileApp extends StatefulWidget {
  const SoilMobileApp({super.key});

  @override
  State<SoilMobileApp> createState() => _SoilMobileAppState();
}

class _SoilMobileAppState extends State<SoilMobileApp> {
  final ApiService _apiService = ApiService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soil Mobile App',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      builder: (context, child) {
        return GlobalAssistantLauncher(
          apiService: _apiService,
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AuthGateway(apiService: _apiService),
    );
  }
}

class AuthGateway extends StatefulWidget {
  const AuthGateway({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<AuthGateway> createState() => _AuthGatewayState();
}

class _AuthGatewayState extends State<AuthGateway> {
  UserModel? _currentUser;

  void _handleLogin(UserModel user) {
    setState(() {
      _currentUser = user;
    });
  }

  void _handleLogout() {
    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return LoginScreen(
        apiService: widget.apiService,
        onLoginSuccess: _handleLogin,
      );
    }

    return HomeScreen(
      apiService: widget.apiService,
      currentUser: _currentUser!,
      onLogout: _handleLogout,
    );
  }
}
