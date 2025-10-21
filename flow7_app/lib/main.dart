import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'providers/user_provider.dart'; // USER PROVIDER IMPORT EDİLDİ
import 'auth_gate.dart';

String backendBaseUrl = "http://127.0.0.1:8000";

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // KRİTİK DEĞİŞİKLİK: MultiProvider kullanılarak hem Locale hem de UserProvider eklendi
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => LocaleProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()), // UserProvider EKLENDİ
        ChangeNotifierProvider(create: (context) => ThemeNotifier('DARK')), // Theme notifier burada
      ],
      child: const MyApp(),
    ),
  );
}

// Simple Theme notifier kept in main.dart (no extra file)
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
    // Ana Renk Paleti
    //    final Color primaryColor = Colors.cyanAccent.shade400; // Ana Vurgu Rengi
    //    final Color secondaryColor = Colors.deepOrangeAccent.shade400; // İkincil Enerji Rengi
    //
    //    // 1. ÜÇÜNCÜ RENK TANIMLAMASI
    //    final Color tertiaryColor = Colors.purpleAccent.shade200; // Üçüncül Vurgu Rengi (Mor/Eflatun)

    // Palette from design brief (revised light theme colors)
    // New, more pleasant light theme:
    // - primary: richer teal for better depth
    // - secondary: warm indigo for contrast accents
    // - accent/tertiary: fresh mint for CTA highlights
    // - surface/background: very light, soft gray to reduce glare
    const lightPrimary = Color(0xFF00695C);    // deep teal
    const lightSecondary = Color(0xFF6C5CE7);  // indigo-purple
    const lightAccent = Color(0xFF00C896);     // mint / fresh green
    // soften whites for less glare
    const lightSurface = Color(0xFFF8FBFD);    // very soft off-white for cards
    const lightBackground = Color(0xFFF2F6F9); // softer page background (reduced glare)

    const darkPrimary = Color(0xFF4DB6AC);
    const darkSecondary = Color(0xFFC0C0C0);
    const darkSurface = Color(0xFF1E1E1E);
    const darkBackground = Color(0xFF121212);

    final themeNotifier = Provider.of<ThemeNotifier>(context);
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        final localeProvider = Provider.of<LocaleProvider>(context);

        return MaterialApp(
          locale: localeProvider.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateTitle: (context) => "Flow7",
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: lightBackground,
            colorScheme: ColorScheme.light().copyWith(
              primary: lightPrimary,
              onPrimary: Colors.white,
              secondary: lightSecondary,
              onSecondary: Colors.white,
              surface: lightSurface,
              background: lightBackground,
              onBackground: const Color(0xFF0B1B2A), // dark navy text for softer contrast
              error: const Color(0xFFD32F2F),
              onError: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: lightBackground,
              foregroundColor: const Color(0xFF0B1B2A),
              elevation: 0,
              centerTitle: true,
            ),
            cardTheme: CardThemeData(
              color: lightSurface,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFFF6F9FB), // slightly warmer than pure white
              contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: Colors.transparent)),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: lightPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: MaterialStateProperty.all(lightAccent),
              trackColor: MaterialStateProperty.all(lightAccent.withOpacity(0.4)),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: darkBackground,
            colorScheme: ColorScheme.dark().copyWith(
              primary: darkPrimary,
              onPrimary: Colors.black,
              secondary: darkSecondary,
              onSecondary: Colors.black,
              surface: darkSurface,
              background: darkBackground,
              onBackground: Colors.white,
              error: const Color(0xFFD32F2F),
              onError: Colors.white,
            ),
            appBarTheme: AppBarTheme(backgroundColor: darkBackground, foregroundColor: Colors.white, elevation: 0, centerTitle: true),
            cardTheme: CardThemeData(color: darkSurface, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r))),
            inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: darkSurface),
          ),
           themeMode: themeNotifier.mode,
           home: child,
         );
      },
      child: const AuthGate(),
    );
  }
}