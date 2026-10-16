/// Outils partagés par les tests de widgets.
///
/// Objectif : que la sortie de `flutter test` ne montre que les vrais échecs.
/// Règles appliquées ici :
///
/// 1. fenêtre agrandie (`useLargeSurface`) plutôt que défilements inutiles ;
/// 2. écran précédent attendu avant de naviguer (`openMenu`,
///    `settleNavigation`) ;
/// 3. finders limités à l'écran concerné (`withinScreen`) ;
/// 4. défilement jamais envoyé à une liste qui ne défile pas ou qui n'est pas
///    l'écran courant (`reveal`).
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

/// Rend [finder] cliquable sans avertissement de hit test.
///
/// Le défilement est fait à la main plutôt qu'avec `scrollUntilVisible` :
///
/// * `scrollUntilVisible` dérive l'origine du geste du centre de la liste et
///   n'accepte pas `warnIfMissed: false` ; si la liste n'est pas cliquable à
///   cet endroit (liste vide, écran recouvert, route en cours de fermeture),
///   `flutter test` imprime un long avertissement de hit test ;
/// * `find.byType(Scrollable).last` peut désigner la liste d'une route en
///   train d'être retirée : on ne défile que sur un `Scrollable` réellement
///   affiché ([_visibleScrollable]) ;
/// * une liste dont le contenu tient à l'écran (`maxScrollExtent == 0`) n'a
///   rien à faire défiler : aucun geste n'est envoyé.
///
/// [delta] est le pas de défilement : positif vers le bas, négatif vers le
/// haut (pour retrouver un en-tête quand une liste est restée défilée).
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    return;
  }

  final scrollable = _visibleScrollable();
  if (scrollable == null) return;

  final position = tester.state<ScrollableState>(scrollable).position;

  for (var step = 0; step < 30; step++) {
    if (finder.evaluate().isNotEmpty) break;
    // Contenu entièrement visible : rien à faire défiler.
    if (position.maxScrollExtent <= 0) break;
    await tester.drag(scrollable, Offset(0, -delta), warnIfMissed: false);
    await tester.pump();
  }

  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pump();
  }
}

/// Liste réellement affichée (et cliquable) de l'écran courant.
Finder? _visibleScrollable() {
  final hitTestable = find.byType(Scrollable).hitTestable();
  if (hitTestable.evaluate().isNotEmpty) {
    return hitTestable.last;
  }

  final any = find.byType(Scrollable);
  if (any.evaluate().isEmpty) return null;
  return any.last;
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

/// Laisse la transition de route se terminer (et la route sortante quitter
/// l'arbre : le rendu reste sinon « offstage » et fausse les finders).
Future<void> settleNavigation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
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
