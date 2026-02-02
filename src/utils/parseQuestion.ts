export type ParsedQuestion = {
  textBefore: string;
  code?: string;
  language?: string;
  textAfter: string;
};

/**
 * Parse une question pour extraire les blocs de code markdown
 * Format attendu : ```language\ncode\n```
 */
export function parseQuestion(question: string): ParsedQuestion {
  const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/;
  const match = question.match(codeBlockRegex);

  if (match) {
    const [fullMatch, language, code] = match;
    const parts = question.split(fullMatch);

    return {
      textBefore: parts[0].trim(),
      code: code,
      language: language || 'java',
      textAfter: parts[1]?.trim() || '',
    };
  }

  return {
    textBefore: question,
    textAfter: '',
  };
}
