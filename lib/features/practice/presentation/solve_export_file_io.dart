import 'dart:io';

import 'package:flutter/services.dart';

import '../application/practice_controller.dart';

const _exportChannel = MethodChannel('crubik/solve_export');

/// Saves the export through Android's system document picker without sending
/// the potentially large JSON payload through a platform channel.
Future<bool> saveSolveExportFile(PracticeController practice) async {
  final sessionId = practice.selectedSession.id;
  final cachePath = await _exportChannel.invokeMethod<String>(
    'chooseDestination',
    {'fileName': 'crubik-solves.json'},
  );
  if (cachePath == null) return false;

  Directory? directory;
  var saved = false;
  try {
    directory = await Directory(cachePath).createTemp('crubik-export-');
    final file = File('${directory.path}/crubik-solves.json');
    final output = file.openWrite();
    // close() reports sink failures after export has finished producing JSON.
    output.done.ignore();
    try {
      await practice.writeExportJson(output, sessionId: sessionId);
    } finally {
      await output.close();
    }

    await _exportChannel.invokeMethod<void>('writeChosen', {
      'sourcePath': file.path,
    });
    saved = true;
    return true;
  } on FileSystemException {
    throw PlatformException(code: 'export_prepare_failed');
  } finally {
    try {
      await directory?.delete(recursive: true);
    } on FileSystemException {
      // Cache cleanup must not turn a successful save into a reported failure.
    }
    if (!saved) {
      try {
        await _exportChannel.invokeMethod<void>('clearDestination');
      } on PlatformException {
        // The provider may not support cleanup of a failed export.
      }
    }
  }
}
