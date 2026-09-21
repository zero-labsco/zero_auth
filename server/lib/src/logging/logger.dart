import 'dart:io';

/// Verbosity levels, ordered by severity.
enum LogLevel { debug, info, warn, error }

/// Minimal structured logger: one timestamped line per event on stdout.
///
/// Output stays ASCII so it renders correctly on Windows consoles too. Set
/// `LOG_LEVEL=debug` to also see per-route debug lines.
final class Logger {
  Logger({LogLevel minimum = LogLevel.info, Stdout? output})
    : _minimum = minimum,
      _out = output ?? stdout;

  final LogLevel _minimum;
  final Stdout _out;

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warn(String message) => _log(LogLevel.warn, message);
  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel level, String message) {
    if (level.index < _minimum.index) return;
    _out.writeln('${_timestamp()} ${_tag(level)} $message');
  }

  static String _timestamp() {
    final now = DateTime.now().toIso8601String();
    // Trim to milliseconds; microseconds only add noise.
    return now.substring(0, now.length - 3);
  }

  static String _tag(LogLevel level) {
    const tags = {
      LogLevel.debug: '[DEBUG]',
      LogLevel.info: '[INFO ]',
      LogLevel.warn: '[WARN ]',
      LogLevel.error: '[ERROR]',
    };
    return tags[level]!;
  }
}
