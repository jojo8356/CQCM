import 'dart:io';

import 'package:cqcm/main.dart';
import 'package:cqcm/services/ui_zoom_controller.dart';
import 'package:cqcm/services/ui_zoom_store.dart';
import 'package:cqcm/widgets/ui_zoom_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/widget_helpers.dart';

/// Enfonce Ctrl, appuie sur [key], relâche tout, puis reconstruit l'arbre.
Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Application de test minimale, avec un contrôleur observable.
Widget probeApp(UiZoomController controller, {Widget? home}) {
  return MaterialApp(
    builder: (context, child) => UiZoomScope(
      controller: controller,
      persist: false,
      child: child,
    ),
    home: home ?? const Scaffold(body: Center(child: Text('sonde'))),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiZoomController', () {
    test('un cran vaut 5 %', () {
      final controller = UiZoomController();
      expect(controller.percent, 100);

      controller.zoomIn();
      expect(controller.percent, 105);
      expect(controller.zoom, closeTo(1.05, 1e-9));

      controller.zoomOut();
      controller.zoomOut();
      expect(controller.percent, 95);
      expect(controller.zoom, closeTo(0.95, 1e-9));
    });

    test('les bornes sont respectées', () {
      final controller = UiZoomController(zoom: 4);
      expect(controller.percent, UiZoomController.maxPercent);
      controller.zoomIn();
      expect(controller.percent, UiZoomController.maxPercent);

      controller.setZoom(0.1);
      expect(controller.percent, UiZoomController.minPercent);
      controller.zoomOut();
      expect(controller.percent, UiZoomController.minPercent);
    });

    test('notifie à chaque changement, jamais au-delà des bornes', () {
      final controller = UiZoomController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.zoomIn(); // 105
      controller.reset(); // 100
      controller.zoomOut(); // 95
      controller.zoomOut(); // 90
      controller.reset(); // 100
      expect(notifications, 5);

      controller.reset(); // déjà 100
      expect(notifications, 5);
    });
  });

  group('raccourcis clavier', () {
    testWidgets('Ctrl + "+" agrandit de 5 %', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester);

      final before = tester.getRect(find.text('CQCM'));
      await pressCtrl(tester, LogicalKeyboardKey.equal);
      final after = tester.getRect(find.text('CQCM'));

      expect(after.width / before.width, closeTo(1.05, 0.01));
    });

    testWidgets('Ctrl + "-" réduit de 5 %', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester);

      final before = tester.getRect(find.text('CQCM'));
      await pressCtrl(tester, LogicalKeyboardKey.minus);
      final after = tester.getRect(find.text('CQCM'));

      expect(after.width / before.width, closeTo(0.95, 0.01));
    });

    testWidgets('Ctrl + "0" revient à 100 %', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester);

      final before = tester.getRect(find.text('CQCM'));
      await pressCtrl(tester, LogicalKeyboardKey.equal);
      await pressCtrl(tester, LogicalKeyboardKey.equal);
      expect(
        tester.getRect(find.text('CQCM')).width / before.width,
        closeTo(1.10, 0.01),
      );

      await pressCtrl(tester, LogicalKeyboardKey.digit0);
      expect(
        tester.getRect(find.text('CQCM')).width / before.width,
        closeTo(1.0, 0.01),
      );
    });

    testWidgets('sans Ctrl, les touches ne changent rien', (tester) async {
      useLargeSurface(tester);
      await pumpApp(tester);

      final before = tester.getRect(find.text('CQCM'));
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(
        tester.getRect(find.text('CQCM')).width / before.width,
        closeTo(1.0, 0.01),
      );
    });
  });

  group('molette de la souris', () {
    testWidgets('Ctrl + molette : un cran de 5 % par cran', (tester) async {
      useLargeSurface(tester);
      final controller = UiZoomController();
      await tester.pumpWidget(probeApp(controller));

      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      pointer.hover(const Offset(600, 900));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
      await tester.pumpAndSettle();
      expect(controller.percent, 105);

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
      await tester.pumpAndSettle();
      expect(controller.percent, 100);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('sans Ctrl, la molette ne zoome pas', (tester) async {
      useLargeSurface(tester);
      final controller = UiZoomController();
      await tester.pumpWidget(probeApp(controller));

      final pointer = TestPointer(8, PointerDeviceKind.mouse);
      pointer.hover(const Offset(600, 900));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
      await tester.pumpAndSettle();

      expect(controller.percent, 100);
    });

    testWidgets('fonctionne au-dessus d une liste défilante', (tester) async {
      useLargeSurface(tester);
      final controller = UiZoomController();
      await tester.pumpWidget(
        probeApp(
          controller,
          home: Scaffold(
            body: ListView.builder(
              itemCount: 80,
              itemBuilder: (context, index) => SizedBox(
                height: 40,
                child: Text('ligne $index'),
              ),
            ),
          ),
        ),
      );

      final pointer = TestPointer(9, PointerDeviceKind.mouse);
      pointer.hover(const Offset(600, 900));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(controller.percent, 105);
    });
  });

  group('UiZoomStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cqcm-zoom-test-');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('fichier absent : pas de zoom mémorisé', () async {
      expect(
        await UiZoomStore.loadZoom(directoryPath: directory.path),
        isNull,
      );
    });

    test('écrit puis relit le zoom, en JSON lisible', () async {
      expect(
        await UiZoomStore.saveZoom(1.15, directoryPath: directory.path),
        isTrue,
      );
      expect(
        await UiZoomStore.loadZoom(directoryPath: directory.path),
        closeTo(1.15, 1e-9),
      );

      final contents = File(
        '${directory.path}/${UiZoomStore.fileName}',
      ).readAsStringSync();
      expect(contents, contains('"zoom": 1.15'));
    });

    test('fichier illisible : 100 %, sans exception', () async {
      final file = File('${directory.path}/${UiZoomStore.fileName}');

      file.writeAsStringSync('{pas du json');
      expect(await UiZoomStore.loadZoom(directoryPath: directory.path), isNull);

      file.writeAsStringSync('{"zoom": "grand"}');
      expect(await UiZoomStore.loadZoom(directoryPath: directory.path), isNull);
    });
  });
}
