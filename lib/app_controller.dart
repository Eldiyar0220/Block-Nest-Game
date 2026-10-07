import 'dart:async';

import 'package:flutter/material.dart';

import 'game/level.dart';
import 'storage/progress_store.dart';

class AppController extends ChangeNotifier {
  AppController({required AppSettings initial, required this.store})
    : themeMode = initial.themeMode,
      soundOn = initial.soundOn,
      level = initial.level,
      bestEasy = initial.bestEasy,
      bestMedium = initial.bestMedium,
      bestHard = initial.bestHard,
      bestFun = initial.bestFun;

  final ProgressStore store;
  ThemeMode themeMode;
  bool soundOn;
  NestLevel level;
  int bestEasy;
  int bestMedium;
  int bestHard;
  int bestFun;

  int bestFor(NestLevel value) {
    return switch (value) {
      NestLevel.medium => bestMedium,
      NestLevel.hard => bestHard,
      NestLevel.fun => bestFun,
      NestLevel.easy => bestEasy,
    };
  }

  void setLevel(NestLevel value) {
    if (value == level) return;
    level = value;
    notifyListeners();
    unawaited(_persist());
  }

  void toggleTheme(Brightness brightness) {
    themeMode = brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
    unawaited(_persist());
  }

  void toggleSound() {
    soundOn = !soundOn;
    notifyListeners();
    unawaited(_persist());
  }

  void setBest(int value) {
    switch (level) {
      case NestLevel.medium:
        if (value <= bestMedium) return;
        bestMedium = value;
      case NestLevel.hard:
        if (value <= bestHard) return;
        bestHard = value;
      case NestLevel.fun:
        if (value <= bestFun) return;
        bestFun = value;
      case NestLevel.easy:
        if (value <= bestEasy) return;
        bestEasy = value;
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      await store.save(
        AppSettings(
          themeMode: themeMode,
          soundOn: soundOn,
          level: level,
          bestEasy: bestEasy,
          bestMedium: bestMedium,
          bestHard: bestHard,
          bestFun: bestFun,
        ),
      );
    } on Object {
      return;
    }
  }
}
