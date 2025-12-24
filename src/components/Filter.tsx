import { createSignal, onMount } from 'solid-js';
import { FiFilter } from 'solid-icons/fi';
import Modal from './Modal';

// Utils
const range = (start: number, end: number) =>
  Array.from({ length: Math.abs(end - start) + 1 }, (_, i) => Math.min(start, end) + i);

export const parseQuestionNumbers = (input: string): number[] =>
  [...new Set(
    input.trim().split(/\s+/).flatMap(part => {
      if (part.includes('-')) {
        const [a, b] = part.split('-').map(Number);
        return !isNaN(a) && !isNaN(b) ? range(a, b) : [];
      }
      const n = Number(part);
      return isNaN(n) ? [] : [n];
    })
  )].sort((a, b) => a - b);

export const compressToIntervals = (numbers: number[]): string => {
  if (!numbers.length) return '';

  return [...numbers].sort((a, b) => a - b)
    .reduce<number[][]>((acc, n) => {
      const last = acc.at(-1);
      if (last && n === last.at(-1)! + 1) last.push(n);
      else acc.push([n]);
      return acc;
    }, [])
    .map(group => group.length >= 3 ? `${group[0]}-${group.at(-1)}` : group.join(' '))
    .join(' ');
};

// URL helpers
const getFilterFromURL = (): string => {
  const params = new URLSearchParams(window.location.search);
  return params.get('q') || '';
};

const setFilterToURL = (filter: string) => {
  const url = new URL(window.location.href);
  if (filter) {
    url.searchParams.set('q', filter);
  } else {
    url.searchParams.delete('q');
  }
  window.history.replaceState({}, '', url.toString());
};

type FilterProps = {
  onFilterChange: (numbers: number[]) => void;
};

export default function Filter(props: FilterProps) {
  const [open, setOpen] = createSignal(false);
  const [input, setInput] = createSignal('');

  onMount(() => {
    const savedFilter = getFilterFromURL();
    if (savedFilter) {
      setInput(savedFilter);
      props.onFilterChange(parseQuestionNumbers(savedFilter));
    }
  });

  const apply = () => {
    const value = input().trim();
    setFilterToURL(value);
    props.onFilterChange(parseQuestionNumbers(value));
    setOpen(false);
  };

  const reset = () => {
    setInput('');
    setFilterToURL('');
    props.onFilterChange([]);
    setOpen(false);
  };

  return (
    <>
      <div class="mb-4 text-center">
        <button
          onClick={() => setOpen(true)}
          class="px-4 py-2 bg-purple-600 text-white rounded-lg font-semibold hover:bg-purple-700 transition-colors cursor-pointer inline-flex items-center gap-2"
        >
          <FiFilter size={18} />
          Filtrer les questions
        </button>
      </div>

      <Modal
        open={open()}
        onOpenChange={setOpen}
        title="Filtrer les questions"
        description="Entrez les numéros séparés par des espaces. Utilisez - pour les intervalles. Exemple: 1 5-10 69"
      >
        <textarea
          value={input()}
          onInput={(e) => setInput(e.currentTarget.value)}
          class="w-full h-24 p-3 border-2 border-gray-200 rounded-lg focus:border-purple-500 focus:outline-none resize-none font-mono box-border"
          placeholder="1 5-10 69 ..."
        />
        <div class="flex gap-3 mt-4">
          <button onClick={apply} class="flex-1 px-4 py-2 bg-purple-600 text-white rounded-lg font-semibold hover:bg-purple-700 transition-colors cursor-pointer">
            Appliquer
          </button>
          <button onClick={reset} class="flex-1 px-4 py-2 bg-gray-200 text-gray-700 rounded-lg font-semibold hover:bg-gray-300 transition-colors cursor-pointer">
            Réinitialiser
          </button>
        </div>
      </Modal>
    </>
  );
}
