import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/crubik_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(WakelockPlus.enable());
  runApp(const CrubikApp());
}
