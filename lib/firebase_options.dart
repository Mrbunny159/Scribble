import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBhZdHSY2l6fCQTxu7iSvNHY1zKQbBGzZw',
    appId: '1:10375589533:web:e81d840be92f46666aee74',
    messagingSenderId: '10375589533',
    projectId: 'scribble-6d33a',
    storageBucket: 'scribble-6d33a.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBhZdHSY2l6fCQTxu7iSvNHY1zKQbBGzZw',
    appId: '1:10375589533:android:e81d840be92f46666aee74',
    messagingSenderId: '10375589533',
    projectId: 'scribble-6d33a',
    storageBucket: 'scribble-6d33a.firebasestorage.app',
  );
}
