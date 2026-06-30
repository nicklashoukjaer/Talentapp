// Platform abstraction: picks the web implementation (dart:html) when compiling
// for web, and the stub implementation on mobile/desktop where dart:html is
// unavailable. Usage in app code: `import 'platform_io.dart';`
export 'platform_io_stub.dart' if (dart.library.html) 'platform_io_web.dart';
