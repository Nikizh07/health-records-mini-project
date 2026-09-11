// File generated for Firebase Initialization
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBBe_gT78akptIrR72yhIoS65Yfyzmk1dI',
    appId: '1:708133570010:web:587b19ea33c0c8f4656ce3',
    messagingSenderId: '708133570010',
    projectId: 'migrant-workers-89bb8',
    authDomain: 'migrant-workers-89bb8.firebaseapp.com',
    storageBucket: 'migrant-workers-89bb8.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBBe_gT78akptIrR72yhIoS65Yfyzmk1dI',
    appId: '1:708133570010:android:587b19ea33c0c8f4656ce3',
    messagingSenderId: '708133570010',
    projectId: 'migrant-workers-89bb8',
    storageBucket: 'migrant-workers-89bb8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBBe_gT78akptIrR72yhIoS65Yfyzmk1dI',
    appId: '1:708133570010:ios:587b19ea33c0c8f4656ce3',
    messagingSenderId: '708133570010',
    projectId: 'migrant-workers-89bb8',
    storageBucket: 'migrant-workers-89bb8.firebasestorage.app',
    iosBundleId: 'com.migranthealth.mobile_app',
  );
}
