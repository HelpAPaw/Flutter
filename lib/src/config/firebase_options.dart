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
        return macos;
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDSFSwZNWu-b69HkmJaz4vnp50mHarVE_o',
    appId: '1:820468452348:web:7b665be1519be3903f0079',
    messagingSenderId: '820468452348',
    projectId: 'flutter-fire-373a7',
    authDomain: 'flutter-fire-373a7.firebaseapp.com',
    databaseURL: 'https://flutter-fire-373a7-default-rtdb.firebaseio.com',
    storageBucket: 'flutter-fire-373a7.appspot.com',
    measurementId: 'G-RS2GXQEFNL',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD-mpO4iSojfKkFW0SPUsPpqQ7Gq5Gadc4',
    appId: '1:820468452348:android:6723be9ed5d3ecbe3f0079',
    messagingSenderId: '820468452348',
    projectId: 'flutter-fire-373a7',
    databaseURL: 'https://flutter-fire-373a7-default-rtdb.firebaseio.com',
    storageBucket: 'flutter-fire-373a7.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBrBqhxQpbvLGATzMPaDf_sskQI_O9cczE',
    appId: '1:820468452348:ios:46814f32837c8d913f0079',
    messagingSenderId: '820468452348',
    projectId: 'flutter-fire-373a7',
    databaseURL: 'https://flutter-fire-373a7-default-rtdb.firebaseio.com',
    storageBucket: 'flutter-fire-373a7.appspot.com',
    iosClientId: '820468452348-m97ok7j0i3qn636lihk3nk2i03qfgjt5.apps.googleusercontent.com',
    iosBundleId: 'dev.helpapaw.helpAPaw',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBrBqhxQpbvLGATzMPaDf_sskQI_O9cczE',
    appId: '1:820468452348:ios:5f8ff04042f7f3b03f0079',
    messagingSenderId: '820468452348',
    projectId: 'flutter-fire-373a7',
    databaseURL: 'https://flutter-fire-373a7-default-rtdb.firebaseio.com',
    storageBucket: 'flutter-fire-373a7.appspot.com',
    iosClientId: '820468452348-ohr43tlrndcf2bte4m4counar07vebcs.apps.googleusercontent.com',
    iosBundleId: 'dev.helpapaw.helpAPaw.RunnerTests',
  );
}
