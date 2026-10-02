import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/level.dart';

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.soundOn,
    required this.level,
    required this.bestEasy,
    required this.bestMedium,
    required this.bestHard,
  });

  final ThemeMode themeMode;
  final bool soundOn;
  final NestLevel level;
  final int bestEasy;
  final int bestMedium;
  final int bestHard;

  static const initial = AppSettings(
    themeMode: ThemeMode.system,
    soundOn: true,
    level: NestLevel.easy,
    bestEasy: 0,
    bestMedium: 0,
    bestHard: 0,
  );
}

abstract class ProgressStore {
  Future<void> save(AppSettings settings);
}

class MemoryStore implements ProgressStore {
  AppSettings? last;

  @override
  Future<void> save(AppSettings settings) async {
    last = settings;
  }
}

class PrefsStore implements ProgressStore {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _open() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<AppSettings> load() async {
    final prefs = await _open();
    return AppSettings(
      themeMode: _decodeTheme(prefs.getString('theme')),
      soundOn: prefs.getBool('sound') ?? true,
      level: _decodeLevel(prefs.getString('level')),
      bestEasy: prefs.getInt('best_easy') ?? prefs.getInt('best') ?? 0,
      bestMedium: prefs.getInt('best_medium') ?? 0,
      bestHard: prefs.getInt('best_hard') ?? 0,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await _open();
    await prefs.setString('theme', settings.themeMode.name);
    await prefs.setBool('sound', settings.soundOn);
    await prefs.setString('level', settings.level.name);
    await prefs.setInt('best_easy', settings.bestEasy);
    await prefs.setInt('best_medium', settings.bestMedium);
    await prefs.setInt('best_hard', settings.bestHard);
  }
}

NestLevel _decodeLevel(String? raw) {
  return switch (raw) {
    'medium' => NestLevel.medium,
    'hard' => NestLevel.hard,
    _ => NestLevel.easy,
  };
}

ThemeMode _decodeTheme(String? raw) {
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
