import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'core/theme.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/main_hub_screen.dart';
import 'services/native_lockscreen_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {}
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final imageUrl = message.data['image_url'] as String?;
    final senderName = message.data['sender_name'] as String? ?? 'Partner';
    final isCleared = message.data['is_cleared'] == 'true';

    if (isCleared) {
      await NativeLockscreenService().clearLockscreen();
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      await NativeLockscreenService().updateLockscreenFromUrl(
        imageUrl,
        senderName: senderName,
      );
    }
  } catch (e) {
    debugPrint('Background message handling error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv initialization notice: $e');
  }

  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;

    // Register background FCM handler (Android/iOS native only)
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(ScribbleApp(isFirebaseInitialized: firebaseInitialized));
}

class ScribbleApp extends StatefulWidget {
  final bool isFirebaseInitialized;

  const ScribbleApp({super.key, required this.isFirebaseInitialized});

  @override
  State<ScribbleApp> createState() => _ScribbleAppState();
}

class _ScribbleAppState extends State<ScribbleApp> {
  User? _currentUser;
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    if (widget.isFirebaseInitialized) {
      _currentUser = FirebaseAuth.instance.currentUser;
      _authStream = FirebaseAuth.instance.authStateChanges();
    } else {
      _authStream = const Stream.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scribble',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        // Clamp text scale factor between 0.85 and 1.3 to prevent extreme font scaling from breaking responsive layouts
        final clampedScaler = mediaQueryData.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mediaQueryData.copyWith(textScaler: clampedScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: !widget.isFirebaseInitialized
          ? Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Firebase Setup Error',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please verify google-services.json is present in android/app/ and restart the app.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : StreamBuilder<User?>(
              stream: _authStream,
              initialData: _currentUser,
              builder: (context, snapshot) {
                final user = snapshot.data;
                if (user != null) {
                  return MainHubScreen(
                    onSignOut: () {
                      setState(() => _currentUser = null);
                    },
                  );
                } else {
                  return AuthScreen(
                    onAuthenticated: () {
                      setState(() {
                        _currentUser = FirebaseAuth.instance.currentUser;
                      });
                    },
                  );
                }
              },
            ),
    );
  }
}
