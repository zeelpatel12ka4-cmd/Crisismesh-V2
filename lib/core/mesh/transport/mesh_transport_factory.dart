// Conditional export: on Web (dart.library.html available), use the Web no-op factory.
// On native (dart.library.io, e.g. Android/iOS), use the native factory.
export 'mesh_transport_native.dart'
    if (dart.library.html) 'mesh_transport_web.dart';
