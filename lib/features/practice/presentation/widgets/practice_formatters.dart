String formatPracticeDuration(Duration duration) {
  final totalHundredths = duration.inMilliseconds ~/ 10;
  final hundredths = totalHundredths % 100;
  final totalSeconds = totalHundredths ~/ 100;
  final seconds = totalSeconds % 60;
  final minutes = totalSeconds ~/ 60;
  if (minutes > 0) {
    return '$minutes:${seconds.toString().padLeft(2, '0')}.'
        '${hundredths.toString().padLeft(2, '0')}';
  }
  return '$seconds.${hundredths.toString().padLeft(2, '0')}';
}

String formatOptionalPracticeDuration(Duration? duration) =>
    duration == null ? '—' : formatPracticeDuration(duration);
