import { http } from '@kit.NetworkKit';

const ACTIVE_HTTP_REQUESTS: http.HttpRequest[] = [];
const RETIRED_HTTP_REQUESTS: http.HttpRequest[] = [];
const IDLE_HTTP_REQUESTS: http.HttpRequest[] = [];
const VOLATILE_HTTP_REQUESTS: http.HttpRequest[] = [];
const HTTP_REQUEST_CLEANUP_QUIET_MS: number = 30000;
const HTTP_REQUEST_CLEANUP_STEP_MS: number = 500;
const MAX_IDLE_HTTP_REQUESTS: number = 6;
const IDLE_HTTP_REQUEST_TTL_MS: number = 120000;
let cleanupTimer: number = -1;
let activityGeneration: number = 0;
let lastActivityAt: number = 0;

export function acquireHttpRequest(): http.HttpRequest {
  const request = http.createHttp();
  activityGeneration++;
  lastActivityAt = Date.now();
  removeRequest(RETIRED_HTTP_REQUESTS, request);
  removeRequest(VOLATILE_HTTP_REQUESTS, request);
  if (ACTIVE_HTTP_REQUESTS.indexOf(request) < 0) {
    ACTIVE_HTTP_REQUESTS.push(request);
  }
  cancelCleanupTimer();
  return request;
}

export function markHttpRequestVolatile(request: http.HttpRequest): void {
  if (VOLATILE_HTTP_REQUESTS.indexOf(request) < 0) {
    VOLATILE_HTTP_REQUESTS.push(request);
  }
}

export function releaseHttpRequest(request: http.HttpRequest): void {
  activityGeneration++;
  lastActivityAt = Date.now();
  removeRequest(ACTIVE_HTTP_REQUESTS, request);
  removeRequest(VOLATILE_HTTP_REQUESTS, request);
  if (RETIRED_HTTP_REQUESTS.indexOf(request) < 0) {
    RETIRED_HTTP_REQUESTS.push(request);
  }
  scheduleCleanup(HTTP_REQUEST_CLEANUP_QUIET_MS);
}

/**
 * Tracks native HTTP tasks so completed handles are not destroyed while another app request is entering the system
 * curl multi loop. Some HarmonyOS builds can otherwise race handle removal against socket dispatch.
 */
export function trackHttpRequest(request: http.HttpRequest): void {
  activityGeneration++;
  lastActivityAt = Date.now();
  removeRequest(RETIRED_HTTP_REQUESTS, request);
  if (ACTIVE_HTTP_REQUESTS.indexOf(request) < 0) {
    ACTIVE_HTTP_REQUESTS.push(request);
  }
  cancelCleanupTimer();
}

export function retireHttpRequest(request: http.HttpRequest): void {
  releaseHttpRequest(request);
}

export function cancelHttpRequest(request: http.HttpRequest): void {
  activityGeneration++;
  lastActivityAt = Date.now();
  if (ACTIVE_HTTP_REQUESTS.indexOf(request) >= 0) {
    cancelCleanupTimer();
  }
}

export function hasActiveHttpRequests(): boolean {
  return ACTIVE_HTTP_REQUESTS.length > 0;
}

function removeRequest(items: http.HttpRequest[], request: http.HttpRequest): boolean {
  const index = items.indexOf(request);
  if (index >= 0) {
    items.splice(index, 1);
    return true;
  }
  return false;
}

function cancelCleanupTimer(): void {
  if (cleanupTimer >= 0) {
    clearTimeout(cleanupTimer);
    cleanupTimer = -1;
  }
}

function scheduleCleanup(delayMs: number): void {
  cancelCleanupTimer();
  const generation = activityGeneration;
  cleanupTimer = setTimeout(() => {
    cleanupTimer = -1;
    if (generation !== activityGeneration) {
      return;
    }
    cleanupRetiredRequest();
  }, delayMs);
}

function cleanupRetiredRequest(): void {
  if (ACTIVE_HTTP_REQUESTS.length > 0) {
    scheduleCleanup(HTTP_REQUEST_CLEANUP_QUIET_MS);
    return;
  }
  const idleFor = Date.now() - lastActivityAt;
  if (IDLE_HTTP_REQUESTS.length > 0 && idleFor >= IDLE_HTTP_REQUEST_TTL_MS) {
    const expired = IDLE_HTTP_REQUESTS.shift();
    if (expired !== undefined) {
      try {
        expired.destroy();
      } catch (_error) {
      }
      scheduleCleanup(HTTP_REQUEST_CLEANUP_STEP_MS);
      return;
    }
  }
  const quietFor = idleFor;
  if (quietFor < HTTP_REQUEST_CLEANUP_QUIET_MS && RETIRED_HTTP_REQUESTS.length === 0) {
    scheduleCleanup(HTTP_REQUEST_CLEANUP_QUIET_MS - quietFor);
    return;
  }
  const request = RETIRED_HTTP_REQUESTS.shift();
  if (request !== undefined) {
    try {
      request.destroy();
    } catch (_error) {
    }
  }
  if (RETIRED_HTTP_REQUESTS.length > 0 || IDLE_HTTP_REQUESTS.length > 0) {
    scheduleCleanup(HTTP_REQUEST_CLEANUP_STEP_MS);
  }
}
