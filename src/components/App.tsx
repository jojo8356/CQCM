import { createSignal, Show } from 'solid-js';
import QuizMenu, { type QuizMetadata } from './QuizMenu';
import Quiz from './Quiz';

// Import des questions
import questionsCFunctions from '../data/questions.json';
import questionsJavaVariables from '../data/questions-java-variables.json';
import questionsJavaOOPBasics from '../data/questions-java-oop-basics.json';
import questionsGraphes from '../data/questions-graphes-non-orientes.json';
import questionsJavaComposition from '../data/questions-java-composition.json';
import questionsJavaExceptions from '../data/questions-java-exceptions.json';

type Question = {
  id: number;
  question: string;
  options: string[];
  correctIndex: number | number[];
  explanation?: string;
  category?: string;
};

// Map des questionnaires
const questionsMap: Record<string, Question[]> = {
  'questions.json': questionsCFunctions as Question[],
  'questions-java-variables.json': questionsJavaVariables as Question[],
  'questions-java-oop-basics.json': questionsJavaOOPBasics as Question[],
  'questions-graphes-non-orientes.json': questionsGraphes as Question[],
  'questions-java-composition.json': questionsJavaComposition as Question[],
  'questions-java-exceptions.json': questionsJavaExceptions as Question[],
};

export default function App() {
  const [selectedQuiz, setSelectedQuiz] = createSignal<QuizMetadata | null>(null);
  const [questions, setQuestions] = createSignal<Question[]>([]);

  const handleSelectQuiz = (quiz: QuizMetadata) => {
    const quizQuestions = questionsMap[quiz.fileName];
    if (quizQuestions) {
      setQuestions(quizQuestions);
      setSelectedQuiz(quiz);
    } else {
      console.error('Questionnaire non trouvé:', quiz.fileName);
      alert('Impossible de charger le questionnaire. Veuillez réessayer.');
    }
  };

  const handleBack = () => {
    setSelectedQuiz(null);
    setQuestions([]);
  };

  return (
    <Show
      when={selectedQuiz()}
      fallback={<QuizMenu onSelectQuiz={handleSelectQuiz} />}
    >
      {(quiz) => (
        <Quiz
          questions={questions()}
          quizTitle={quiz().title}
          onBack={handleBack}
        />
      )}
    </Show>
  );
}
