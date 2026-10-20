import { EhTagSuggestion, ParsedTagDatabase, parseTagTsv, prepareTagDatabase } from './TagTranslationProcessing';

@Concurrent
export function parseTagTsvTask(text: string): EhTagSuggestion[] {
  return parseTagTsv(text);
}

@Concurrent
export function prepareTagDatabaseTask(body: string, expectedSha: string): ParsedTagDatabase {
  return prepareTagDatabase(body, expectedSha);
}
