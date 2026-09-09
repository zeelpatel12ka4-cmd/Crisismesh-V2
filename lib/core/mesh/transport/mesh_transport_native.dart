import 'package:flutter/foundation.dart';
import 'mesh_transport.dart';
import 'ios_mesh_transport.dart';
import 'android_mesh_transport.dart';

/// Creates the appropriate [MeshTransport] for native (Android/iOS) platforms.
MeshTransport createDefaultMeshTransport() {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return IosMeshTransport();
  }
  return AndroidMeshTransport();
}
