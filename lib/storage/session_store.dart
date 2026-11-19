// Platform storage selector. On the VM (Windows, Android, iOS) the file-based
// implementation is used; Flutter Web gets an in-memory implementation for the
// UI preview, because path_provider and dart:io are unavailable there.
export 'session_store_io.dart'
    if (dart.library.js_interop) 'session_store_web.dart';
