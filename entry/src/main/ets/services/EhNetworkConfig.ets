import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { ehAppLog } from './EhAppLog';
import { ehSettingsStore } from './EhSettingsStore';
import { acquireHttpRequest, hasActiveHttpRequests, retireHttpRequest } from './HttpRequestLifecycle';

const YANDEX_DOH_URL: string = 'https://common.dot.dns.yandex.net/dns-query';
const CLOUDFLARE_DOH_URL: string = 'https://cloudflare-dns.com/dns-query';
const GOOGLE_DOH_URL: string = 'https://dns.google/dns-query';
const FRONTING_IP_CACHE_FILE_NAME: string = 'eh_fronting_ip_quality.json';
const FRONTING_IP_CACHE_VERSION: number = 1;
const FRONTING_PROBE_CONNECT_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_READ_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_DEADLINE_MS: number = 4500;
const FRONTING_PROBE_CONCURRENCY: number = 3;
const FRONTING_PREFERRED_IP_LIMIT: number = 3;
const FRONTING_TAIL_SAMPLE_RATE: number = 0.08;
const FRONTING_WEIGHT_SCORE_BASE: number = 500;
const DIRECT_PROBE_TIMEOUT_MS: number = 5000;
const DIRECT_HOST_FAILURE_THRESHOLD: number = 1;
const DIRECT_HOST_BLOCK_MS: number = 120000;
const IP_FAILURE_LATENCY_PENALTY_MS: number = 2500;
const IP_SUCCESS_LATENCY_BONUS_MS: number = 120;
const IP_RETRY_DEMOTE_THRESHOLD: number = 1;
const IP_UNTESTED_LATENCY_MS: number = 2200;
const IP_QUALITY_SAVE_THROTTLE_MS: number = 30000;
const IP_SLOW_RESPONSE_THRESHOLD_MS: number = 4000;
const IP_SLOW_LATENCY_PENALTY_MS: number = 350;
const NETWORK_CHANGE_DEBOUNCE_MS: number = 350;
const NETWORK_RECOVERY_SETTLE_MS: number = 2000;
const NETWORK_RECOVERY_IDLE_RETRY_MS: number = 1000;
const NETWORK_ENVIRONMENT_FALLBACK_INTERVAL_MS: number = 5000;
const FRESH_CONNECTION_WINDOW_MS: number = 5000;
const FRONTING_PROBE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const BUILT_IN_RULES: HostRule[] = [
  { host: 'e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'repo.e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'forums.e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'upld.e-hentai.org', ips: ['89.149.221.236', '95.211.208.236'] },
  { host: 'ehgt.org', ips: ['109.236.85.28', '62.112.8.21', '89.39.106.43', '2a00:7c80:0:123::3a85', '2a00:7c80:0:12d::38a1', '2a00:7c80:0:13b::37a4'] },
  { host: 'github.com', ips: ['140.82.112.4', '140.82.113.4', '140.82.114.4', '140.82.121.4'] },
  { host: 'api.github.com', ips: ['140.82.112.6', '140.82.113.6', '140.82.114.6', '140.82.121.6'] },
  { host: 'raw.githubusercontent.com', ips: ['151.101.0.133', '151.101.64.133', '151.101.128.133', '151.101.192.133'] },
  { host: 'objects.githubusercontent.com', ips: ['185.199.108.133', '185.199.109.133', '185.199.110.133', '185.199.111.133'] },
  { host: 'github-releases.githubusercontent.com', ips: ['185.199.108.154', '185.199.109.154', '185.199.110.154', '185.199.111.154'] }
];
const BUILT_EX_RULES: HostRule[] = [
  { host: 'exhentai.org', ips: ['178.175.128.251', '178.175.128.252', '178.175.128.253', '178.175.128.254', '178.175.129.251', '178.175.129.252', '178.175.129.253', '178.175.129.254', '178.175.132.19', '178.175.132.20', '178.175.132.21', '178.175.132.22'] },
  { host: 'upld.exhentai.org', ips: ['178.175.132.22', '178.175.129.254', '178.175.128.254'] },
  { host: 's.exhentai.org', ips: ['178.175.129.253', '178.175.129.254', '178.175.128.253', '178.175.128.254', '178.175.132.21', '178.175.132.22'] }
];
let appliedHostRulesKey: string = '';
let pendingHostRules: Promise<void> | null = null;
const HOST_IP_QUALITIES: HostIpQuality[] = [];
let frontingProbeKey: string = '';
let frontingProbeNetworkEnvironmentKey: string = '';
let frontingProbeGeneration: number = 0;
let frontingProbePending: Promise<void> | null = null;
let frontingIpCachePath: string = '';
let frontingIpCacheLoadedKey: string = '';
let frontingIpCacheLoadedSuccessfully: boolean = false;
let frontingCachedNetworkEnvironmentKey: string = '';
let directProbeKey: string = '';
let directProbeGeneration: number = 0;
let directProbePending: Promise<boolean> | null = null;
let directProbePassed: boolean = false;
let observedNetworkEnvironmentKey: string = '';
let cachedNetworkEnvironmentKey: string = '';
let lastNetworkEnvironmentCheckAt: number = 0;
let networkRuntimeContext: common.UIAbilityContext | undefined = undefined;
let networkRuntimeConnection: connection.NetConnection | undefined = undefined;
let networkRuntimeRegistered: boolean = false;
let networkChangeTimer: number = -1;
let networkRecoveryTimer: number = -1;
let forceFreshConnectionsUntilMs: number = 0;
let lastIpQualitySaveAt: number = 0;
const DIRECT_HOST_FAILURES: DirectHostFailure[] = [];

interface HostRule {
  host: string;
  ips: string[];
}

interface HostIpQuality {
  host: string;
  ip: string;
  ok: boolean;
  latencyMs: number;
  testedAt: number;
  successCount?: number;
  failureCount?: number;
  lastResultAt?: number;
}

interface HostIpProbeTarget {
  host: string;
  ip: string;
}

interface DirectHostFailure {
  host: string;
  failureCount: number;
  blockedUntil: number;
}

interface FrontingIpQualityCache {
  version?: number;
  key?: string;
  updatedAt?: number;
  networkEnvironmentKey?: string;
  qualities?: HostIpQuality[];
}

export interface EhRequestPlan {
  url: string;
  host: string;
  fronted: boolean;
}

export function createEhRequestPlan(url: string): EhRequestPlan {
  const host = requestHost(url);
  const hostHeader = requestHostHeader(url);
  if (!isEhNetworkProcessingEnabled()) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  let networkChanged = false;
  if (isEhDirectConnectionProbeEnabled() || isEhFrontingBenchmarkEnabled()) {
    networkChanged = refreshNetworkEnvironment();
  }
  ensureFrontingQualityCacheLoaded();
  if (networkChanged) {
    refreshNetworkRuntimeAfterChange();
  }
  if (shouldUseDirectConnection(host)) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  const exFrontingIp = exFrontingIpForUrl(url, host);
  if (exFrontingIp.length > 0) {
    return {
      url: replaceUrlHost(url, exFrontingIp),
      host: hostHeader,
      fronted: true
    };
  }
  const eFrontingIp = eFrontingIpForUrl(url, host);
  if (eFrontingIp.length === 0) {
    return {
      url: url,
      host: hostHeader,
      fronted: false
    };
  }
  return {
    url: replaceUrlHost(url, eFrontingIp),
    host: hostHeader,
    fronted: true
  };
}

function isEhNetworkProcessingEnabled(): boolean {
  return ehSettingsStore.getValue('built_in_hosts', 'Off') === 'On' ||
    ehSettingsStore.getValue('built_ex_hosts', 'Off') === 'On' ||
    ehSettingsStore.getValue('dns_over_https', 'Off') === 'On' ||
    ehSettingsStore.getValue('domain_fronting', 'Off') === 'On' ||
    ehSettingsStore.getValue('auto_direct_connection', 'Off') === 'On';
}

function ensureFrontingQualityCacheLoaded(): void {
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    return;
  }
  loadCachedIpQualities(key);
}

export function applyEhNetworkOptions(options: http.HttpRequestOptions, plan: EhRequestPlan,
  useDnsOverHttps: boolean = true): void {
  options.usingCache = false;
  // 部分 6.1 设备在 HTTP/3 请求超时后移除 curl handle 时会触发系统网络栈崩溃。
  // EH 站点完整支持 HTTP/1.1，固定协议可以避开该原生路径，同时保留连接复用。
  options.usingProtocol = http.HttpProtocol.HTTP1_1;
  applyConfiguredNetworkOptions(options, useDnsOverHttps);
  if (plan.fronted) {
    options.remoteValidation = 'skip';
    // Keep sniHostName unset deliberately. The original implementation opens TLS by IP so the blocked gallery
    // hostname is absent from ClientHello, then routes the HTTP request with the original Host header.
    // API 26 can explicitly prevent the system HTTP/2 pool from reusing an IP connection for another Host/SNI
    // combination. Connection: close alone is not sufficient on affected HarmonyOS 6.1 builds.
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
  } else if (Date.now() < forceFreshConnectionsUntilMs) {
    // The system clears its DNS cache on network disconnect/switch, but an existing HTTP/1.1
    // connection can still bypass a newly restored app-scoped DNS rule. Use fresh EH connections
    // briefly after a network or Hosts transition, then return to normal connection reuse.
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
  }
}

export function applyConfiguredNetworkOptions(options: http.HttpRequestOptions, useDnsOverHttps: boolean = true): void {
  applyConfiguredProxyOptions(options);
  if (useDnsOverHttps) {
    const dohUrl = currentDnsOverHttpsUrl();
    if (dohUrl.length > 0) {
      options.dnsOverHttps = dohUrl;
    }
  }
}

export function applyConfiguredProxyOptions(options: http.HttpRequestOptions): void {
  if (ehSettingsStore.getValue('proxy', 'System') === 'SOCKS') {
    if (deviceInfo.apiAvailable('26.0.0')) {
      const host = ehSettingsStore.getValue('proxy_host', '').trim();
      const port = parseProxyPort(ehSettingsStore.getValue('proxy_port', ''));
      if (host.length > 0 && isValidPort(port)) {
        const socks5Proxy: http.Socks5Proxy = {
          host: host,
          port: port,
          dnsStrategy: ehSettingsStore.getValue('proxy_socks_dns', 'Proxy') === 'System' ?
            connection.Socks5DnsStrategy.SYSTEM_MODE : connection.Socks5DnsStrategy.PROXY_MODE,
          exclusionList: parseProxyExclusionList(ehSettingsStore.getValue('proxy_exclusion_list', ''))
        };
        const username = ehSettingsStore.getValue('proxy_username', '').trim();
        if (username.length > 0) {
          socks5Proxy.username = username;
          socks5Proxy.password = ehSettingsStore.getValue('proxy_password', '');
        }
        options.usingSocks5Proxy = socks5Proxy;
        return;
      }
    }
  }
  options.usingProxy = proxyOption();
}

/**
 * Connections can be left in an unusable state while an ability is suspended in background.
 * Do not destroy active requests during the lifecycle callback; make requests started shortly
 * after a real foreground resume use fresh connections instead. Keep this window short so normal
 * requests quickly return to HTTP/1.1 connection reuse after stale background connections are bypassed.
 */
export function refreshEhConnectionsAfterForeground(): void {
  forceFreshConnectionsUntilMs = Math.max(forceFreshConnectionsUntilMs,
    Date.now() + FRESH_CONNECTION_WINDOW_MS);
}

export function socks5ProxySupported(): boolean {
  return deviceInfo.apiAvailable('26.0.0');
}

export function startEhDirectConnectionProbe(context?: common.UIAbilityContext): Promise<boolean> {
  if (context !== undefined) {
    networkRuntimeContext = context;
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  const key = directProbeKeyValue();
  if (key === 'Off') {
    directProbeGeneration++;
    directProbeKey = key;
    directProbePending = null;
    directProbePassed = false;
    clearDirectHostFailures();
    return Promise.resolve(false);
  }
  refreshNetworkEnvironment();
  if (directProbePending !== null && directProbeKey === key) {
    return directProbePending;
  }
  directProbeKey = key;
  directProbePassed = false;
  directProbeGeneration++;
  const generation = directProbeGeneration;
  const existingHostRuleTask = pendingHostRules;
  directProbePending = (existingHostRuleTask === null ? Promise.resolve() : existingHostRuleTask).then(() => {
    markFreshEhConnectionsRequired();
    return removeKnownHostRules();
  }).then(() => {
    return probeDirectSelectedSite();
  }).then(async (passed: boolean): Promise<boolean> => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = passed;
      if (passed) {
        clearDirectHostFailures();
        cancelFrontingBenchmark();
        appliedHostRulesKey = 'Direct';
      } else {
        await restoreConfiguredHostRules();
      }
      directProbePending = null;
    }
    return passed;
  }).catch(async (): Promise<boolean> => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = false;
      await restoreConfiguredHostRules();
      directProbePending = null;
    }
    return false;
  });
  return directProbePending;
}

export function isEhDirectConnectionProbeEnabled(): boolean {
  return ehSettingsStore.getValue('auto_direct_connection', 'Off') === 'On';
}

export function isEhFrontingBenchmarkEnabled(): boolean {
  return frontingBenchmarkKey() !== 'Off';
}

export function recordEhRequestOutcome(plan: EhRequestPlan, ok: boolean, elapsedMs: number): void {
  if (!plan.fronted) {
    recordDirectRequestOutcome(plan, ok);
    return;
  }
  const ip = requestHost(plan.url);
  if (!isIpv4(ip)) {
    return;
  }
  const host = plan.host.split(':')[0].toLowerCase();
  if (host.length === 0 || !isKnownProbeTarget(host, ip)) {
    return;
  }
  const current = qualityForHostIp(host, ip);
  applyIpQualityMeasurement(current, ok, elapsedMs, Date.now());
  if (ok) {
    saveCachedIpQualitiesThrottled(frontingBenchmarkKey());
  } else {
    saveCachedIpQualities(frontingBenchmarkKey());
  }
}

export function isEhRouteReachableStatus(statusCode: number): boolean {
  if (statusCode >= 200 && statusCode < 400) {
    return true;
  }
  // These responses are returned by the intended EH servers and still prove that the route is reachable.
  // Do not include generic 400/421 responses because they commonly indicate a wrong fronting endpoint.
  return statusCode === 401 || statusCode === 403 || statusCode === 404 || statusCode === 429 ||
    statusCode === 509;
}

function applyIpQualityMeasurement(current: HostIpQuality, ok: boolean, elapsedMs: number,
  now: number): void {
  const successCount = current.successCount === undefined ? 0 : current.successCount;
  const failureCount = current.failureCount === undefined ? 0 : current.failureCount;
  if (ok) {
    current.ok = true;
    current.successCount = successCount + 1;
    current.failureCount = Math.max(0, failureCount - 1);
    const measured = Math.max(1, elapsedMs);
    current.latencyMs = Math.max(1, Math.round((current.latencyMs * 2 + measured) / 3) -
      Math.min(IP_SUCCESS_LATENCY_BONUS_MS, current.successCount * 20));
    if (measured >= IP_SLOW_RESPONSE_THRESHOLD_MS) {
      current.latencyMs += Math.min(IP_SLOW_LATENCY_PENALTY_MS * 3,
        IP_SLOW_LATENCY_PENALTY_MS + Math.round((measured - IP_SLOW_RESPONSE_THRESHOLD_MS) / 20));
    }
  } else {
    current.failureCount = failureCount + 1;
    current.latencyMs = Math.max(current.latencyMs, Math.max(1, elapsedMs)) +
      IP_FAILURE_LATENCY_PENALTY_MS * Math.min(4, current.failureCount);
    current.ok = current.failureCount < IP_RETRY_DEMOTE_THRESHOLD ||
      (current.successCount !== undefined && current.successCount > current.failureCount);
  }
  current.testedAt = now;
  current.lastResultAt = now;
}

export function startEhFrontingBenchmark(context?: common.UIAbilityContext, forceRefresh: boolean = false): void {
  if (context !== undefined) {
    networkRuntimeContext = context;
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    cancelFrontingBenchmark();
    return;
  }
  const hasCachedBenchmark = loadCachedIpQualities(key);
  const currentEnvironmentKey = currentNetworkEnvironmentKey();
  if (observedNetworkEnvironmentKey.length === 0 && currentEnvironmentKey.length > 0) {
    observedNetworkEnvironmentKey = currentEnvironmentKey;
  }
  const cachedNetworkChanged = hasCachedBenchmark && currentEnvironmentKey.length > 0 &&
    frontingCachedNetworkEnvironmentKey !== currentEnvironmentKey;
  const preserveScores = forceRefresh || cachedNetworkChanged;
  if (key === frontingProbeKey && frontingProbePending !== null &&
    frontingProbeNetworkEnvironmentKey === currentEnvironmentKey) {
    return;
  }
  if (!preserveScores && (hasCachedBenchmark || hasUsableIpQualities())) {
    return;
  }
  frontingProbeKey = key;
  frontingProbeNetworkEnvironmentKey = currentEnvironmentKey;
  frontingProbeGeneration++;
  const generation = frontingProbeGeneration;
  frontingProbePending = runEhFrontingBenchmark(generation).then((results: HostIpQuality[]) => {
    if (generation === frontingProbeGeneration) {
      if (preserveScores) {
        mergeIpQualityMeasurements(results);
      } else {
        replaceIpQualities(results);
      }
      saveCachedIpQualities(key, true);
      frontingProbePending = null;
    }
  }).catch(() => {
    if (generation === frontingProbeGeneration) {
      frontingProbePending = null;
    }
  });
}

function cancelFrontingBenchmark(): void {
  frontingProbeGeneration++;
  frontingProbePending = null;
  frontingProbeKey = 'Off';
  frontingProbeNetworkEnvironmentKey = '';
}

export async function ensureEhHostRules(): Promise<void> {
  if (directProbePending !== null && isEhDirectConnectionProbeEnabled()) {
    await directProbePending;
  }
  if (directProbePassed && ehSettingsStore.getValue('auto_direct_connection', 'Off') === 'On') {
    const key = 'Direct';
    if (appliedHostRulesKey !== key) {
      if (appliedHostRulesKey.length > 0) {
        await waitHostRuleTask(removeKnownHostRules(), 1200);
      }
      appliedHostRulesKey = key;
    }
    return;
  }
  const key = ehSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    ehSettingsStore.getValue('built_ex_hosts', 'Off');
  if (key === 'Off:Off') {
    if (appliedHostRulesKey !== key) {
      await waitHostRuleTask(removeKnownHostRules(), 1200);
    }
    appliedHostRulesKey = key;
    return;
  }
  if (key === appliedHostRulesKey) {
    return;
  }
  if (pendingHostRules !== null) {
    await pendingHostRules;
    return;
  }

  pendingHostRules = applyHostRules(key);
  try {
    await pendingHostRules;
  } finally {
    pendingHostRules = null;
  }
}

function proxyOption(): boolean | http.HttpProxy {
  const proxyType = ehSettingsStore.getValue('proxy', 'System');
  if (proxyType === 'Off') {
    return false;
  }
  if (proxyType === 'HTTP') {
    const host = ehSettingsStore.getValue('proxy_host', '').trim();
    const port = parseProxyPort(ehSettingsStore.getValue('proxy_port', ''));
    if (host.length > 0 && isValidPort(port)) {
      const proxy: http.HttpProxy = {
        host: host,
        port: port,
        exclusionList: parseProxyExclusionList(ehSettingsStore.getValue('proxy_exclusion_list', ''))
      };
      const username = ehSettingsStore.getValue('proxy_username', '').trim();
      const password = ehSettingsStore.getValue('proxy_password', '');
      if (username.length > 0) {
        proxy.username = username;
        proxy.password = password;
      }
      return proxy;
    }
  }
  return true;
}

function eFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On' ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  const ip = rotatingIpv4ForHost(normalizedHost, BUILT_IN_RULES);
  if (ip.length > 0) {
    return ip;
  }
  return '';
}

function exFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On' ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  const ip = rotatingIpv4ForHost(normalizedHost, BUILT_EX_RULES);
  if (ip.length > 0) {
    return ip;
  }
  return '';
}

function rotatingIpv4ForHost(host: string, rules: HostRule[]): string {
  const ip = weightedIpv4ForHost(host, rules);
  if (ip.length > 0) {
    return ip;
  }
  const fallbackIps = ipv4ListForHost(host, rules);
  if (fallbackIps.length === 0) {
    return '';
  }
  return fallbackIps[Math.floor(Math.random() * fallbackIps.length)];
}

function ipv4ListForHost(host: string, rules: HostRule[]): string[] {
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].host !== host) {
      continue;
    }
    const ips: string[] = [];
    for (let j = 0; j < rules[i].ips.length; j++) {
      if (isIpv4(rules[i].ips[j])) {
        ips.push(rules[i].ips[j]);
      }
    }
    return ips;
  }
  return [];
}

function weightedIpv4ForHost(host: string, rules: HostRule[]): string {
  const candidates = ipv4ListForHost(host, rules);
  if (candidates.length === 0) {
    return '';
  }

  const results: HostIpQuality[] = [];
  for (let i = 0; i < candidates.length; i++) {
    results.push(qualityForHostIp(host, candidates[i]));
  }
  if (results.length === 0) {
    return '';
  }

  results.sort((left: HostIpQuality, right: HostIpQuality) => {
    const leftScore = ipQualityScore(left);
    const rightScore = ipQualityScore(right);
    if (leftScore !== rightScore) {
      return leftScore - rightScore;
    }
    return left.ip.localeCompare(right.ip);
  });
  const preferredLimit = Math.min(FRONTING_PREFERRED_IP_LIMIT, results.length);
  if (results.length > preferredLimit && Math.random() < FRONTING_TAIL_SAMPLE_RATE) {
    return weightedRandomIp(results, preferredLimit, results.length);
  }
  return weightedRandomIp(results, 0, preferredLimit);
}

function weightedRandomIp(results: HostIpQuality[], start: number, end: number): string {
  if (start >= end) {
    return '';
  }
  const bestScore = ipQualityScore(results[0]);
  let totalWeight = 0;
  const weights: number[] = [];
  for (let i = start; i < end; i++) {
    const scoreDistance = Math.max(0, ipQualityScore(results[i]) - bestScore);
    const healthWeight = results[i].ok ? 1 : 0.15;
    const weight = healthWeight / (FRONTING_WEIGHT_SCORE_BASE + scoreDistance);
    weights.push(weight);
    totalWeight += weight;
  }
  if (totalWeight <= 0) {
    return results[start].ip;
  }
  let cursor = Math.random() * totalWeight;
  for (let i = 0; i < weights.length; i++) {
    cursor -= weights[i];
    if (cursor <= 0) {
      return results[start + i].ip;
    }
  }
  return results[end - 1].ip;
}

async function runEhFrontingBenchmark(generation: number): Promise<HostIpQuality[]> {
  const targets = collectFrontingProbeTargets();
  if (targets.length === 0) {
    return [];
  }
  let nextIndex = 0;
  const results: HostIpQuality[] = [];
  const workers: Promise<void>[] = [];
  const workerCount = Math.min(FRONTING_PROBE_CONCURRENCY, targets.length);
  for (let i = 0; i < workerCount; i++) {
    workers.push(new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
      runFrontingProbeWorker(targets, generation, () => {
        const index = nextIndex;
        nextIndex++;
        return index;
      }, results).then(() => {
        resolve();
      }).catch(() => {
        resolve();
      });
    }));
  }
  await Promise.all(workers);
  return results;
}

async function runFrontingProbeWorker(targets: HostIpProbeTarget[], generation: number,
  next: () => number, results: HostIpQuality[]): Promise<void> {
  while (generation === frontingProbeGeneration) {
    const index = next();
    if (index >= targets.length) {
      return;
    }
    const result = await probeFrontingIp(targets[index]);
    if (generation === frontingProbeGeneration) {
      results.push(result);
    }
  }
}

export function registerEhNetworkChangeListener(context: common.UIAbilityContext): void {
  networkRuntimeContext = context;
  cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
  lastNetworkEnvironmentCheckAt = Date.now();
  if (observedNetworkEnvironmentKey.length === 0) {
    observedNetworkEnvironmentKey = cachedNetworkEnvironmentKey;
  }
  if (networkRuntimeConnection !== undefined) {
    return;
  }
  const netConnection = connection.createNetConnection();
  networkRuntimeConnection = netConnection;
  netConnection.on('netAvailable', (_netHandle: connection.NetHandle) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netLost', (_netHandle: connection.NetHandle) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netUnavailable', () => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo) => {
    scheduleNetworkRuntimeRefresh();
  });
  netConnection.on('netConnectionPropertiesChange', (_info: connection.NetConnectionPropertyInfo) => {
    scheduleNetworkRuntimeRefresh();
  });
  networkRuntimeRegistered = true;
  try {
    netConnection.register((error: BusinessError) => {
      if (error !== undefined && error.code !== 0) {
        networkRuntimeRegistered = false;
        networkRuntimeConnection = undefined;
        ehAppLog.warn(context, 'EhNetworkConfig',
          'Register network listener failed: ' + error.code.toString() + ' ' + error.message);
      }
    });
  } catch (error) {
    networkRuntimeRegistered = false;
    networkRuntimeConnection = undefined;
    ehAppLog.warn(context, 'EhNetworkConfig', 'Register network listener failed');
  }
}

export function unregisterEhNetworkChangeListener(): void {
  if (networkChangeTimer >= 0) {
    clearTimeout(networkChangeTimer);
    networkChangeTimer = -1;
  }
  if (networkRecoveryTimer >= 0) {
    clearTimeout(networkRecoveryTimer);
    networkRecoveryTimer = -1;
  }
  const netConnection = networkRuntimeConnection;
  networkRuntimeConnection = undefined;
  networkRuntimeRegistered = false;
  networkRuntimeContext = undefined;
  if (netConnection === undefined) {
    return;
  }
  try {
    netConnection.unregister((_error: BusinessError) => {
    });
  } catch (error) {
  }
}

async function probeFrontingIp(target: HostIpProbeTarget): Promise<HostIpQuality> {
  const request = acquireHttpRequest();
  const startedAt = Date.now();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.HEAD,
      header: {
        'Host': target.host,
        'User-Agent': FRONTING_PROBE_USER_AGENT,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Connection': 'close'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      usingProtocol: http.HttpProtocol.HTTP1_1,
      remoteValidation: 'skip',
      maxRedirects: 0,
      connectTimeout: FRONTING_PROBE_CONNECT_TIMEOUT_MS,
      readTimeout: FRONTING_PROBE_READ_TIMEOUT_MS
    };
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
    applyConfiguredNetworkOptions(options);
    const response = await requestProbeToCompletion(request, 'https://' + target.ip + '/', options);
    const statusCode = Number(response.responseCode);
    const ok = isEhRouteReachableStatus(statusCode);
    return {
      host: target.host,
      ip: target.ip,
      ok: ok,
      latencyMs: ok ? Math.max(1, Date.now() - startedAt) : FRONTING_PROBE_DEADLINE_MS,
      testedAt: Date.now()
    };
  } catch (error) {
    return {
      host: target.host,
      ip: target.ip,
      ok: false,
      latencyMs: FRONTING_PROBE_DEADLINE_MS,
      testedAt: Date.now()
    };
  } finally {
    retireHttpRequest(request);
  }
}

async function requestProbeToCompletion(request: http.HttpRequest, url: string,
  options: http.HttpRequestOptions): Promise<http.HttpResponse> {
  try {
    return await request.request(url, options);
  } catch (error) {
    throw new Error(String(error));
  }
}

function collectFrontingProbeTargets(): HostIpProbeTarget[] {
  const targets: HostIpProbeTarget[] = [];
  if (ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On') {
    return targets;
  }
  if (selectedGalleryHost() === 'e-hentai.org') {
    pushProbeTargets(targets, BUILT_IN_RULES);
  } else {
    pushProbeTargets(targets, BUILT_EX_RULES);
  }
  return targets;
}

function pushProbeTargets(targets: HostIpProbeTarget[], rules: HostRule[]): void {
  for (let i = 0; i < rules.length; i++) {
    if (!supportsDomainFrontingHost(rules[i].host)) {
      continue;
    }
    const ips = ipv4ListForHost(rules[i].host, rules);
    for (let j = 0; j < ips.length; j++) {
      if (!containsProbeTarget(targets, rules[i].host, ips[j])) {
        targets.push({ host: rules[i].host, ip: ips[j] });
      }
    }
  }
}

function containsProbeTarget(targets: HostIpProbeTarget[], host: string, ip: string): boolean {
  for (let i = 0; i < targets.length; i++) {
    if (targets[i].host === host && targets[i].ip === ip) {
      return true;
    }
  }
  return false;
}

function recordIpQuality(result: HostIpQuality): void {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].host === result.host && HOST_IP_QUALITIES[i].ip === result.ip) {
      HOST_IP_QUALITIES[i] = result;
      return;
    }
  }
  HOST_IP_QUALITIES.push(result);
}

function qualityForHostIp(host: string, ip: string): HostIpQuality {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].host === host && HOST_IP_QUALITIES[i].ip === ip) {
      return HOST_IP_QUALITIES[i];
    }
  }
  const quality: HostIpQuality = {
    host: host,
    ip: ip,
    ok: true,
    latencyMs: IP_UNTESTED_LATENCY_MS,
    testedAt: Date.now(),
    successCount: 0,
    failureCount: 0,
    lastResultAt: 0
  };
  HOST_IP_QUALITIES.push(quality);
  return quality;
}

function hasUsableIpQualities(): boolean {
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    if (HOST_IP_QUALITIES[i].ok && isKnownProbeTarget(HOST_IP_QUALITIES[i].host, HOST_IP_QUALITIES[i].ip)) {
      return true;
    }
  }
  return false;
}

function ipQualityScore(item: HostIpQuality): number {
  const successCount = item.successCount === undefined ? 0 : item.successCount;
  const failureCount = item.failureCount === undefined ? 0 : item.failureCount;
  const testedPenalty = item.lastResultAt === undefined || item.lastResultAt <= 0 ? 700 : 0;
  const okPenalty = item.ok ? 0 : IP_FAILURE_LATENCY_PENALTY_MS;
  return item.latencyMs + testedPenalty + okPenalty + failureCount * IP_FAILURE_LATENCY_PENALTY_MS -
    Math.min(1200, successCount * IP_SUCCESS_LATENCY_BONUS_MS);
}

function replaceIpQualities(results: HostIpQuality[]): boolean {
  const validResults: HostIpQuality[] = [];
  for (let i = 0; i < results.length; i++) {
    if (isKnownProbeTarget(results[i].host, results[i].ip)) {
      validResults.push(results[i]);
    }
  }
  if (validResults.length === 0) {
    return false;
  }
  clearIpQualities();
  for (let i = 0; i < validResults.length; i++) {
    recordIpQuality(validResults[i]);
  }
  return true;
}

function mergeIpQualityMeasurements(results: HostIpQuality[]): boolean {
  let merged = false;
  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    if (!isKnownProbeTarget(result.host, result.ip)) {
      continue;
    }
    const current = qualityForHostIp(result.host, result.ip);
    applyIpQualityMeasurement(current, result.ok, result.latencyMs, result.testedAt);
    merged = true;
  }
  return merged;
}

function clearIpQualities(): void {
  HOST_IP_QUALITIES.splice(0, HOST_IP_QUALITIES.length);
}

function loadCachedIpQualities(key: string): boolean {
  if (frontingIpCacheLoadedKey === key) {
    return frontingIpCacheLoadedSuccessfully;
  }
  clearIpQualities();
  frontingIpCacheLoadedKey = key;
  frontingIpCacheLoadedSuccessfully = false;
  frontingCachedNetworkEnvironmentKey = '';
  if (frontingIpCachePath.length === 0) {
    return false;
  }
  try {
    const parsed = JSON.parse(fs.readTextSync(frontingIpCachePath)) as FrontingIpQualityCache;
    if (!frontingCacheKeyMatches(parsed.key, key) || !Array.isArray(parsed.qualities)) {
      return false;
    }
    let loadedCount = 0;
    for (let i = 0; i < parsed.qualities.length; i++) {
      const item = parsed.qualities[i];
      if (isValidIpQuality(item)) {
        recordIpQuality({
          host: item.host,
          ip: item.ip,
          ok: item.ok,
          latencyMs: item.latencyMs,
          testedAt: item.testedAt,
          successCount: typeof item.successCount === 'number' ? item.successCount : 0,
          failureCount: typeof item.failureCount === 'number' ? item.failureCount : 0,
          lastResultAt: typeof item.lastResultAt === 'number' ? item.lastResultAt : item.testedAt
        });
        loadedCount++;
      }
    }
    frontingIpCacheLoadedSuccessfully = loadedCount > 0;
    frontingCachedNetworkEnvironmentKey = typeof parsed.networkEnvironmentKey === 'string' ?
      parsed.networkEnvironmentKey : '';
    return frontingIpCacheLoadedSuccessfully;
  } catch (error) {
    return false;
  }
}

function saveCachedIpQualities(key: string, benchmarkCompleted: boolean = false): void {
  if (frontingIpCachePath.length === 0) {
    return;
  }
  ensureKnownIpQualities();
  const qualities: HostIpQuality[] = [];
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    const item = HOST_IP_QUALITIES[i];
    if (isKnownProbeTarget(item.host, item.ip)) {
      qualities.push(item);
    }
  }
  let fd = -1;
  try {
    const file = fs.openSync(frontingIpCachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    const networkEnvironmentKey = currentNetworkEnvironmentKey();
    if (benchmarkCompleted && networkEnvironmentKey.length > 0) {
      frontingCachedNetworkEnvironmentKey = networkEnvironmentKey;
    }
    const payload: FrontingIpQualityCache = {
      version: FRONTING_IP_CACHE_VERSION,
      key: key,
      updatedAt: Date.now(),
      networkEnvironmentKey: frontingCachedNetworkEnvironmentKey,
      qualities: qualities
    };
    fs.writeSync(fd, JSON.stringify(payload));
    frontingIpCacheLoadedKey = key;
    frontingIpCacheLoadedSuccessfully = qualities.length > 0;
  } catch (error) {
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function ensureKnownIpQualities(): void {
  const targets = collectFrontingProbeTargets();
  for (let i = 0; i < targets.length; i++) {
    qualityForHostIp(targets[i].host, targets[i].ip);
  }
}

function saveCachedIpQualitiesThrottled(key: string): void {
  if (key === 'Off') {
    return;
  }
  const now = Date.now();
  if (now - lastIpQualitySaveAt < IP_QUALITY_SAVE_THROTTLE_MS) {
    return;
  }
  lastIpQualitySaveAt = now;
  saveCachedIpQualities(key);
}

function isValidIpQuality(item: HostIpQuality): boolean {
  if (item === undefined || item === null) {
    return false;
  }
  if (typeof item.host !== 'string' || typeof item.ip !== 'string' || typeof item.ok !== 'boolean') {
    return false;
  }
  if (typeof item.latencyMs !== 'number' || typeof item.testedAt !== 'number') {
    return false;
  }
  return item.host.length > 0 && isIpv4(item.ip) && item.latencyMs > 0 &&
    isKnownProbeTarget(item.host, item.ip);
}

function shouldUseDirectConnection(host: string): boolean {
  if (!directProbePassed || ehSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return false;
  }
  const normalizedHost = host.toLowerCase();
  if (isDirectHostBlocked(normalizedHost)) {
    return false;
  }
  if (normalizedHost === 'repo.e-hentai.org') {
    return true;
  }
  const selectedHost = selectedGalleryHost();
  if (normalizedHost === selectedHost) {
    return true;
  }
  if (selectedHost === 'exhentai.org') {
    return normalizedHost.endsWith('.exhentai.org');
  }
  if (selectedHost === 'e-hentai.org') {
    return normalizedHost.endsWith('.e-hentai.org') || normalizedHost === 'ehgt.org';
  }
  return false;
}

function recordDirectRequestOutcome(plan: EhRequestPlan, ok: boolean): void {
  if (!directProbePassed || ehSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return;
  }
  const host = plan.host.split(':')[0].toLowerCase();
  if (!isDirectCandidateHost(host)) {
    return;
  }
  if (ok) {
    clearDirectHostFailure(host);
    return;
  }
  const failure = directHostFailureFor(host);
  failure.failureCount++;
  if (failure.failureCount >= DIRECT_HOST_FAILURE_THRESHOLD) {
    failure.blockedUntil = Date.now() + DIRECT_HOST_BLOCK_MS;
  }
}

function isDirectCandidateHost(host: string): boolean {
  if (host === 'repo.e-hentai.org') {
    return true;
  }
  const selectedHost = selectedGalleryHost();
  if (host === selectedHost) {
    return true;
  }
  if (selectedHost === 'exhentai.org') {
    return host.endsWith('.exhentai.org');
  }
  if (selectedHost === 'e-hentai.org') {
    return host.endsWith('.e-hentai.org') || host === 'ehgt.org';
  }
  return false;
}

function isDirectHostBlocked(host: string): boolean {
  for (let i = DIRECT_HOST_FAILURES.length - 1; i >= 0; i--) {
    const item = DIRECT_HOST_FAILURES[i];
    if (item.blockedUntil > 0 && item.blockedUntil <= Date.now()) {
      DIRECT_HOST_FAILURES.splice(i, 1);
      continue;
    }
    if (item.host === host && item.blockedUntil > Date.now()) {
      return true;
    }
  }
  return false;
}

function directHostFailureFor(host: string): DirectHostFailure {
  for (let i = 0; i < DIRECT_HOST_FAILURES.length; i++) {
    if (DIRECT_HOST_FAILURES[i].host === host) {
      return DIRECT_HOST_FAILURES[i];
    }
  }
  const failure: DirectHostFailure = {
    host: host,
    failureCount: 0,
    blockedUntil: 0
  };
  DIRECT_HOST_FAILURES.push(failure);
  return failure;
}

function clearDirectHostFailure(host: string): void {
  for (let i = DIRECT_HOST_FAILURES.length - 1; i >= 0; i--) {
    if (DIRECT_HOST_FAILURES[i].host === host) {
      DIRECT_HOST_FAILURES.splice(i, 1);
    }
  }
}

function clearDirectHostFailures(): void {
  DIRECT_HOST_FAILURES.splice(0, DIRECT_HOST_FAILURES.length);
}

function directProbeKeyValue(): string {
  if (ehSettingsStore.getValue('auto_direct_connection', 'Off') !== 'On') {
    return 'Off';
  }
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') + ':' + proxySettingsKey() + ':' +
    dohSettingsKey() + ':' + currentNetworkEnvironmentKey();
}

function selectedGalleryHost(): string {
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? 'exhentai.org' : 'e-hentai.org';
}

async function probeDirectSelectedSite(): Promise<boolean> {
  const request = acquireHttpRequest();
  try {
    const host = selectedGalleryHost();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.HEAD,
      header: {
        'User-Agent': FRONTING_PROBE_USER_AGENT,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Connection': 'close'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      usingProtocol: http.HttpProtocol.HTTP1_1,
      maxRedirects: 0,
      connectTimeout: DIRECT_PROBE_TIMEOUT_MS,
      readTimeout: DIRECT_PROBE_TIMEOUT_MS
    };
    if (deviceInfo.apiAvailable('26.0.0')) {
      options.reuseConnections = false;
    }
    applyConfiguredNetworkOptions(options);
    const response = await requestProbeToCompletion(request, 'https://' + host + '/', options);
    const statusCode = Number(response.responseCode);
    return statusCode >= 200 && statusCode < 400;
  } catch (error) {
    return false;
  } finally {
    retireHttpRequest(request);
  }
}

function isKnownProbeTarget(host: string, ip: string): boolean {
  if (ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On') {
    return false;
  }
  return ruleContainsHostIp(BUILT_IN_RULES, host, ip) || ruleContainsHostIp(BUILT_EX_RULES, host, ip);
}

function ruleContainsHostIp(rules: HostRule[], host: string, ip: string): boolean {
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].host === host && rules[i].ips.indexOf(ip) >= 0) {
      return true;
    }
  }
  return false;
}

function frontingBenchmarkKey(): string {
  if (ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On') {
    return 'Off';
  }
  return 'sni-v4-status-aware:' + selectedGalleryHost() + ':' +
    proxySettingsKey() + ':' +
    dohSettingsKey();
}

function frontingCacheKeyMatches(cachedKey: string | undefined, currentKey: string): boolean {
  if (cachedKey === undefined) {
    return false;
  }
  return cachedKey === currentKey || cachedKey.startsWith(currentKey + ':');
}

function refreshNetworkEnvironment(): boolean {
  const key = currentNetworkEnvironmentKey();
  if (key.length === 0) {
    return false;
  }
  if (observedNetworkEnvironmentKey.length === 0) {
    observedNetworkEnvironmentKey = key;
    return false;
  }
  if (observedNetworkEnvironmentKey === key) {
    return false;
  }
  observedNetworkEnvironmentKey = key;
  directProbeGeneration++;
  directProbeKey = '';
  directProbePending = null;
  directProbePassed = false;
  clearDirectHostFailures();
  markFreshEhConnectionsRequired();
  return true;
}

function currentNetworkEnvironmentKey(): string {
  if (networkRuntimeRegistered && cachedNetworkEnvironmentKey.length > 0) {
    return cachedNetworkEnvironmentKey;
  }
  const now = Date.now();
  if (cachedNetworkEnvironmentKey.length > 0 &&
    now - lastNetworkEnvironmentCheckAt < NETWORK_ENVIRONMENT_FALLBACK_INTERVAL_MS) {
    return cachedNetworkEnvironmentKey;
  }
  cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
  lastNetworkEnvironmentCheckAt = now;
  return cachedNetworkEnvironmentKey;
}

function readCurrentNetworkEnvironmentKey(): string {
  try {
    const defaultNetwork = connection.getDefaultNetSync();
    if (defaultNetwork.netId <= 0) {
      return 'offline';
    }
    const capabilities = connection.getNetCapabilitiesSync(defaultNetwork);
    const bearerTypes: number[] = [];
    for (let i = 0; i < capabilities.bearerTypes.length; i++) {
      bearerTypes.push(capabilities.bearerTypes[i] as number);
    }
    bearerTypes.sort((left: number, right: number): number => left - right);
    const networkCapabilities: number[] = [];
    if (capabilities.networkCap !== undefined) {
      for (let i = 0; i < capabilities.networkCap.length; i++) {
        networkCapabilities.push(capabilities.networkCap[i] as number);
      }
    }
    networkCapabilities.sort((left: number, right: number): number => left - right);
    const properties = connection.getConnectionPropertiesSync(defaultNetwork);
    const dnses: string[] = [];
    for (let i = 0; i < properties.dnses.length; i++) {
      dnses.push(properties.dnses[i].address);
    }
    dnses.sort();
    const linkAddresses: string[] = [];
    for (let i = 0; i < properties.linkAddresses.length; i++) {
      linkAddresses.push(properties.linkAddresses[i].address.address + '/' +
        properties.linkAddresses[i].prefixLength.toString());
    }
    linkAddresses.sort();
    return defaultNetwork.netId.toString() + ':' + bearerTypes.join(',') + ':' +
      networkCapabilities.join(',') + ':' + properties.interfaceName + ':' +
      dnses.join(',') + ':' + linkAddresses.join(',');
  } catch (error) {
    return 'offline';
  }
}

function markFreshEhConnectionsRequired(): void {
  forceFreshConnectionsUntilMs = Date.now() + FRESH_CONNECTION_WINDOW_MS;
}

function scheduleNetworkRuntimeRefresh(): void {
  if (networkChangeTimer >= 0) {
    clearTimeout(networkChangeTimer);
  }
  networkChangeTimer = setTimeout(() => {
    networkChangeTimer = -1;
    cachedNetworkEnvironmentKey = readCurrentNetworkEnvironmentKey();
    lastNetworkEnvironmentCheckAt = Date.now();
    if (refreshNetworkEnvironment()) {
      refreshNetworkRuntimeAfterChange();
    }
  }, NETWORK_CHANGE_DEBOUNCE_MS);
}

function refreshNetworkRuntimeAfterChange(): void {
  if (networkRecoveryTimer >= 0) {
    clearTimeout(networkRecoveryTimer);
    networkRecoveryTimer = -1;
  }
  if (!isEhNetworkProcessingEnabled()) {
    return;
  }
  const environmentKey = currentNetworkEnvironmentKey();
  if (environmentKey === 'offline') {
    return;
  }
  networkRecoveryTimer = setTimeout(() => {
    runNetworkRuntimeRecoveryWhenIdle(environmentKey);
  }, NETWORK_RECOVERY_SETTLE_MS);
}

function runNetworkRuntimeRecoveryWhenIdle(environmentKey: string): void {
  networkRecoveryTimer = -1;
  if (environmentKey !== currentNetworkEnvironmentKey() || currentNetworkEnvironmentKey() === 'offline') {
    refreshNetworkRuntimeAfterChange();
    return;
  }
  // HarmonyOS 6.1 may migrate existing curl tasks during a network handover. Starting the direct probe and
  // fronting benchmark before those tasks settle can make several timeouts complete in the same native multi loop.
  // Wait for normal requests to become idle; cached scores and real request outcomes remain usable meanwhile.
  if (hasActiveHttpRequests()) {
    networkRecoveryTimer = setTimeout(() => {
      runNetworkRuntimeRecoveryWhenIdle(environmentKey);
    }, NETWORK_RECOVERY_IDLE_RETRY_MS);
    return;
  }
  if (isEhDirectConnectionProbeEnabled()) {
    startEhDirectConnectionProbe(networkRuntimeContext).then((directAvailable: boolean) => {
      if (!directAvailable) {
        startEhFrontingBenchmark(networkRuntimeContext, true);
      }
    }).catch(() => {
      startEhFrontingBenchmark(networkRuntimeContext, true);
    });
    return;
  }
  ensureEhHostRules().then(() => {
    startEhFrontingBenchmark(networkRuntimeContext, true);
  }).catch(() => {
  });
}

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#:]+)/i.exec(url);
  return match === null ? '' : match[1];
}

function requestHostHeader(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  return match === null ? '' : match[1];
}

function replaceUrlHost(url: string, host: string): string {
  return url.replace(/^(https?:\/\/)([^\/?#]+)/i, '$1' + host);
}

function isIpv4(value: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(value);
}

function isHttpsUrl(url: string): boolean {
  return /^https:\/\//i.test(url);
}

function supportsDomainFrontingHost(host: string): boolean {
  const normalized = host.toLowerCase();
  return normalized === 'ehgt.org' || normalized === 'e-hentai.org' ||
    normalized.endsWith('.e-hentai.org') || normalized === 'exhentai.org' ||
    normalized.endsWith('.exhentai.org');
}

function waitHostRuleTask(task: Promise<void>, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      resolve();
    }, timeoutMs);
    task.then(() => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve();
    }).catch(() => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve();
    });
  });
}

function parseProxyPort(value: string): number {
  const port = Number.parseInt(value.trim());
  return Number.isNaN(port) ? -1 : port;
}

function isValidPort(port: number): boolean {
  return port > 0 && port <= 65535;
}

function parseProxyExclusionList(value: string): string[] {
  const result: string[] = [];
  const parts = value.split(',');
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i].trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result;
}

function proxySettingsKey(): string {
  return ehSettingsStore.getValue('proxy', 'System') + ':' +
    ehSettingsStore.getValue('proxy_host', '') + ':' +
    ehSettingsStore.getValue('proxy_port', '') + ':' +
    ehSettingsStore.getValue('proxy_username', '') + ':' +
    hashText(ehSettingsStore.getValue('proxy_password', '')) + ':' +
    ehSettingsStore.getValue('proxy_exclusion_list', '') + ':' +
    ehSettingsStore.getValue('proxy_socks_dns', 'Proxy');
}

export function currentDnsOverHttpsUrl(): string {
  if (ehSettingsStore.getValue('dns_over_https', 'Off') !== 'On') {
    return '';
  }
  const provider = currentDnsOverHttpsProvider();
  if (provider === 'Cloudflare') {
    return CLOUDFLARE_DOH_URL;
  }
  if (provider === 'Google') {
    return GOOGLE_DOH_URL;
  }
  return YANDEX_DOH_URL;
}

export function currentDnsOverHttpsStatusText(): string {
  const url = currentDnsOverHttpsUrl();
  return url.length > 0 ? 'On ' + currentDnsOverHttpsProvider() + ' ' + url : 'Off';
}

function dohSettingsKey(): string {
  if (ehSettingsStore.getValue('dns_over_https', 'Off') !== 'On') {
    return 'Off';
  }
  return 'On:' + currentDnsOverHttpsProvider();
}

function currentDnsOverHttpsProvider(): string {
  const provider = ehSettingsStore.getValue('dns_over_https_provider', 'Yandex');
  return provider === 'Cloudflare' || provider === 'Google' ? provider : 'Yandex';
}

function hashText(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash = (hash ^ value.charCodeAt(i)) * 16777619;
  }
  return value.length.toString() + '-' + (hash >>> 0).toString(16);
}

async function applyHostRules(key: string): Promise<void> {
  try {
    await removeKnownHostRules();
    const rules: HostRule[] = [];
    if (ehSettingsStore.getValue('built_in_hosts', 'Off') === 'On') {
      pushRules(rules, BUILT_IN_RULES);
    }
    if (ehSettingsStore.getValue('built_ex_hosts', 'Off') === 'On') {
      pushRules(rules, BUILT_EX_RULES);
    }
    for (let i = 0; i < rules.length; i++) {
      await connection.addCustomDnsRule(rules[i].host, rules[i].ips);
    }
    appliedHostRulesKey = key;
  } catch (error) {
    appliedHostRulesKey = '';
  }
}

async function removeKnownHostRules(): Promise<void> {
  appliedHostRulesKey = '';
  const rules: HostRule[] = [];
  pushRules(rules, BUILT_IN_RULES);
  pushRules(rules, BUILT_EX_RULES);
  for (let i = 0; i < rules.length; i++) {
    try {
      await connection.removeCustomDnsRule(rules[i].host);
    } catch (error) {
    }
  }
}

async function restoreConfiguredHostRules(): Promise<void> {
  const key = ehSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    ehSettingsStore.getValue('built_ex_hosts', 'Off');
  if (key === 'Off:Off') {
    await removeKnownHostRules();
    appliedHostRulesKey = key;
    return;
  }
  await applyHostRules(key);
}

function pushRules(target: HostRule[], source: HostRule[]): void {
  for (let i = 0; i < source.length; i++) {
    target.push(source[i]);
  }
}
