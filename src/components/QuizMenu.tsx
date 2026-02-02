import { createSignal, For, Show } from 'solid-js';
import { FiBook, FiArrowRight, FiFilter } from 'solid-icons/fi';
import data from '../data/data.json';

export type QuizMetadata = {
  id: string;
  title: string;
  description: string;
  category: string;
  difficulty: string;
  questionCount: number;
  fileName: string;
  icon: string;
};

type QuizMenuProps = {
  onSelectQuiz: (quiz: QuizMetadata) => void;
};

const difficultyColors = {
  debutant: 'bg-green-100 text-green-700 border-green-300',
  intermediaire: 'bg-yellow-100 text-yellow-700 border-yellow-300',
  avance: 'bg-red-100 text-red-700 border-red-300'
};

const difficultyLabels = {
  debutant: 'Débutant',
  intermediaire: 'Intermédiaire',
  avance: 'Avancé'
};

export default function QuizMenu(props: QuizMenuProps) {
  const [selectedCategory, setSelectedCategory] = createSignal<string>('all');

  const quizzes = data.quizzes as QuizMetadata[];

  const categories = () => {
    const cats = new Set(quizzes.map(q => q.category));
    return ['all', ...Array.from(cats)];
  };

  const filteredQuizzes = () => {
    const cat = selectedCategory();
    if (cat === 'all') return quizzes;
    return quizzes.filter(q => q.category === cat);
  };

  const getCategoryLabel = (cat: string) => {
    if (cat === 'all') return 'Tous les questionnaires';
    return cat;
  };

  return (
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-6xl mx-auto p-6">
        {/* Header */}
        <div class="text-center mb-12 pt-8">
          <h1 class="text-5xl font-bold mb-4 bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
            QCM Interactifs
          </h1>
          <p class="text-gray-600 text-lg">
            Sélectionnez un questionnaire pour commencer votre apprentissage
          </p>
        </div>

        {/* Filter */}
        <div class="mb-8 flex items-center justify-center gap-2 flex-wrap">
          <FiFilter class="text-gray-500" size={20} />
          <For each={categories()}>
            {(cat) => (
              <button
                onClick={() => setSelectedCategory(cat)}
                class={`px-4 py-2 rounded-lg font-medium transition-all cursor-pointer ${
                  selectedCategory() === cat
                    ? 'bg-blue-600 text-white shadow-lg scale-105'
                    : 'bg-white text-gray-700 hover:bg-blue-50 border border-gray-200'
                }`}
              >
                {getCategoryLabel(cat)}
              </button>
            )}
          </For>
        </div>

        {/* Quiz Grid */}
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <For each={filteredQuizzes()}>
            {(quiz) => (
              <div class="bg-white rounded-xl shadow-lg hover:shadow-2xl transition-all duration-300 overflow-hidden border-2 border-transparent hover:border-blue-300 group">
                <div class="p-6">
                  {/* Icon & Title */}
                  <div class="flex items-start gap-4 mb-4">
                    <div class="text-4xl">{quiz.icon}</div>
                    <div class="flex-1">
                      <h3 class="text-xl font-bold text-gray-800 mb-1 group-hover:text-blue-600 transition-colors">
                        {quiz.title}
                      </h3>
                      <p class="text-sm text-gray-500">{quiz.category}</p>
                    </div>
                  </div>

                  {/* Description */}
                  <p class="text-gray-600 text-sm mb-4 line-clamp-2">
                    {quiz.description}
                  </p>

                  {/* Metadata */}
                  <div class="flex items-center gap-2 mb-4">
                    <span class={`text-xs px-2 py-1 rounded-full border ${
                      difficultyColors[quiz.difficulty as keyof typeof difficultyColors]
                    }`}>
                      {difficultyLabels[quiz.difficulty as keyof typeof difficultyLabels]}
                    </span>
                    <Show when={quiz.questionCount > 0}>
                      <span class="text-xs text-gray-500 flex items-center gap-1">
                        <FiBook size={12} />
                        {quiz.questionCount} questions
                      </span>
                    </Show>
                  </div>

                  {/* Button */}
                  <Show
                    when={quiz.questionCount > 0}
                    fallback={
                      <button
                        disabled
                        class="w-full py-2 px-4 bg-gray-300 text-gray-500 rounded-lg font-medium cursor-not-allowed"
                      >
                        Bientôt disponible
                      </button>
                    }
                  >
                    <button
                      onClick={() => props.onSelectQuiz(quiz)}
                      class="w-full py-2 px-4 bg-gradient-to-r from-blue-600 to-purple-600 text-white rounded-lg font-medium hover:from-blue-700 hover:to-purple-700 transition-all cursor-pointer flex items-center justify-center gap-2 group-hover:scale-105"
                    >
                      Commencer
                      <FiArrowRight class="group-hover:translate-x-1 transition-transform" />
                    </button>
                  </Show>
                </div>
              </div>
            )}
          </For>
        </div>

        {/* Empty State */}
        <Show when={filteredQuizzes().length === 0}>
          <div class="text-center py-16">
            <p class="text-gray-500 text-lg">Aucun questionnaire dans cette catégorie</p>
          </div>
        </Show>
      </div>
    </div>
  );
}
