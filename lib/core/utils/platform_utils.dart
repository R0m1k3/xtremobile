/// Platform utilities - conditional export
/// Uses web implementation on web, stub on other platforms
library;

export 'platform_utils_stub.dart'
    if (dart.library.html) 'platform_utils_web.dart';
