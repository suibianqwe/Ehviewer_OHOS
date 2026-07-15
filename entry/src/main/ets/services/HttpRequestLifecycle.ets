import { http } from '@kit.NetworkKit';

const ACTIVE_HTTP_REQUESTS: http.HttpRequest[] = [];
const RETIRED_HTTP_REQUESTS: http.HttpRequest[] = [];
const HTTP_REQUEST_CLEANUP_QUIET_MS: number = 1200;
const HTTP_REQUEST_CLEANUP_STEP_MS: number = 60;
let cleanupTimer: number = -1;

/**
 * Tracks native HTTP tasks so completed handles are not destroyed while another app request is entering the system
 * curl multi loop. Some HarmonyOS builds can otherwise race handle removal against socket dispatch.
 */
export function trackHttpRequest(request: http.HttpRequest): void {
  removeRequest(RETIRED_HTTP_REQUESTS, request);
  if (ACTIVE_HTTP_REQUESTS.indexOf(request) < 0) {
    ACTIVE_HTTP_REQUESTS.push(request);
  }
  cancelCleanupTimer();
}

export function retireHttpRequest(request: http.HttpRequest): void {
  removeRequest(ACTIVE_HTTP_REQUESTS, request);
  if (RETIRED_HTTP_REQUESTS.indexOf(request) < 0) {
    RETIRED_HTTP_REQUESTS.push(request);
  }
  scheduleCleanup(HTTP_REQUEST_CLEANUP_QUIET_MS);
}

function removeRequest(items: http.HttpRequest[], request: http.HttpRequest): void {
  const index = items.indexOf(request);
  if (index >= 0) {
    items.splice(index, 1);
  }
}

function cancelCleanupTimer(): void {
  if (cleanupTimer >= 0) {
    clearTimeout(cleanupTimer);
    cleanupTimer = -1;
  }
}

function scheduleCleanup(delayMs: number): void {
  cancelCleanupTimer();
  cleanupTimer = setTimeout(() => {
    cleanupTimer = -1;
    cleanupRetiredRequest();
  }, delayMs);
}

function cleanupRetiredRequest(): void {
  if (ACTIVE_HTTP_REQUESTS.length > 0) {
    scheduleCleanup(HTTP_REQUEST_CLEANUP_QUIET_MS);
    return;
  }
  const request = RETIRED_HTTP_REQUESTS.shift();
  if (request === undefined) {
    return;
  }
  try {
    request.destroy();
  } catch (_error) {
  }
  if (RETIRED_HTTP_REQUESTS.length > 0) {
    scheduleCleanup(HTTP_REQUEST_CLEANUP_STEP_MS);
  }
}
