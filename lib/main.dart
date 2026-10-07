import 'dart:async';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'audio/sound_engine.dart';
import 'storage/progress_store.dart';
import 'ui/menu_screen.dart';
import 'ui/nest_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = PrefsStore();
  var settings = AppSettings.initial;
  try {
    settings = await store.load();
  } on Object {
    settings = AppSettings.initial;
  }
  runApp(
    BlockNestApp(
      controller: AppController(initial: settings, store: store),
    ),
  );
}

class BlockNestApp extends StatefulWidget {
  const BlockNestApp({
    super.key,
    required this.controller,
    this.enableAudio = true,
  });

  final AppController controller;
  final bool enableAudio;

  @override
  State<BlockNestApp> createState() => _BlockNestAppState();
}

class _BlockNestAppState extends State<BlockNestApp> {
  late final SoundEngine _sound;

  @override
  void initState() {
    super.initState();
    _sound = SoundEngine(enabled: widget.controller.soundOn);
    if (widget.enableAudio) unawaited(_sound.init());
    widget.controller.addListener(_syncSound);
  }

  void _syncSound() {
    _sound.enabled = widget.controller.soundOn;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSound);
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Block Nest',
          debugShowCheckedModeBanner: false,
          theme: nestTheme(Brightness.light),
          darkTheme: nestTheme(Brightness.dark),
          themeMode: widget.controller.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 350),
          themeAnimationCurve: Curves.easeOutCubic,
          home: MenuScreen(controller: widget.controller, sound: _sound),
        );
      },
    );
  }
}
