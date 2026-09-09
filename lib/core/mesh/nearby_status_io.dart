import 'package:nearby_connections/nearby_connections.dart';

/// IO (Android) helper for NearbyStatusHelper.
/// Uses the real nearby_connections Status enum.
class NearbyStatusHelper {
  NearbyStatusHelper._();

  static bool isConnected(dynamic status) {
    if (status is Status) {
      return status == Status.CONNECTED;
    }
    return false;
  }
}

/// IO (Android) helper for NearbyPayloadHelper.
/// Uses the real nearby_connections Payload and PayloadType types.
class NearbyPayloadHelper {
  NearbyPayloadHelper._();

  static dynamic getType(dynamic payload) {
    if (payload is Payload) return payload.type;
    return null;
  }

  static bool isBytes(dynamic type) {
    return type == PayloadType.BYTES;
  }

  static List<int>? getBytes(dynamic payload) {
    if (payload is Payload) return payload.bytes;
    return null;
  }
}
