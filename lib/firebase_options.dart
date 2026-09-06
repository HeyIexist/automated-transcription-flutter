import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for linux.');
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB4cvdrOc5obQgrIw6zsnP1ZepYLr3rYN0',
    appId: '1:39027424:web:ba2e734163f07d18524685',
    messagingSenderId: '39027424',
    projectId: 'flutter-chat-app-348da',
    authDomain: 'meeting-intelligence.firebaseapp.com',
    storageBucket: 'flutter-chat-app-348da.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0IL7FDZCA6o-KPApe-RCpVmKaLY0N3vs',
    appId: '1:39027424:android:4f27468a408e6012524685',
    messagingSenderId: '39027424',
    projectId: 'flutter-chat-app-348da',
    storageBucket: 'flutter-chat-app-348da.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDmesik0yZxhv1ITl4prvXdfd6ZuBTjUnw',
    appId: '1:39027424:ios:4670c8011783cf09524685',
    messagingSenderId: '39027424',
    projectId: 'flutter-chat-app-348da',
    storageBucket: 'flutter-chat-app-348da.firebasestorage.app',
    iosBundleId: 'com.tcs.ai.frontend',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDmesik0yZxhv1ITl4prvXdfd6ZuBTjUnw',
    appId: '1:39027424:ios:4670c8011783cf09524685',
    messagingSenderId: '39027424',
    projectId: 'flutter-chat-app-348da',
    storageBucket: 'flutter-chat-app-348da.firebasestorage.app',
    iosBundleId: 'com.tcs.ai.frontend',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyB4cvdrOc5obQgrIw6zsnP1ZepYLr3rYN0',
    appId: '1:39027424:web:ba2e734163f07d18524685',
    messagingSenderId: '39027424',
    projectId: 'flutter-chat-app-348da',
    authDomain: 'flutter-chat-app-348da.firebaseapp.com',
    storageBucket: 'flutter-chat-app-348da.firebasestorage.app',
  );
}
