import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';

abstract final class PracticePhasePresentation {
  static String label(PracticePhase phase) => switch (phase) {
    PracticePhase.manualReady => 'READY',
    PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
    PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
    PracticePhase.scrambling => 'SCRAMBLING',
    PracticePhase.inspectionDelay => 'GET READY',
    PracticePhase.inspection => 'INSPECTION',
    PracticePhase.solving => 'SOLVING',
  };

  static Color color(PracticePhase phase) => switch (phase) {
    PracticePhase.needsSolvedCube => CrubikColors.warning,
    PracticePhase.scrambling ||
    PracticePhase.inspectionDelay ||
    PracticePhase.inspection => CrubikColors.cyan,
    PracticePhase.solving => CrubikColors.lime,
    PracticePhase.manualReady ||
    PracticePhase.awaitingCubeState => CrubikColors.muted,
  };

  static Duration displayedTime(PracticeController practice) =>
      switch (practice.phase) {
        PracticePhase.inspectionDelay => practice.preInspectionRemaining,
        PracticePhase.inspection => practice.inspectionRemaining,
        _ => practice.elapsed,
      };

  static bool attemptAborts(PracticeController practice) =>
      practice.phase == PracticePhase.inspectionDelay ||
      practice.phase == PracticePhase.inspection ||
      (practice.smartCubeWorkflowActive &&
          practice.phase == PracticePhase.solving);

  static String primaryActionLabel(PracticeController practice) =>
      switch (practice.phase) {
        PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
        PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
        PracticePhase.scrambling => 'FOLLOW SCRAMBLE',
        PracticePhase.inspectionDelay || PracticePhase.inspection => 'ABORT',
        PracticePhase.solving =>
          practice.smartCubeWorkflowActive ? 'ABORT' : 'STOP & SAVE',
        PracticePhase.manualReady => 'START SOLVE',
      };

  static IconData primaryActionIcon(PracticeController practice) {
    if (attemptAborts(practice)) return Icons.close_rounded;
    if (!practice.smartCubeWorkflowActive &&
        practice.phase == PracticePhase.solving) {
      return Icons.stop_rounded;
    }
    if (practice.smartCubeWorkflowActive) return Icons.sync_rounded;
    return Icons.play_arrow_rounded;
  }
}
