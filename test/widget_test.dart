import 'package:block_nest/app_controller.dart';
import 'package:block_nest/game/level.dart';
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
    await tester.pumpAndSettle();

    expect(find.text('Block Nest'), findsOneWidget);
    expect(find.textContaining('исчезнут'), findsOneWidget);
    expect(find.text('Лёгкий'), findsOneWidget);
    expect(find.text('запас'), findsOneWidget);
    expect(find.text('Средний'), findsOneWidget);
    expect(find.text('Сложный'), findsOneWidget);
    expect(find.text('скоро'), findsNothing);
    expect(_bombs(), findsNothing);
    expect(find.text('дальше'), findsOneWidget);
    expect(find.byKey(const ValueKey('upcoming-0')), findsOneWidget);
    expect(find.byKey(const Key('score')), findsOneWidget);

    await tester.tap(find.byKey(const Key('level-medium')));
    await tester.pump();
    expect(find.text('Счёт обнулится.'), findsNothing);
    expect(find.textContaining('парами'), findsOneWidget);
    expect(find.textContaining('запас'), findsOneWidget);
    expect(find.text('дальше'), findsNothing);
    expect(find.byKey(const ValueKey('upcoming-0')), findsNothing);
    expect(_bombs(), findsNWidgets(NestLevel.medium.bombPace!.opening));

    await tester.tap(find.byKey(const Key('level-hard')));
    await tester.pump();
    expect(find.text('Счёт обнулится.'), findsNothing);
    expect(find.textContaining('часто'), findsOneWidget);
    expect(find.textContaining('запас'), findsNothing);
    expect(_bombs(), findsNWidgets(NestLevel.hard.bombPace!.opening));

    await tester.tap(find.byKey(const Key('level-easy')));
    await tester.pump();
    expect(_bombs(), findsNothing);
    expect(find.byKey(const ValueKey('upcoming-0')), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('undo-button'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('tray-0')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches between light and dark and mutes sound', (
    tester,
  ) async {
    await _phone(tester, const Size(390, 844));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-button')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const Key('theme-button')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('рекорд'), findsOneWidget);

    await tester.tap(find.byTooltip('Заново'));
    await tester.pump();
    expect(find.text('Block Nest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _bombs() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('bomb-');
  });
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
