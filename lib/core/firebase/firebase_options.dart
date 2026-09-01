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
    apiKey: 'AIzaSyCrisisMeshAndroidBridgePlaceholder123',
    appId: '1:100000000000:android:crisismeshapp000000',
    messagingSenderId: '100000000000',
    projectId: 'crisismesh-app',
    storageBucket: 'crisismesh-app.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCrisisMeshIOSBridgePlaceholder123',
    appId: '1:100000000000:ios:crisismeshapp000000',
    messagingSenderId: '100000000000',
    projectId: 'crisismesh-app',
    storageBucket: 'crisismesh-app.appspot.com',
    iosBundleId: 'com.crisismesh.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCrisisMeshWebBridgePlaceholder123',
    appId: '1:100000000000:web:crisismeshapp000000',
    messagingSenderId: '100000000000',
    projectId: 'crisismesh-app',
    storageBucket: 'crisismesh-app.appspot.com',
  );
}
