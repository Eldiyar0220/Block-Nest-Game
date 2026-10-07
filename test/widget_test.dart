import 'package:block_nest/app_controller.dart';
import 'package:block_nest/main.dart';
import 'package:block_nest/storage/progress_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
  });

  testWidgets('shows the score and rotates a piece', (tester) async {
    await _phone(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await _frames(tester);

    expect(find.text('Block Nest'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Сложный'), findsOneWidget);
    expect(find.text('скоро'), findsNothing);
    expect(find.byKey(const Key('playfield')), findsNothing);

    await _enter(tester, 'level-medium');
    expect(find.textContaining('исчезнут'), findsOneWidget);
    expect(find.byKey(const Key('score')), findsOneWidget);
    expect(find.text('Счёт обнулится.'), findsNothing);
    expect(find.textContaining('парами'), findsWidgets);
    await _backToMenu(tester);

    await _enter(tester, 'level-hard');
    expect(find.textContaining('часто'), findsWidgets);
    await _backToMenu(tester);

    await _enter(tester, 'level-easy');
    expect(
      tester.widget<IconButton>(find.byKey(const Key('undo-button'))).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches between light and dark and mutes sound', (
    tester,
  ) async {
    await _phone(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await _frames(tester);

    await tester.tap(find.byKey(const Key('theme-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const Key('theme-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('sound-button')));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });

  testWidgets('fits on a narrow phone', (tester) async {
    await _phone(tester, const Size(360, 640));
    await tester.pumpWidget(_app());
    await _frames(tester);
    expect(tester.takeException(), isNull);
    await _enter(tester, 'level-easy');
    expect(find.textContaining('рекорд'), findsOneWidget);

    await tester.tap(find.byTooltip('Заново'));
    await tester.pump();
    expect(find.text('Block Nest'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _enter(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)).hitTestable());
  await _settle(tester);
}

Future<void> _backToMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('menu-button')).hitTestable());
  await _settle(tester);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _phone(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app() {
  return BlockNestApp(
    enableAudio: false,
    controller: AppController(
      initial: AppSettings.initial,
      store: MemoryStore(),
    ),
  );
}
