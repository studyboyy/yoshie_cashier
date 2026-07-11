import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/user_profile.dart';
import 'screens/cashier_home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/app_update_service.dart';
import 'widgets/common/app_update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YosyCashierApp());
}

class YosyCashierApp extends StatefulWidget {
  const YosyCashierApp({super.key});

  @override
  State<YosyCashierApp> createState() => _YosyCashierAppState();
}

class _YosyCashierAppState extends State<YosyCashierApp>
    with WidgetsBindingObserver {
  late final ApiClient _api;
  late final AppUpdateService _appUpdateService;
  late final Future<UserProfile?> _session;
  late final Connectivity _connectivity;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOffline = false;
  bool _needsDataRefresh = false;
  DateTime? _lastBackgroundTime;
  bool _checkedForUpdate = false;

  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ApiClient();
    _appUpdateService = AppUpdateService();
    _session = _api.restoreSession();
    _connectivity = Connectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectivity(result);
    } catch (_) {
      // Ignore — assume online
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (!offline) {
      _api.resetNetworkGuard();
    }
    if (mounted && offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _lastBackgroundTime = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      // If app was in background for more than 2 minutes, mark for refresh
      if (_lastBackgroundTime != null &&
          DateTime.now().difference(_lastBackgroundTime!).inMinutes >= 2) {
        _needsDataRefresh = true;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void handleUnauthorized() {
    _api.logout();
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            LoginScreen(api: _api, appUpdateService: _appUpdateService),
      ),
      (_) => false,
    );
  }

  void _checkForUpdateOnce(BuildContext context) {
    if (_checkedForUpdate) {
      return;
    }

    _checkedForUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        return;
      }

      try {
        final update = await _appUpdateService.checkForUpdate();
        if (!context.mounted || !update.updateAvailable) {
          return;
        }

        await showDialog<void>(
          context: context,
          barrierDismissible: !update.required,
          builder: (_) =>
              AppUpdateDialog(update: update, updateService: _appUpdateService),
        );
      } catch (_) {
        // Cek update otomatis dibuat silent supaya app tetap bisa dipakai
        // kalau server sedang lambat atau perangkat offline.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yosy Kasir',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      // Smooth page transition — pakai Cupertino style (slide) yang lebih
      // halus daripada default Material fade/scale Android
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: const CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          },
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      // ScrollConfiguration global: physics lebih smooth untuk semua ListView
      builder: (context, child) => ScrollConfiguration(
        behavior: const _SmoothScrollBehavior(),
        child: child!,
      ),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            // Exit app on back press — Android handles double-tap natively
            SystemNavigator.pop();
          }
        },
        child: FutureBuilder<UserProfile?>(
          future: _session,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _SplashScreen();
            }

            _checkForUpdateOnce(context);

            final user = snapshot.data;
            if (user == null) {
              return LoginScreen(
                api: _api,
                appUpdateService: _appUpdateService,
              );
            }

            return Stack(
              children: [
                CashierHomeScreen(
                  api: _api,
                  appUpdateService: _appUpdateService,
                  user: user,
                  onUnauthorized: handleUnauthorized,
                  needsDataRefresh: _needsDataRefresh,
                  onDataRefreshed: () {
                    _needsDataRefresh = false;
                  },
                ),
                // Offline banner overlay
                if (_isOffline)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      color: Colors.transparent,
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: const Color(0xFFEF4444),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.wifi_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Mode Offline — Transaksi akan disimpan & di-sync saat online',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Scroll behavior kustom: BouncingScrollPhysics + tidak ada glow overscroll.
/// Lebih smooth dibanding default Android (ClampingScrollPhysics + glow biru).
class _SmoothScrollBehavior extends ScrollBehavior {
  const _SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Hapus glow biru Android saat overscroll — terlihat lebih clean
    return child;
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Image(image: AssetImage('assets/images/brand.png')),
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
