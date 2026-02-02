import { onMount } from 'solid-js';
import hljs from 'highlight.js/lib/core';
import java from 'highlight.js/lib/languages/java';
import c from 'highlight.js/lib/languages/c';
import 'highlight.js/styles/atom-one-dark.css';

// Enregistrer les langages
hljs.registerLanguage('java', java);
hljs.registerLanguage('c', c);

type CodeBlockProps = {
  code: string;
  language?: string;
};

export default function CodeBlock(props: CodeBlockProps) {
  let codeRef: HTMLElement | undefined;

  onMount(() => {
    if (codeRef) {
      hljs.highlightElement(codeRef);
    }
  });

  return (
    <div class="code-block-wrapper my-3">
      <pre class="!m-0 rounded-lg overflow-hidden shadow-md">
        <code
          ref={codeRef}
          class={`language-${props.language || 'java'} !p-4 block overflow-x-auto text-sm`}
        >
          {props.code.trim()}
        </code>
      </pre>
    </div>
  );
}
