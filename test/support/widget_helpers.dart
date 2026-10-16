/// Outils partagés par les tests de widgets.
///
/// Objectif : que la sortie de `flutter test` ne montre que les vrais échecs.
/// Règles appliquées ici :
///
/// 1. fenêtre agrandie (`useLargeSurface`) plutôt que défilements inutiles ;
/// 2. écran précédent attendu avant de naviguer (`openMenu`,
///    `settleNavigation`) ;
/// 3. finders limités à l'écran concerné (`withinScreen`) ;
/// 4. défilement uniquement sur une liste affichée qui a de quoi défiler, et
///    retour en haut par la position de défilement (jamais par un geste) :
///    voir `reveal`.
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
/// * `find.byType(Scrollable).last` peut désigner la liste d'une autre route
///   (celle qui se ferme, ou une liste trop courte pour défiler) : on ne
///   défile que sur une liste affichée **capable** de défiler ;
/// * une liste dont le contenu tient à l'écran (`maxScrollExtent == 0`) n'a
///   rien à faire défiler : aucun geste n'est envoyé.
///
/// [delta] indique de quel côté chercher : `delta < 0` pour une cible
/// **au-dessus** (retour en haut : en-tête, bandeau de rappel), `delta > 0`
/// (défaut) pour une cible plus bas (fiche, bouton).
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

  if (delta < 0) {
    // Cible au-dessus : on replace les listes en haut de leur contenu, par
    // leur position de défilement. Aucun geste, donc aucune dépendance au hit
    // test ni à la route au premier plan.
    _resetLists();
    await tester.pump();
    _alignVisible(tester, finder);
    return;
  }

  final scrollable = _scrollableToScroll(tester);
  if (scrollable == null) return;

  final position = tester.state<ScrollableState>(scrollable).position;

  for (var step = 0; step < 30; step++) {
    if (finder.evaluate().isNotEmpty) break;
    if (position.pixels >= position.maxScrollExtent) break;
    await tester.drag(scrollable, Offset(0, -delta), warnIfMissed: false);
    await tester.pump();
  }

  _alignVisible(tester, finder);
}

/// Remet en haut du contenu toutes les listes de l'arbre.
void _resetLists() {
  for (final element in find.byType(Scrollable).evaluate().toList()) {
    final state = (element as StatefulElement).state;
    if (state is! ScrollableState) continue;
    state.position.jumpTo(state.position.minScrollExtent);
  }
}

/// Dernière liste affichée qui a réellement de quoi défiler.
Finder? _scrollableToScroll(WidgetTester tester) {
  final candidates = find.byType(Scrollable).hitTestable().evaluate().toList();
  for (final element in candidates.reversed) {
    final state = (element as StatefulElement).state;
    if (state is! ScrollableState) continue;
    if (state.position.maxScrollExtent <= 0) continue;
    return find.byWidget(state.widget);
  }
  return null;
}

/// Recentre la cible si elle a été trouvée.
Future<void> _alignVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) return;
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
