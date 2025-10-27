import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'providers/user_provider.dart';
import 'auth_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

String backendBaseUrl = "http://127.0.0.1:8000";

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => LocaleProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(create: (context) => ThemeNotifier('DARK')),
      ],
      child: const MyApp(),
    ),
  );
}

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode;
  ThemeNotifier([String initial = 'DARK']) : _mode = (initial.toUpperCase() == 'LIGHT' ? ThemeMode.light : ThemeMode.dark);
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  void setTheme(String key) {
    final k = (key).toString().toUpperCase();
    _mode = (k == 'LIGHT') ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    const Color brandDeep = Color(0xFFE91E63);     // vivid pink (light primary)
    const Color brandAccent = Color(0xFFFF7043);   // warm coral / peach accent
    const Color brandViolet = Color(0xFFAB47BC);   // soft lavender for secondary accents
    const Color bgLight = Color(0xFFFFFBFD);       // very light blush background
    const Color cardLight = Color(0xFFFFF1F6);     // soft card surface with blush tint

    const Color brandDarkPrimary = Color(0xFF08203A); // deep midnight blue
    const Color brandDarkAccent = Color(0xFF00BFA6);  // cold teal accent for sharp contrast
    const Color bgDark = Color(0xFF05060A);
    const Color cardDark = Color(0xFF0B0F14);

    final themeNotifier = Provider.of<ThemeNotifier>(context);
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        final localeProvider = Provider.of<LocaleProvider>(context);
        return MaterialApp(
          locale: localeProvider.locale,
          useInheritedMediaQuery: true,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateTitle: (context) => "Flow7",
          themeMode: themeNotifier.mode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: bgLight,
            colorScheme: ColorScheme.fromSeed(seedColor: brandDeep, brightness: Brightness.light).copyWith(
              primary: brandDeep,
              secondary: brandViolet,
              tertiary: brandAccent,
              background: bgLight,
              surface: cardLight,
              onPrimary: Colors.white,
            ),
            appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: const Color(0xFF042028), elevation: 0),
            cardTheme: CardThemeData(color: cardLight, elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r))),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandDeep,
                foregroundColor: Colors.white,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
              ),
            ),
            textTheme: ThemeData.light().textTheme.apply(bodyColor: const Color(0xFF042028)),
            visualDensity: VisualDensity.adaptivePlatformDensity,
            pageTransitionsTheme: const PageTransitionsTheme(builders: { TargetPlatform.iOS: CupertinoPageTransitionsBuilder(), TargetPlatform.android: FadeUpwardsPageTransitionsBuilder() }),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: bgDark,
            colorScheme: ColorScheme.fromSeed(seedColor: brandDarkPrimary, brightness: Brightness.dark).copyWith(
              primary: brandDarkPrimary,
              secondary: brandDarkAccent,
              tertiary: brandDeep,
              background: bgDark,
              surface: cardDark,
              onPrimary: Colors.white,
            ),
            appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
            cardTheme: CardThemeData(color: cardDark, elevation: 14, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandDarkPrimary,
                foregroundColor: Colors.white,
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
            textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white),
          ),
          home: child,
        );
      },
      child: const FirstRunInitializer(child: AuthGate()),
    );
  }
}

/// Widget that runs once after app start to request notification permission
/// for first-time installs. It persists a 'notification_permission_requested'
/// flag and the resulting 'notifications_enabled' boolean in SharedPreferences.
class FirstRunInitializer extends StatefulWidget {
  final Widget child;
  const FirstRunInitializer({required this.child, super.key});

  @override
  State<FirstRunInitializer> createState() => _FirstRunInitializerState();
}

class _FirstRunInitializerState extends State<FirstRunInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRequestPermission());
  }

  Future<void> _maybeRequestPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyAsked = prefs.getBool('notification_permission_requested') ?? false;
      if (alreadyAsked) return;

      // Mark as asked so we don't repeatedly prompt on subsequent launches.
      await prefs.setBool('notification_permission_requested', true);

      // Request permission from FCM. We don't block startup on this.
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        final allowed = (settings.authorizationStatus == AuthorizationStatus.authorized) || (settings.authorizationStatus == AuthorizationStatus.provisional);
        await prefs.setBool('notifications_enabled', allowed);
      } catch (e) {
        // Some platforms may throw when calling requestPermission; fall back to not enabled.
        await prefs.setBool('notifications_enabled', false);
      }
    } catch (e) {
      // ignore errors silently; permission prompt is non-critical
      debugPrint('FirstRunInitializer error: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
