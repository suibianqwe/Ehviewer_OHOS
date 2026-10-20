// Only use a deadline when the caller has a real website page to fall back to.
// The cloud download continues warming its cache; a late result cannot replace the visible page.
export function readerCloudPageWithFallback(request: Promise<string>, timeoutMs: number): Promise<string> {
  if (timeoutMs <= 0) {
    return request;
  }
  return new Promise<string>((resolve: (value: string) => void) => {
    let settled = false;
    const timer = setTimeout(() => {
      settled = true;
      resolve('');
    }, timeoutMs);
    request.then((path: string) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(path);
      }
    }).catch(() => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve('');
      }
    });
  });
}
