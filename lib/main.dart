import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'services/theme_mode_service.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeModeService.init();

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
    final Widget initialScreen =
        widget.supabaseReady &&
            Supabase.instance.client.auth.currentSession != null
        ? const HomeScreen()
        : OnboardingScreen(supabaseReady: widget.supabaseReady);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeService.notifier,
      builder: (BuildContext context, ThemeMode mode, Widget? child) {
        return MaterialApp(
          title: 'Foxy',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          localizationsDelegates:
              quill.FlutterQuillLocalizations.localizationsDelegates,
          supportedLocales: quill.FlutterQuillLocalizations.supportedLocales,
          themeMode: mode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: appBackground,
            appBarTheme: AppBarTheme(
              backgroundColor: appBackground,
              foregroundColor: textColor,
              elevation: 0,
            ),
            textTheme: TextTheme(
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
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: appBackground,
            appBarTheme: AppBarTheme(
              backgroundColor: appBackground,
              foregroundColor: textColor,
              elevation: 0,
            ),
            textTheme: TextTheme(
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
          home: initialScreen,
        );
      },
    );
  }
}
