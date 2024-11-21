// File generated by FlutterFire CLI.
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
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0LuaRZaBtuVoyvbTas1NeG0E2PqXW-Rw',
    appId: '1:221500400769:android:b4b40e8d2cb728bd489980',
    messagingSenderId: '221500400769',
    projectId: 'spiromatik-9feb6',
    databaseURL: 'https://spiromatik-9feb6-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'spiromatik-9feb6.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAPFbINl7SSTTJKyUlYyvbpQzXOC4eCOSk',
    appId: '1:221500400769:ios:53276c5f1dc97cf8489980',
    messagingSenderId: '221500400769',
    projectId: 'spiromatik-9feb6',
    databaseURL: 'https://spiromatik-9feb6-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'spiromatik-9feb6.firebasestorage.app',
    iosBundleId: 'com.spiro.spiroble',
  );
}
