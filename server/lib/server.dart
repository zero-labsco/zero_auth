/// Public surface of the `zero_auth` demo backend.
///
/// Kept small on purpose: `bin/server.dart` only bootstraps, everything else
/// lives behind this barrel.
library;

export 'src/app.dart';
export 'src/config.dart';
export 'src/logging/logger.dart';
