// Keep public service hosts and native crash symbols useful for diagnosis.
// Custom endpoints can contain private server names and gallery directories.
export function redactDiagnosticText(text: string): string {
  return text
    .replace(/((?:proxy-authorization|authorization|set-cookie|cookie)\s*["']?\s*[:=]\s*)[^\r\n]+/gi, '$1[REDACTED]')
    .replace(/((?:["']?)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|client_secret|password|passwd|ipb_pass_hash|ipb_member_id|igneous)["']?\s*[:=]\s*)(?:\[REDACTED\]|"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;&<>\r\n]+)/gi, '$1[REDACTED]')
    .replace(/(https?:\/\/)[^\s/<>"']+@/gi, '$1[REDACTED]@')
    .replace(/([?&;](?:amp;)?[^=\s&#<>"']+=)[^\s&#<>"']*/gi, '$1[REDACTED]')
    .replace(/(\/(?:keystamp|auth|token)=)[^/\s<>"']+/gi, '$1[REDACTED]')
    .replace(/\b(?:sk-[A-Za-z0-9_-]{12,}|AIza[A-Za-z0-9_-]{20,})\b/g, '[REDACTED]')
    .replace(/https?:\/\/[^\s<>"']+/gi, (url: string): string => {
      const parts = /^(https?:\/\/)([^/?#]+)(.*)$/i.exec(url);
      if (parts === null || parts[2].indexOf('[PRIVATE_HOST]') >= 0) return url;
      const authority = parts[2].replace(/^\[REDACTED\]@/, '');
      const host = authority.replace(/:\d+$/, '').toLowerCase();
      if (/(^|\.)(e-hentai\.org|exhentai\.org|ehgt\.org|hath\.network|github\.com|githubusercontent\.com|cloudflare-dns\.com|dns\.google)$/.test(host)) {
        return url;
      }
      const port = /:\d+$/.exec(authority);
      const extension = /\.(webp|gif|png|jpe?g|avif|json|xml)(?:[?#]|$)/i.exec(parts[3]);
      return parts[1] + '[PRIVATE_HOST]' + (port === null ? '' : port[0]) +
        (parts[3].length === 0 ? '' : '/[PRIVATE_PATH]' + (extension === null ? '' : '.' + extension[1]));
    })
    .replace(/(\[RemoteStorage\]|\[(?:INFO|WARN|ERROR)\] RemoteStorage:)([^\r\n]*)/g,
      (_match: string, prefix: string, message: string): string => prefix + message.replace(
        /\b(profile|root|path|dir)=.*?(?=\s+(?:bytes|entries|items|files|index|gid|sections|bodyBytes)=|$)/g,
        '$1=[REDACTED]'));
}

export function formatAppDiagnosticLog(app: string, remote: string): string {
  const mainRecords: string[] = [];
  const remoteRecords: string[] = [];
  // Old versions stored WebDAV traffic and other modules in a single file.
  // Separate those records during export as well as separating new writes.
  for (const entry of app.split(/(?=^\d{4}-\d{2}-\d{2}T[\d:.]+Z \[(?:INFO|WARN|ERROR)\] )/m)) {
    if (entry.length === 0) continue;
    if (/^\d{4}-[^\n]+\] RemoteStorage:/.test(entry)) remoteRecords.push(entry);
    else if (/^\d{4}-/.test(entry) || /^\[Log (?:read|write) failed\]/.test(entry)) mainRecords.push(entry);
    else mainRecords.push('[Earlier content omitted, incomplete legacy record removed]\n');
  }
  let details = remoteRecords.join('') + remote;
  // A conservative UTF-16 bound also keeps the UTF-8 section below 128 KiB.
  if (details.length > 32768) {
    details = details.slice(-32768);
    const newline = details.indexOf('\n');
    details = '[Earlier remote storage records omitted]\n' + (newline < 0 ? '' : details.substring(newline + 1));
  }
  return (mainRecords.join('') || '(none saved)\n') + '\n[Remote storage log, independent capacity]\n' +
    (details || '(none saved)\n');
}

export function isAbnormalExit(reason: number): boolean {
  return reason === 1 || reason === 3 || reason === 4 || reason === 5 || reason === 6 || reason === 7;
}
