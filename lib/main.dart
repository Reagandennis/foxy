import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(FoxyApp(supabaseReady: SupabaseConfig.isConfigured));
}

class FoxyApp extends StatefulWidget {
  const FoxyApp({super.key, required this.supabaseReady});

  final bool supabaseReady;

  @override
  State<FoxyApp> createState() => _FoxyAppState();
}

class _FoxyAppState extends State<FoxyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  bool _isRecoveryScreenOpen = false;

  @override
  void initState() {
    super.initState();

    if (widget.supabaseReady) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((AuthState data) {
            if (data.event == AuthChangeEvent.passwordRecovery) {
              _openRecoveryScreen();
            }
          });
    }
  }

  void _openRecoveryScreen() {
    if (_isRecoveryScreenOpen) {
      return;
    }

    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openRecoveryScreen();
      });
      return;
    }

    _isRecoveryScreenOpen = true;
    navigator
        .push(
          MaterialPageRoute(
            builder: (_) => const UpdatePasswordScreen(),
            fullscreenDialog: true,
          ),
        )
        .whenComplete(() {
          _isRecoveryScreenOpen = false;
        });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foxy',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: appBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: appBackground,
          foregroundColor: textColor,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
          bodyLarge: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ),
      home: OnboardingScreen(supabaseReady: widget.supabaseReady),
    );
  }
}
