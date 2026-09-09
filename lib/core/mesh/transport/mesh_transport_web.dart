import 'mesh_transport.dart';
import 'web_mesh_transport.dart';

/// Creates the Web no-op [MeshTransport]. Nearby Connections is never imported here.
MeshTransport createDefaultMeshTransport() {
  return WebMeshTransport();
}
