import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'providers/user_provider.dart';
import 'auth_gate.dart';

String backendBaseUrl = "http://127.0.0.1:8000";

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Background message received: ${message.messageId}');
}

// Request notification permission once per device/app install. This does not
// change UI — it simply triggers the OS permission dialog (where supported)
// the first time the app runs.
Future<void> _requestNotificationPermissionIfFirstRun() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final asked = prefs.getBool('notifications_permission_asked') ?? false;
    if (asked) return;

    final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final authorized = settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional;
    await prefs.setBool('notifications_permission_asked', true);
    await prefs.setBool('notifications_enabled', authorized);
  } catch (e) {
    // best-effort: ignore errors (for example on platforms where permissions
    // are not supported or SharedPreferences fails). Do not crash the app.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // Ask for notification permission on first app launch (best-effort, no UI changes)
  _requestNotificationPermissionIfFirstRun();

  // Load persisted UI settings before building providers so app starts with
  // the user's saved theme and language (persisted in SharedPreferences).
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = (prefs.getString('theme_mode') ?? 'DARK').toUpperCase();
  final savedLang = prefs.getString('language_code');

  final themeNotifier = ThemeNotifier(savedTheme);
  final localeProvider = LocaleProvider();
  if (savedLang != null && savedLang.isNotEmpty) {
    localeProvider.setLocale(savedLang);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => localeProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => themeNotifier),
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
      child: const AuthGate(),
    );
  }
}
