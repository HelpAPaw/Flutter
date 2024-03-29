// File generated by FlutterFire CLI.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
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

  static FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBoB7K9lV8yt432J7XymbNWryQ2SXbZPzk',
    appId: '1:757136327951:web:c1bd49f5a3beb6310f2a7a',
    messagingSenderId: '757136327951',
    projectId: 'help-a-paw-dev',
    authDomain: 'help-a-paw-dev.firebaseapp.com',
    storageBucket: 'help-a-paw-dev.appspot.com',
  );

  static FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDFn3Cexv_aWaSIQ6w4i53YQJf-j5_EsNk',
    appId: '1:757136327951:android:be094e7052a38f6e0f2a7a',
    messagingSenderId: '757136327951',
    projectId: 'help-a-paw-dev',
    storageBucket: 'help-a-paw-dev.appspot.com',
  );

  static FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDX000zOUB-F2qL4Wcf-pas3q3ThyHAOVc',
    appId: '1:757136327951:ios:1a56d4871b9a39fa0f2a7a',
    messagingSenderId: '757136327951',
    projectId: 'help-a-paw-dev',
    storageBucket: 'help-a-paw-dev.appspot.com',
    iosClientId:
        '757136327951-9hkvaklhc08pdcc8lfi5vd53c8c61391.apps.googleusercontent.com',
    iosBundleId: 'com.helpapaw.helpapaw',
  );
}
