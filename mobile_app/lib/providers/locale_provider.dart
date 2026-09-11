import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

/// Supported languages map
const Map<String, String> appSupportedLanguages = {
  'en': 'English',
  'ta': 'தமிழ் (Tamil)',
  'hi': 'हिंदी (Hindi)',
};

/// Helper to convert language code or name to Locale
Locale parseLocale(String? lang) {
  if (lang == null) return const Locale('en');
  final clean = lang.trim().toLowerCase();
  if (clean == 'ta' || clean.contains('tamil') || clean.contains('தமிழ்')) {
    return const Locale('ta');
  }
  if (clean == 'hi' || clean.contains('hindi') || clean.contains('हिंदी')) {
    return const Locale('hi');
  }
  return const Locale('en');
}

/// Helper to convert Locale to standard backend string
String localeToBackendCode(Locale locale) {
  switch (locale.languageCode) {
    case 'ta':
      return 'Tamil';
    case 'hi':
      return 'Hindi';
    case 'en':
    default:
      return 'English';
  }
}

/// StateNotifier to manage current active App Locale
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en'));

  void setLocale(Locale newLocale) {
    if (state != newLocale) {
      state = newLocale;
    }
  }

  void setFromLanguageCode(String lang) {
    final parsed = parseLocale(lang);
    setLocale(parsed);
  }
}

/// Provider exposing the current App Locale
final localeNotifierProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  final notifier = LocaleNotifier();

  // Listen to user's language_pref in auth state to sync initially or on change
  ref.listen<AuthState>(authNotifierProvider, (previous, next) {
    final langPref = next.patientProfile?['language_pref']?.toString();
    if (langPref != null && langPref.isNotEmpty) {
      notifier.setFromLanguageCode(langPref);
    }
  });

  return notifier;
});
