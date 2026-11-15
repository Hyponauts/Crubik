import '../../domain/solve_average.dart';
import '../../domain/solve_record.dart';

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

String formatSolveResult(SolveRecord solve, {String unavailableLabel = '—'}) =>
    switch (solve.outcome) {
      SolveOutcome.dnf => 'DNF',
      SolveOutcome.dns => 'DNS',
      SolveOutcome.completed when solve.isTimingReliable =>
        formatPracticeDuration(solve.elapsed),
      _ => unavailableLabel,
    };

String formatAverageResult(SolveAverageRecord? average) =>
    switch (average?.status) {
      SolveAverageStatus.completed => formatPracticeDuration(average!.elapsed!),
      SolveAverageStatus.dnf => 'DNF',
      _ => '—',
    };

String formatSolveDateTime(DateTime value, {bool includeYear = true}) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final date = '${twoDigits(local.day)}.${twoDigits(local.month)}';
  final year = includeYear ? '.${local.year}' : '';
  return '$date$year · ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String formatPracticeDelay(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  final seconds = milliseconds / Duration.millisecondsPerSecond;
  final value = milliseconds % Duration.millisecondsPerSecond == 0
      ? seconds.toStringAsFixed(0)
      : seconds
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '$value ${milliseconds == Duration.millisecondsPerSecond ? 'second' : 'seconds'}';
}
