/// Web stub for NearbyPayloadHelper.
/// On Flutter Web, Payload/PayloadType from nearby_connections don't exist.
/// These methods are never called on Web since WebMeshTransport never fires callbacks.
class NearbyPayloadHelper {
  NearbyPayloadHelper._();

  static dynamic getType(dynamic payload) => null;
  static bool isBytes(dynamic type) => false;
  static List<int>? getBytes(dynamic payload) => null;
}

/// Web stub for NearbyStatusHelper.
/// On Flutter Web, nearby_connections is not available.
/// This helper always returns false — the Web mesh transport never fires callbacks anyway.
class NearbyStatusHelper {
  NearbyStatusHelper._();

  static bool isConnected(dynamic status) => false;
}
