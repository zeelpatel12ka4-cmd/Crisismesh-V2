import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for CrisisMesh.
/// Provides default credentials to allow runtime initialization and testing.
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
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD7uttTa9gITDJc4LmV-8CB7z_ObeiyB0c',
    appId: '1:151182768339:android:c0dbe69764aaeddc0e3c26',
    messagingSenderId: '151182768339',
    projectId: 'crisis-mesh-7e39c',
    storageBucket: 'crisis-mesh-7e39c.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBSFN038EA6JTLb1jcwKIDkRSn_x4BgcJw',
    appId: '1:151182768339:ios:aea9d2639a8ee9d80e3c26',
    messagingSenderId: '151182768339',
    projectId: 'crisis-mesh-7e39c',
    storageBucket: 'crisis-mesh-7e39c.firebasestorage.app',
    iosBundleId: 'com.example.flutterApp1',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAlKHyTjAe9akzPAA41y0GVgp1f4NQBv7I',
    appId: '1:151182768339:web:ea0f8ba437ecaa0f0e3c26',
    messagingSenderId: '151182768339',
    projectId: 'crisis-mesh-7e39c',
    authDomain: 'crisis-mesh-7e39c.firebaseapp.com',
    storageBucket: 'crisis-mesh-7e39c.firebasestorage.app',
    measurementId: 'G-ZBNYFTDKQZ',
  );
}
