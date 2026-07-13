import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { ehSettingsStore } from './EhSettingsStore';

const DOH_URL: string = 'https://77.88.8.1/dns-query';
const FRONTING_IP_CACHE_FILE_NAME: string = 'eh_fronting_ip_quality.json';
const FRONTING_IP_CACHE_VERSION: number = 1;
const FRONTING_PROBE_CONNECT_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_READ_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_DEADLINE_MS: number = 4500;
const FRONTING_PROBE_CONCURRENCY: number = 4;
const FRONTING_FAST_IP_LIMIT: number = 3;
const DIRECT_PROBE_TIMEOUT_MS: number = 5000;
const DIRECT_HOST_FAILURE_THRESHOLD: number = 1;
const DIRECT_HOST_BLOCK_MS: number = 120000;
const IP_FAILURE_LATENCY_PENALTY_MS: number = 2500;
const IP_SUCCESS_LATENCY_BONUS_MS: number = 120;
const IP_RETRY_DEMOTE_THRESHOLD: number = 2;
const IP_UNTESTED_LATENCY_MS: number = 2200;
const IP_QUALITY_SAVE_THROTTLE_MS: number = 30000;
const IP_SLOW_RESPONSE_THRESHOLD_MS: number = 4000;
const IP_SLOW_LATENCY_PENALTY_MS: number = 350;
const FRONTING_PROBE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const BUILT_IN_RULES: HostRule[] = [
  { host: 'e-hentai.org', ips: ['104.20.18.168', '104.20.19.168', '172.66.132.196', '172.66.140.62', '172.67.2.238'] },
  { host: 'repo.e-hentai.org', ips: ['104.20.18.168', '104.20.19.168', '172.66.132.196', '172.66.140.62', '172.67.2.238'] },
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
const HOST_IP_CURSORS: HostIpCursor[] = [];
const HOST_IP_QUALITIES: HostIpQuality[] = [];
let frontingProbeKey: string = '';
let frontingProbeGeneration: number = 0;
let frontingProbePending: Promise<void> | null = null;
let frontingIpCachePath: string = '';
let frontingIpCacheLoadedKey: string = '';
let directProbeKey: string = '';
let directProbeGeneration: number = 0;
let directProbePending: Promise<boolean> | null = null;
let directProbePassed: boolean = false;
let observedNetworkEnvironmentKey: string = '';
let lastIpQualitySaveAt: number = 0;
const DIRECT_HOST_FAILURES: DirectHostFailure[] = [];

interface HostRule {
  host: string;
  ips: string[];
}

interface HostIpCursor {
  host: string;
  next: number;
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
  qualities?: HostIpQuality[];
}

export interface EhRequestPlan {
  url: string;
  host: string;
  fronted: boolean;
  sniHost: string;
}

export function createEhRequestPlan(url: string): EhRequestPlan {
  refreshNetworkEnvironment();
  ensureFrontingQualityCacheLoaded();
  const host = requestHost(url);
  const hostHeader = requestHostHeader(url);
  if (shouldUseDirectConnection(host)) {
    return {
      url: url,
      host: hostHeader,
      fronted: false,
      sniHost: host
    };
  }
  const exFrontingIp = exFrontingIpForUrl(url, host);
  if (exFrontingIp.length > 0) {
    return {
      url: replaceUrlHost(url, exFrontingIp),
      host: hostHeader,
      fronted: true,
      sniHost: ''
    };
  }
  const eFrontingIp = eFrontingIpForUrl(url, host);
  if (eFrontingIp.length === 0) {
    return {
      url: url,
      host: hostHeader,
      fronted: false,
      sniHost: host
    };
  }
  return {
    url: replaceUrlHost(url, eFrontingIp),
    host: hostHeader,
    fronted: true,
    sniHost: ''
  };
}

function ensureFrontingQualityCacheLoaded(): void {
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    return;
  }
  loadCachedIpQualities(key);
}

export function applyEhNetworkOptions(options: http.HttpRequestOptions, plan: EhRequestPlan): void {
  options.usingCache = false;
  options.usingProxy = proxyOption();
  const dohUrl = currentDnsOverHttpsUrl();
  if (dohUrl.length > 0) {
    options.dnsOverHttps = dohUrl;
  }
  if (plan.fronted) {
    options.usingProtocol = http.HttpProtocol.HTTP1_1;
    options.remoteValidation = 'skip';
  }
  if (deviceInfo.apiAvailable(23)) {
    if (plan.sniHost.length > 0) {
      options.sniHostName = plan.sniHost;
    }
  }
}

export function startEhDirectConnectionProbe(context?: common.UIAbilityContext): Promise<boolean> {
  if (context !== undefined) {
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  refreshNetworkEnvironment();
  const key = directProbeKeyValue();
  if (key === 'Off') {
    directProbeGeneration++;
    directProbeKey = key;
    directProbePending = null;
    directProbePassed = false;
    clearDirectHostFailures();
    return Promise.resolve(false);
  }
  if (directProbePending !== null && directProbeKey === key) {
    return directProbePending;
  }
  directProbeKey = key;
  directProbePassed = false;
  directProbeGeneration++;
  const generation = directProbeGeneration;
  directProbePending = removeKnownHostRules().then(() => {
    return probeDirectSelectedSite();
  }).then((passed: boolean) => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = passed;
      if (passed) {
        clearDirectHostFailures();
      }
      directProbePending = null;
    }
    return passed;
  }).catch(() => {
    if (generation === directProbeGeneration && directProbeKey === key) {
      directProbePassed = false;
      directProbePending = null;
    }
    return false;
  });
  return directProbePending;
}

export function isEhDirectConnectionProbeEnabled(): boolean {
  return ehSettingsStore.getValue('auto_direct_connection', 'On') === 'On';
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
  const now = Date.now();
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
  if (ok) {
    saveCachedIpQualitiesThrottled(frontingBenchmarkKey());
  } else {
    saveCachedIpQualities(frontingBenchmarkKey());
  }
}

export function startEhFrontingBenchmark(context?: common.UIAbilityContext): void {
  if (context !== undefined) {
    frontingIpCachePath = context.filesDir + '/' + FRONTING_IP_CACHE_FILE_NAME;
  }
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    clearIpQualities();
    frontingProbeKey = key;
    frontingIpCacheLoadedKey = '';
    return;
  }
  const hasCachedBenchmark = loadCachedIpQualities(key);
  if (key === frontingProbeKey && frontingProbePending !== null) {
    return;
  }
  if (hasCachedBenchmark || hasUsableIpQualities()) {
    return;
  }
  frontingProbeKey = key;
  frontingProbeGeneration++;
  const generation = frontingProbeGeneration;
  frontingProbePending = runEhFrontingBenchmark(generation).then((results: HostIpQuality[]) => {
    if (generation === frontingProbeGeneration) {
      replaceIpQualities(results);
      saveCachedIpQualities(key);
      frontingProbePending = null;
    }
  }).catch(() => {
    if (generation === frontingProbeGeneration) {
      frontingProbePending = null;
    }
  });
}

export async function ensureEhHostRules(): Promise<void> {
  if (directProbePassed && ehSettingsStore.getValue('auto_direct_connection', 'On') === 'On') {
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
      if (appliedHostRulesKey.length > 0) {
        await waitHostRuleTask(removeKnownHostRules(), 1200);
      }
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
  if (proxyType === 'HTTP' || proxyType === 'SOCKS') {
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
  return proxyType === 'System';
}

function eFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || ehSettingsStore.getValue('domain_fronting', 'On') !== 'On' ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  if (ehSettingsStore.getValue('built_in_hosts', 'Off') === 'On') {
    const ip = rotatingIpv4ForHost(normalizedHost, BUILT_IN_RULES);
    if (ip.length > 0) {
      return ip;
    }
  }
  return '';
}

function exFrontingIpForUrl(url: string, host: string): string {
  if (shouldUseDirectConnection(host) || ehSettingsStore.getValue('domain_fronting', 'On') !== 'On' ||
    !isHttpsUrl(url) || host.length === 0 || !supportsDomainFrontingHost(host)) {
    return '';
  }
  const normalizedHost = host.toLowerCase();
  if (ehSettingsStore.getValue('built_ex_hosts', 'Off') === 'On') {
    const ip = rotatingIpv4ForHost(normalizedHost, BUILT_EX_RULES);
    if (ip.length > 0) {
      return ip;
    }
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
  let cursor = cursorForHost(host);
  if (cursor.next < 0 || cursor.next >= fallbackIps.length) {
    cursor.next = Math.floor(Math.random() * fallbackIps.length);
  }
  const fallbackIp = fallbackIps[cursor.next];
  cursor.next = (cursor.next + 1) % fallbackIps.length;
  return fallbackIp;
}

function cursorForHost(host: string): HostIpCursor {
  for (let i = 0; i < HOST_IP_CURSORS.length; i++) {
    if (HOST_IP_CURSORS[i].host === host) {
      return HOST_IP_CURSORS[i];
    }
  }
  const cursor: HostIpCursor = {
    host: host,
    next: -1
  };
  HOST_IP_CURSORS.push(cursor);
  return cursor;
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
  const limit = Math.min(FRONTING_FAST_IP_LIMIT, results.length);
  let totalWeight = 0;
  for (let i = 0; i < limit; i++) {
    totalWeight += ipQualityWeight(results[i]);
  }
  if (totalWeight <= 0) {
    return results[0].ip;
  }
  let ticket = Math.random() * totalWeight;
  for (let i = 0; i < limit; i++) {
    ticket -= ipQualityWeight(results[i]);
    if (ticket <= 0) {
      return results[i].ip;
    }
  }
  return results[0].ip;
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

async function probeFrontingIp(target: HostIpProbeTarget): Promise<HostIpQuality> {
  const request = http.createHttp();
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
      usingProxy: proxyOption(),
      usingProtocol: http.HttpProtocol.HTTP1_1,
      remoteValidation: 'skip',
      connectTimeout: FRONTING_PROBE_CONNECT_TIMEOUT_MS,
      readTimeout: FRONTING_PROBE_READ_TIMEOUT_MS
    };
    await requestProbeToCompletion(request, 'https://' + target.ip + '/', options);
    return {
      host: target.host,
      ip: target.ip,
      ok: true,
      latencyMs: Math.max(1, Date.now() - startedAt),
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
    try {
      request.destroy();
    } catch (error) {
    }
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
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On') {
    return targets;
  }
  if (ehSettingsStore.getValue('built_in_hosts', 'Off') === 'On') {
    pushProbeTargets(targets, BUILT_IN_RULES);
  }
  if (ehSettingsStore.getValue('built_ex_hosts', 'Off') === 'On') {
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

function ipQualityWeight(item: HostIpQuality): number {
  const score = Math.max(100, ipQualityScore(item));
  const successCount = item.successCount === undefined ? 0 : item.successCount;
  const failureCount = item.failureCount === undefined ? 0 : item.failureCount;
  const reliability = Math.max(1, 8 + successCount * 2 - failureCount * 5);
  return Math.max(1, Math.round(100000 * reliability / score));
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

function clearIpQualities(): void {
  HOST_IP_QUALITIES.splice(0, HOST_IP_QUALITIES.length);
  for (let i = 0; i < HOST_IP_CURSORS.length; i++) {
    HOST_IP_CURSORS[i].next = -1;
  }
}

function loadCachedIpQualities(key: string): boolean {
  if (frontingIpCacheLoadedKey === key) {
    return true;
  }
  clearIpQualities();
  frontingIpCacheLoadedKey = key;
  if (frontingIpCachePath.length === 0) {
    return false;
  }
  try {
    const parsed = JSON.parse(fs.readTextSync(frontingIpCachePath)) as FrontingIpQualityCache;
    if (parsed.key !== key || !Array.isArray(parsed.qualities)) {
      return false;
    }
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
      }
    }
    return true;
  } catch (error) {
    return false;
  }
}

function saveCachedIpQualities(key: string): void {
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
    const payload: FrontingIpQualityCache = {
      version: FRONTING_IP_CACHE_VERSION,
      key: key,
      updatedAt: Date.now(),
      qualities: qualities
    };
    fs.writeSync(fd, JSON.stringify(payload));
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
  if (!directProbePassed || ehSettingsStore.getValue('auto_direct_connection', 'On') !== 'On') {
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
  if (!directProbePassed || ehSettingsStore.getValue('auto_direct_connection', 'On') !== 'On') {
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
  if (ehSettingsStore.getValue('auto_direct_connection', 'On') !== 'On') {
    return 'Off';
  }
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') + ':' + proxySettingsKey() + ':' +
    dohSettingsKey() + ':' + currentNetworkEnvironmentKey();
}

function selectedGalleryHost(): string {
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? 'exhentai.org' : 'e-hentai.org';
}

async function probeDirectSelectedSite(): Promise<boolean> {
  const request = http.createHttp();
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
      usingProxy: proxyOption(),
      connectTimeout: DIRECT_PROBE_TIMEOUT_MS,
      readTimeout: DIRECT_PROBE_TIMEOUT_MS
    };
    const dohUrl = currentDnsOverHttpsUrl();
    if (dohUrl.length > 0) {
      options.dnsOverHttps = dohUrl;
    }
    const response = await requestProbeToCompletion(request, 'https://' + host + '/', options);
    const statusCode = Number(response.responseCode);
    return statusCode > 0 && statusCode < 500;
  } catch (error) {
    return false;
  } finally {
    try {
      request.destroy();
    } catch (error) {
    }
  }
}

function isKnownProbeTarget(host: string, ip: string): boolean {
  const targets = collectFrontingProbeTargets();
  for (let i = 0; i < targets.length; i++) {
    if (targets[i].host === host && targets[i].ip === ip) {
      return true;
    }
  }
  return false;
}

function frontingBenchmarkKey(): string {
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On') {
    return 'Off';
  }
  return ehSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    ehSettingsStore.getValue('built_ex_hosts', 'Off') + ':' +
    proxySettingsKey() + ':' +
    dohSettingsKey() + ':' + currentNetworkEnvironmentKey();
}

function refreshNetworkEnvironment(): void {
  const key = currentNetworkEnvironmentKey();
  if (key.length === 0) {
    return;
  }
  if (observedNetworkEnvironmentKey.length === 0) {
    observedNetworkEnvironmentKey = key;
    return;
  }
  if (observedNetworkEnvironmentKey === key) {
    return;
  }
  observedNetworkEnvironmentKey = key;
  directProbeGeneration++;
  directProbeKey = '';
  directProbePending = null;
  directProbePassed = false;
  clearDirectHostFailures();
  frontingProbeGeneration++;
  frontingProbeKey = '';
  frontingProbePending = null;
  frontingIpCacheLoadedKey = '';
  HOST_IP_CURSORS.splice(0, HOST_IP_CURSORS.length);
  HOST_IP_QUALITIES.splice(0, HOST_IP_QUALITIES.length);
}

function currentNetworkEnvironmentKey(): string {
  try {
    const networks = connection.getAllNetsSync();
    const entries: string[] = [];
    for (let i = 0; i < networks.length; i++) {
      const capabilities = connection.getNetCapabilitiesSync(networks[i]);
      const bearerTypes: number[] = [];
      for (let j = 0; j < capabilities.bearerTypes.length; j++) {
        bearerTypes.push(capabilities.bearerTypes[j] as number);
      }
      bearerTypes.sort((left: number, right: number): number => left - right);
      entries.push(networks[i].netId.toString() + ':' + bearerTypes.join(','));
    }
    entries.sort();
    return entries.join('|');
  } catch (error) {
    return '';
  }
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
    ehSettingsStore.getValue('proxy_exclusion_list', '');
}

export function currentDnsOverHttpsUrl(): string {
  return ehSettingsStore.getValue('dns_over_https', 'Off') === 'On' ? DOH_URL : '';
}

export function currentDnsOverHttpsStatusText(): string {
  const url = currentDnsOverHttpsUrl();
  return url.length > 0 ? 'On ' + url : 'Off';
}

function dohSettingsKey(): string {
  return ehSettingsStore.getValue('dns_over_https', 'Off');
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
    if (appliedHostRulesKey.length > 0) {
      await removeKnownHostRules();
    }
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

function pushRules(target: HostRule[], source: HostRule[]): void {
  for (let i = 0; i < source.length; i++) {
    target.push(source[i]);
  }
}
