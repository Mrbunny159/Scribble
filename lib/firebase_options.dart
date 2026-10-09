import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: dotenv.maybeGet('FIREBASE_API_KEY') ??
        const String.fromEnvironment(
          'FIREBASE_API_KEY',
          defaultValue: 'AIzaSyBhZdHSY2l6fCQTxu7iSvNHY1zKQbBGzZw',
        ),
    appId: dotenv.maybeGet('FIREBASE_APP_ID_WEB') ??
        const String.fromEnvironment(
          'FIREBASE_APP_ID_WEB',
          defaultValue: '1:10375589533:web:e81d840be92f46666aee74',
        ),
    messagingSenderId: dotenv.maybeGet('FIREBASE_MESSAGING_SENDER_ID') ??
        const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: '10375589533',
        ),
    projectId: dotenv.maybeGet('FIREBASE_PROJECT_ID') ??
        const String.fromEnvironment(
          'FIREBASE_PROJECT_ID',
          defaultValue: 'scribble-6d33a',
        ),
    storageBucket: dotenv.maybeGet('FIREBASE_STORAGE_BUCKET') ??
        const String.fromEnvironment(
          'FIREBASE_STORAGE_BUCKET',
          defaultValue: 'scribble-6d33a.firebasestorage.app',
        ),
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: dotenv.maybeGet('FIREBASE_API_KEY') ??
        const String.fromEnvironment(
          'FIREBASE_API_KEY',
          defaultValue: 'AIzaSyBhZdHSY2l6fCQTxu7iSvNHY1zKQbBGzZw',
        ),
    appId: dotenv.maybeGet('FIREBASE_APP_ID_ANDROID') ??
        const String.fromEnvironment(
          'FIREBASE_APP_ID_ANDROID',
          defaultValue: '1:10375589533:android:e81d840be92f46666aee74',
        ),
    messagingSenderId: dotenv.maybeGet('FIREBASE_MESSAGING_SENDER_ID') ??
        const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: '10375589533',
        ),
    projectId: dotenv.maybeGet('FIREBASE_PROJECT_ID') ??
        const String.fromEnvironment(
          'FIREBASE_PROJECT_ID',
          defaultValue: 'scribble-6d33a',
        ),
    storageBucket: dotenv.maybeGet('FIREBASE_STORAGE_BUCKET') ??
        const String.fromEnvironment(
          'FIREBASE_STORAGE_BUCKET',
          defaultValue: 'scribble-6d33a.firebasestorage.app',
        ),
  );
}
