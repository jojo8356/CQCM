import { createSignal, createMemo, For, Show, onMount, onCleanup } from 'solid-js';
import { Tooltip } from '@kobalte/core/tooltip';
import { FiChevronUp, FiDownload } from 'solid-icons/fi';
import Modal from './Modal';
import Filter, { compressToIntervals } from './Filter';
import questions from '../data/questions.json';

// Types
type Question = {
  id: number;
  question: string;
  options: string[];
  correctIndex: number | number[];
};

// Utils
const formatTime = (ms: number): string => {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
};

// Components
function QuestionCard(props: {
  question: Question;
  index: number;
  onAnswer: (correct: boolean, questionId: number) => void;
}) {
  const [answered, setAnswered] = createSignal(false);
  const [selected, setSelected] = createSignal<Set<number>>(new Set());
  const [result, setResult] = createSignal<'correct' | 'incorrect' | null>(null);

  const correctIndices = createMemo(() =>
    Array.isArray(props.question.correctIndex) ? props.question.correctIndex : [props.question.correctIndex]
  );
  const isMultiple = createMemo(() => correctIndices().length > 1);

  const handleClick = (optIndex: number) => {
    if (answered()) return;

    if (isMultiple()) {
      const newSelected = new Set(selected());
      newSelected.has(optIndex) ? newSelected.delete(optIndex) : newSelected.add(optIndex);
      setSelected(newSelected);

      if (newSelected.size === correctIndices().length) {
        const allCorrect = correctIndices().every(i => newSelected.has(i));
        if (allCorrect) {
          setAnswered(true);
          setResult('correct');
          props.onAnswer(true, props.question.id);
        }
      }
    } else {
      setAnswered(true);
      setSelected(new Set([optIndex]));
      const isCorrect = optIndex === correctIndices()[0];
      setResult(isCorrect ? 'correct' : 'incorrect');
      props.onAnswer(isCorrect, props.question.id);
    }
  };

  const handleDoubleClick = () => {
    if (answered() || selected().size === 0 || !isMultiple()) return;
    setAnswered(true);
    const allCorrect = correctIndices().every(i => selected().has(i)) && selected().size === correctIndices().length;
    setResult(allCorrect ? 'correct' : 'incorrect');
    props.onAnswer(allCorrect, props.question.id);
  };

  const getOptionClass = (optIndex: number) => {
    const base = "w-full text-left p-3 rounded-lg border-2 transition-all duration-200";

    if (!answered()) {
      return selected().has(optIndex)
        ? `${base} border-blue-500 bg-blue-50 cursor-pointer hover:border-blue-600`
        : `${base} border-gray-200 cursor-pointer hover:border-blue-400 hover:bg-blue-50`;
    }

    if (correctIndices().includes(optIndex)) return `${base} border-green-500 bg-green-50 cursor-default`;
    if (selected().has(optIndex)) return `${base} border-red-500 bg-red-50 cursor-default`;
    return `${base} border-gray-200 cursor-default`;
  };

  return (
    <div
      id={`question-${props.question.id}`}
      class={`bg-white rounded-xl shadow-md p-6 border-2 transition-all duration-300 ${
        result() === 'correct' ? 'border-green-400' :
        result() === 'incorrect' ? 'border-red-400' : 'border-transparent'
      }`}
    >
      <h3 class="font-semibold text-lg mb-4 text-gray-800">
        <span class="text-blue-600 mr-2">{props.question.id}.</span>
        {props.question.question}
        <Show when={isMultiple()}>
          <span class="ml-2 text-xs bg-purple-100 text-purple-700 px-2 py-1 rounded-full">
            {correctIndices().length} réponses
          </span>
        </Show>
      </h3>

      <div class="space-y-2">
        <For each={props.question.options}>
          {(option, optIndex) => (
            <button
              class={getOptionClass(optIndex())}
              onClick={() => handleClick(optIndex())}
              onDblClick={handleDoubleClick}
            >
              <code class="text-sm">{option}</code>
            </button>
          )}
        </For>
      </div>

      <Show when={answered()}>
        <div class="mt-4">
          <p class={`text-sm font-medium ${result() === 'correct' ? 'text-green-600' : 'text-red-600'}`}>
            {result() === 'correct'
              ? (isMultiple() ? '✓ Correct ! Toutes les bonnes réponses trouvées.' : '✓ Correct !')
              : (isMultiple() ? '✗ Incorrect. Les bonnes réponses sont indiquées en vert.' : '✗ Incorrect. La bonne réponse est indiquée en vert.')
            }
          </p>
        </div>
      </Show>
    </div>
  );
}

export default function Quiz() {
  const [filter, setFilter] = createSignal<number[]>([]);
  const [answered, setAnswered] = createSignal(0);
  const [correct, setCorrect] = createSignal(0);
  const [errors, setErrors] = createSignal<number[]>([]);
  const [startTime, setStartTime] = createSignal(Date.now());
  const [elapsed, setElapsed] = createSignal(0);
  const [finished, setFinished] = createSignal(false);
  const [showScroll, setShowScroll] = createSignal(false);
  const [exportOpen, setExportOpen] = createSignal(false);
  const [copied, setCopied] = createSignal(false);

  const filteredQuestions = createMemo(() => {
    const f = filter();
    return f.length === 0 ? questions as Question[] : (questions as Question[]).filter(q => f.includes(q.id));
  });

  const total = createMemo(() => filteredQuestions().length);
  const progressPercent = createMemo(() => Math.round((answered() / total()) * 100));
  const successPercent = createMemo(() => Math.round((correct() / total()) * 100));

  let timerInterval: number;

  onMount(() => {
    timerInterval = setInterval(() => {
      if (!finished()) setElapsed(Date.now() - startTime());
    }, 1000);

    const handleScroll = () => setShowScroll(window.scrollY > 300);
    window.addEventListener('scroll', handleScroll);
    onCleanup(() => {
      clearInterval(timerInterval);
      window.removeEventListener('scroll', handleScroll);
    });
  });

  const handleAnswer = (isCorrect: boolean, questionId: number) => {
    setAnswered(a => a + 1);
    isCorrect ? setCorrect(c => c + 1) : setErrors(e => [...e, questionId]);

    if (answered() + 1 === total()) {
      setFinished(true);
      clearInterval(timerInterval);
    }
  };

  const copyErrors = () => {
    navigator.clipboard.writeText(compressToIntervals(errors()));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const scrollToTop = () => window.scrollTo({ top: 0, behavior: 'smooth' });

  return (
    <div class="max-w-3xl mx-auto p-4">
      {/* Filtre */}
      <Filter onFilterChange={setFilter} />

      {/* Stats */}
      <div class="mb-8 text-center">
        <p class="text-gray-600 mb-6">Pour un apprentissage efficace, prenez des notes sur papier.</p>
        <div class="flex gap-8 justify-center">
          <div class="text-center">
            <div class="text-sm text-gray-500 mb-1">Temps</div>
            <div class="text-2xl font-bold text-purple-600">{formatTime(elapsed())}</div>
          </div>
          <div class="text-center">
            <div class="text-sm text-gray-500 mb-1">Progress</div>
            <div class="text-2xl font-bold text-blue-600">{progressPercent()} %</div>
          </div>
          <div class="text-center">
            <div class="text-sm text-gray-500 mb-1">Success</div>
            <div class="text-2xl font-bold text-green-600">{successPercent()} %</div>
          </div>
        </div>
      </div>

      {/* Erreurs */}
      <Show when={errors().length > 0}>
        <div class="mb-8">
          <div class="bg-red-50 border-2 border-red-200 rounded-xl p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="text-red-700 font-semibold flex items-center gap-2">
                <span>✗</span> Erreurs ({errors().length})
              </h3>
              <button
                onClick={() => setExportOpen(true)}
                class="px-3 py-1 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors cursor-pointer inline-flex items-center gap-1.5"
              >
                <FiDownload size={14} />
                Exporter
              </button>
            </div>
            <ul class="space-y-2 max-h-60 overflow-y-auto">
              <For each={errors()}>
                {(errorId) => {
                  const q = (questions as Question[]).find(q => q.id === errorId);
                  const idx = (questions as Question[]).findIndex(q => q.id === errorId);
                  return (
                    <li>
                      <a href={`#question-${errorId}`} class="block p-2 bg-white rounded-lg border border-red-200 hover:border-red-400 transition-colors">
                        <span class="text-red-600 font-medium">{idx + 1}.</span>
                        <span class="text-gray-700 text-sm ml-1">{q?.question}</span>
                      </a>
                    </li>
                  );
                }}
              </For>
            </ul>
          </div>
        </div>
      </Show>

      {/* Modal export */}
      <Modal
        open={exportOpen()}
        onOpenChange={setExportOpen}
        title="Exporter les erreurs"
        description="Copiez cette liste pour réviser uniquement les questions ratées."
      >
        <textarea
          value={compressToIntervals(errors())}
          readonly
          class="w-full h-24 p-3 border-2 border-gray-200 rounded-lg bg-gray-50 focus:outline-none resize-none font-mono box-border"
        />
        <div class="flex gap-3 mt-4">
          <button
            onClick={copyErrors}
            class={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors cursor-pointer ${
              copied() ? 'bg-green-500 text-white' : 'bg-green-600 text-white hover:bg-green-700'
            }`}
          >
            {copied() ? '✓ Copié !' : 'Copier'}
          </button>
        </div>
      </Modal>

      {/* Questions */}
      <div class="space-y-6">
        <For each={filteredQuestions()}>
          {(question, index) => (
            <QuestionCard question={question} index={index()} onAnswer={handleAnswer} />
          )}
        </For>
      </div>

      {/* Résultat final */}
      <Show when={finished()}>
        <div class="mt-8 p-6 bg-gradient-to-r from-blue-500 to-purple-600 rounded-xl text-white text-center">
          <h2 class="text-2xl font-bold mb-2">Quiz terminé !</h2>
          <p class="text-xl">
            Vous avez {correct()} bonnes réponses sur {total()} ({successPercent()}%) en {formatTime(elapsed())}
          </p>
          <button onClick={resetQuiz} class="mt-4 px-6 py-2 bg-white text-blue-600 rounded-lg font-semibold hover:bg-gray-100 transition-colors cursor-pointer">
            Recommencer
          </button>
        </div>
      </Show>

      {/* Bouton scroll to top */}
      <Show when={showScroll()}>
        <Tooltip>
          <Tooltip.Trigger
            onClick={scrollToTop}
            class="fixed bottom-6 right-6 inline-flex items-center justify-center rounded-full bg-purple-600 text-white hover:bg-purple-700 h-12 w-12 shadow-[0_4px_14px_0_rgba(124,58,237,0.39)] hover:shadow-[0_6px_20px_rgba(124,58,237,0.5)] hover:scale-110 transition-all outline-none cursor-pointer"
          >
            <FiChevronUp size={24} />
          </Tooltip.Trigger>
          <Tooltip.Portal>
            <Tooltip.Content class="bg-gray-900 text-white px-3 py-1.5 rounded-md text-sm shadow-lg z-50">
              Retour en haut
              <Tooltip.Arrow />
            </Tooltip.Content>
          </Tooltip.Portal>
        </Tooltip>
      </Show>
    </div>
  );
}
