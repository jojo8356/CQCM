/// Outils partagés par les tests de widgets.
///
/// Deux principes, pour que la sortie de `flutter test` reste propre : seuls
/// les vrais échecs s'affichent.
///
/// 1. La fenêtre de test est agrandie ([useLargeSurface]) : tout le contenu
///    tient à l'écran, donc plus besoin de faire défiler à l'aveugle (un
///    défilement sur une liste qui ne défile pas produit un avertissement de
///    hit test dans la sortie de test).
/// 2. Un écran n'est ouvert que lorsque l'écran précédent a fini de charger
///    ([openMenu]) : les écrans reçoivent un plan déjà chargé et s'affichent
///    au premier rendu, au lieu de courir après un chargement d'assets.
library;

import 'package:cqcm/main.dart';
import 'package:cqcm/widgets/revision_reminder_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Agrandit la fenêtre de test : le contenu des écrans est visible d'un coup.
void useLargeSurface(
  WidgetTester tester, {
  Size size = const Size(1200, 2400),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Monte l'application et attend le menu d'accueil.
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const CQCMApp());
  await pumpUntilFound(tester, find.text('Que veux-tu réviser ?'));
}

/// Attend que le menu ait chargé la progression : son bandeau de rappel est
/// alors affiché, et un plan est disponible pour les écrans suivants.
///
/// On attend le widget (et non un texte) : le bandeau change de libellé selon
/// qu'il reste des phrases à revoir ou non.
Future<void> waitForMenuPlan(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(RevisionReminderBanner));
}

/// Menu d'accueil prêt à naviguer.
Future<void> openMenu(WidgetTester tester) async {
  await pumpApp(tester);
  await waitForMenuPlan(tester);
}

/// Restreint un finder au sous-arbre d'un écran.
///
/// **Indispensable** dès qu'une route en recouvre une autre : les écrans
/// couverts restent présents dans l'arbre et leurs textes sont trouvés par
/// `find.text` (le même énoncé peut donc apparaître deux fois, une fois dans
/// la liste du programme et une fois dans la fiche ouverte).
Finder withinScreen(Type screen, Finder finder) {
  return find.descendant(of: find.byType(screen), matching: finder);
}

/// Rend [finder] cliquable sans avertissement de hit test : défilement
/// seulement si le widget n'est pas déjà affiché.
///
/// [delta] est le pas de défilement : positif vers le bas, négatif vers le
/// haut (pour retrouver un en-tête quand une liste est restée défilée).
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    return;
  }

  await tester.ensureVisible(finder.first);
  await tester.pump();
}

/// Pompe jusqu'à ce que [finder] trouve quelque chose.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 60,
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail(
    'Élément introuvable après $maxPumps pompages : $finder\n'
    'Texte visible : ${visibleTexts(tester)}\n'
    'Rappel : dans une liste défilée, les widgets hors écran ne sont pas '
    'construits (utiliser reveal, avec un delta négatif pour remonter).',
  );
}

/// Laisse la transition de route se terminer.
Future<void> settleNavigation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
}

/// Textes affichés, pour diagnostiquer un test qui échoue.
String visibleTexts(WidgetTester tester, {int limit = 12}) {
  final texts = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data == null || data.trim().isEmpty) {
      continue;
    }
    texts.add(data);
    if (texts.length >= limit) {
      break;
    }
  }
  return texts.isEmpty ? '(aucun texte)' : texts.join(' | ');
}
