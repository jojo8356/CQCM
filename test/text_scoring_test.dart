import 'package:cqcm/services/text_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 17 mots : en tant que client je veux payer en carte bancaire sans contact
  // afin d acheter mon pain
  const reference =
      'En tant que client je veux payer en carte bancaire sans contact '
      'afin d acheter mon pain';

  group('TextScorer.tokenize', () {
    test('ignore ponctuation, majuscules et accents', () {
      expect(TextScorer.tokenize(
        'L\'Étudiant, un professeur — l\'EDT (ne pas gérer)',
      ), [
        'le',
        'etudiant',
        'un',
        'professeur',
        'le',
        'edt',
        'ne',
        'pas',
        'gerer',
      ]);
    });

    test('ramène les élisions à leur mot complet', () {
      expect(
        TextScorer.tokenize("En tant qu'étudiant afin d'acheter"),
        ['en', 'tant', 'que', 'etudiant', 'afin', 'de', 'acheter'],
      );
      expect(
        TextScorer.tokenize('en tant que etudiant afin de acheter'),
        ['en', 'tant', 'que', 'etudiant', 'afin', 'de', 'acheter'],
      );
    });

    test('conserve les chiffres et les sigles', () {
      expect(
        TextScorer.tokenize('TPE : mes 2 TD de 14h'),
        ['tpe', 'mes', '2', 'td', 'de', '14', 'h'],
      );
    });

    test('découpe les mots à tirets et gère une chaîne vide', () {
      expect(TextScorer.tokenize('sans-contact'), ['sans', 'contact']);
      expect(TextScorer.tokenize('   '), isEmpty);
    });
  });

  group('TextScorer.score', () {
    test('une recopie exacte vaut 100 %', () {
      final score = TextScorer.score(reference, const [reference]);

      expect(score.accuracyPercent, 100);
      expect(score.expectedWordCount, 17);
      expect(score.matchedWordCount, 17);
      expect(score.isPerfect, isTrue);
      expect(score.isValidated, isTrue);
      expect(score.missingWords, isEmpty);
    });

    test('la ponctuation, les majuscules et les accents sont neutralisés', () {
      final score = TextScorer.score(
        "EN TANT QUE CLIENT, je veux payer en carte bancaire sans contact ; "
        "afin d'acheter mon pain !",
        const [reference],
      );

      expect(score.accuracyPercent, 100);
      expect(score.isPerfect, isTrue);
    });

    test('compte les mots manquants et le pourcentage de validation', () {
      final twoWords = TextScorer.score(
        reference.replaceFirst(' sans contact', ''),
        const [reference],
      );

      expect(twoWords.matchedWordCount, 15);
      expect(twoWords.accuracyPercent, 88);
      expect(twoWords.missingWords, ['sans', 'contact']);
      expect(twoWords.isValidated, isFalse);

      final oneWord = TextScorer.score(
        reference.replaceFirst(' contact', ''),
        const [reference],
      );

      expect(oneWord.accuracyPercent, 94);
      expect(oneWord.isValidated, isFalse, reason: 'seuil strict de 95 %');
    });

    test('repère les fautes de frappe sans compter le mot comme juste', () {
      final score = TextScorer.score(
        reference.replaceFirst('bancaire', 'bancaires'),
        const [reference],
      );

      expect(score.typoWordCount, 1);
      expect(score.typoWords, ['bancaires']);
      expect(score.matchedWordCount, 16);
      expect(score.accuracyPercent, 94);
    });

    test('signale les mots en trop et calcule la précision', () {
      final score = TextScorer.score(
        '$reference svp',
        const [reference],
      );

      expect(score.accuracyPercent, 100);
      expect(score.extraWordCount, 1);
      expect(score.isPerfect, isFalse);
      expect(score.precision, closeTo(17 / 18, 1e-9));
      expect(score.similarityPercent, 97);
    });

    test('accepte plusieurs réponses de référence (cas « OU »)', () {
      const first =
          'En tant que secrétaire je veux changer les jours et heures des TD '
          "d'un professeur afin de répondre à sa demande de changement de son EDT";
      const second =
          'En tant que secrétaire je veux changer les jours et heures des TD '
          "des professeurs afin de gérer l'EDT";

      final score = TextScorer.score(second, const [first, second]);

      expect(score.accuracyPercent, 100);
      expect(score.isPerfect, isTrue);
    });

    test('une réponse vide vaut 0 %', () {
      final score = TextScorer.score('   ', const [reference]);

      expect(score.accuracyPercent, 0);
      expect(score.isEmpty, isTrue);
      expect(score.isValidated, isFalse);
    });

    test('editDistance mesure les fautes caractère par caractère', () {
      expect(TextScorer.editDistance('carte', 'carte'), 0);
      expect(TextScorer.editDistance('carte', 'cartes'), 1);
      expect(TextScorer.editDistance('recuperer', 'recupere'), 1);
      expect(TextScorer.editDistance('pain', 'pains'), 1);
      expect(TextScorer.editDistance('', 'abc'), 3);
    });
  });

  group('ConstraintCheck', () {
    test('extrait le mot interdit d\'une contrainte', () {
      expect(TextScorer.forbiddenWordsOf('ne pas utiliser le verbe payer'), [
        'payer',
      ]);
      expect(TextScorer.forbiddenWordsOf('ne pas utiliser le verbe gérer'), [
        'gerer',
      ]);
      expect(TextScorer.forbiddenWordsOf('détailler les actions'), isEmpty);
    });

    test('signale le mot interdit présent dans la copie', () {
      final check = ConstraintCheck.evaluate(
        constraints: const ['ne pas utiliser le verbe payer'],
        typed: 'En tant que client je veux payer en carte bancaire',
        references: const ['En tant que client je veux régler en carte bancaire'],
      );

      expect(check.hasConstraints, isTrue);
      expect(check.isSatisfied, isFalse);
      expect(check.violatedWords, ['payer']);
      expect(check.creditedWords, isEmpty);
      expect(check.avoidedWords, isEmpty);
    });

    test('signale aussi le mot interdit absent de la copie', () {
      final check = ConstraintCheck.evaluate(
        constraints: const ['ne pas utiliser le verbe payer'],
        typed: 'En tant que client je veux régler en carte bancaire',
        references: const ['En tant que client je veux régler en carte bancaire'],
      );

      expect(check.isSatisfied, isTrue);
      expect(check.avoidedWords, ['payer']);
      expect(check.violatedWords, isEmpty);
    });

    test('ne signale rien quand la réponse officielle utilise le mot', () {
      final check = ConstraintCheck.evaluate(
        constraints: const ['ne pas utiliser le verbe payer'],
        typed: "Je veux lire le montant à payer sur le TPE",
        references: const ["Lire le montant à payer sur le TPE"],
      );

      expect(check.isSatisfied, isTrue);
      expect(check.creditedWords, ['payer']);
      expect(check.violatedWords, isEmpty);
    });
  });

  group('UserStoryStructure', () {
    test('détecte les trois parties d\'une user story', () {
      final structure = UserStoryStructure.of(
        'En tant que client je veux payer en carte bancaire afin d acheter mon pain',
      );

      expect(structure.hasRole, isTrue);
      expect(structure.hasNeed, isTrue);
      expect(structure.hasGoal, isTrue);
      expect(structure.isComplete, isTrue);
      expect(structure.missingParts, isEmpty);
    });

    test('liste les parties manquantes', () {
      final structure = UserStoryStructure.of('Un client achète du pain');

      expect(structure.isComplete, isFalse);
      expect(structure.missingParts, ['En tant que…', 'Je veux…', 'Afin de…']);
    });

    test('reconnaît « Afin d\'acheter » et « En tant qu\'étudiant »', () {
      final structure = UserStoryStructure.of(
        "En tant qu'étudiant je veux réviser afin d'acheter",
      );

      expect(structure.hasGoal, isTrue);
      expect(structure.hasRole, isTrue);
      expect(structure.isComplete, isTrue);
    });
  });
}
