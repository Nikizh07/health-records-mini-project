import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/services/local_cache_service.dart';
import 'firebase_options.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'routes/app_router.dart';

void main() async {
  // Preserve the native splash until we finish initializing
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Enforce HTTPS security before any network requests take place
  AppConstants.validateNetworkSecurity();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Hive offline cache
  await LocalCacheService.init();

  // All init done — remove the splash screen
  FlutterNativeSplash.remove();

  runApp(
    // ProviderScope stores the state of all Riverpod providers
    const ProviderScope(
      child: MigrantHealthApp(),
    ),
  );
}

class MigrantHealthApp extends ConsumerWidget {
  const MigrantHealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeNotifierProvider);

    return MaterialApp.router(
      title: 'Migrant Worker Health Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      locale: currentLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
