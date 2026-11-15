import { formatAppDiagnosticLog, redactDiagnosticText } from './DiagnosticLogSupport';

@Concurrent
export function redactDiagnosticExportTask(text: string): string {
  return redactDiagnosticText(text);
}

@Concurrent
export function formatAppDiagnosticLogTask(app: string, remote: string): string {
  return formatAppDiagnosticLog(app, remote);
}
