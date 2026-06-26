import { http } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { ehSettingsStore } from './EhSettingsStore';

const DOH_URL: string = 'https://77.88.8.1/dns-query';
const FRONTING_PROBE_CONNECT_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_READ_TIMEOUT_MS: number = 3000;
const FRONTING_PROBE_DEADLINE_MS: number = 4500;
const FRONTING_PROBE_CONCURRENCY: number = 4;
const FRONTING_FAST_IP_LIMIT: number = 3;
const FRONTING_PROBE_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const BUILT_IN_RULES: HostRule[] = [
  { host: 'e-hentai.org', ips: ['104.20.18.168', '104.20.19.168', '172.66.132.196', '172.66.140.62', '172.67.2.238'] },
  { host: 'repo.e-hentai.org', ips: ['104.20.18.168', '104.20.19.168', '172.67.2.238'] },
  { host: 'forums.e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'upld.e-hentai.org', ips: ['89.149.221.236', '95.211.208.236'] },
  { host: 'ehgt.org', ips: ['109.236.85.28', '62.112.8.21', '89.39.106.43', '2a00:7c80:0:123::3a85', '2a00:7c80:0:12d::38a1', '2a00:7c80:0:13b::37a4'] },
  { host: 'raw.githubusercontent.com', ips: ['151.101.0.133', '151.101.64.133', '151.101.128.133', '151.101.192.133'] }
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
}

interface HostIpProbeTarget {
  host: string;
  ip: string;
}

export interface EhRequestPlan {
  url: string;
  host: string;
  fronted: boolean;
  sniHost: string;
}

export function createEhRequestPlan(url: string): EhRequestPlan {
  const host = requestHost(url);
  const hostHeader = requestHostHeader(url);
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

export function applyEhNetworkOptions(options: http.HttpRequestOptions, plan: EhRequestPlan): void {
  options.usingCache = false;
  options.usingProxy = proxyOption();
  if (ehSettingsStore.getValue('dns_over_https', 'Off') === 'On') {
    options.dnsOverHttps = DOH_URL;
  }
  if (plan.fronted) {
    options.remoteValidation = 'skip';
    options.usingProtocol = http.HttpProtocol.HTTP1_1;
  }
  if (plan.sniHost.length > 0) {
    options.sniHostName = plan.sniHost;
  }
}

export function startEhFrontingBenchmark(): void {
  const key = frontingBenchmarkKey();
  if (key === 'Off') {
    clearIpQualities();
    frontingProbeKey = key;
    return;
  }
  if (key === frontingProbeKey && frontingProbePending !== null) {
    return;
  }
  frontingProbeKey = key;
  frontingProbeGeneration++;
  clearIpQualities();
  const generation = frontingProbeGeneration;
  frontingProbePending = runEhFrontingBenchmark(generation).then(() => {
    if (generation === frontingProbeGeneration) {
      frontingProbePending = null;
    }
  }).catch(() => {
    if (generation === frontingProbeGeneration) {
      frontingProbePending = null;
    }
  });
}

export async function ensureEhHostRules(): Promise<void> {
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
  if (proxyType === 'HTTP' || proxyType === 'SOCKS') {
    const host = ehSettingsStore.getValue('proxy_host', '').trim();
    const port = parseProxyPort(ehSettingsStore.getValue('proxy_port', ''));
    if (host.length > 0 && isValidPort(port)) {
      return {
        host: host,
        port: port,
        exclusionList: []
      };
    }
  }
  return proxyType === 'System';
}

function eFrontingIpForUrl(url: string, host: string): string {
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On' || !isHttpsUrl(url) || host.length === 0) {
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
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On' || !isHttpsUrl(url) || host.length === 0) {
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
  const rankedIps = rankedIpv4ListForHost(host, rules);
  const ips = rankedIps.length > 0 ? rankedIps : ipv4ListForHost(host, rules);
  if (ips.length === 0) {
    return '';
  }
  let cursor = cursorForHost(host);
  if (cursor.next < 0 || cursor.next >= ips.length) {
    cursor.next = Math.floor(Math.random() * ips.length);
  }
  const ip = ips[cursor.next];
  cursor.next = (cursor.next + 1) % ips.length;
  return ip;
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

function rankedIpv4ListForHost(host: string, rules: HostRule[]): string[] {
  const candidates = ipv4ListForHost(host, rules);
  if (candidates.length === 0) {
    return [];
  }

  const results: HostIpQuality[] = [];
  for (let i = 0; i < HOST_IP_QUALITIES.length; i++) {
    const item = HOST_IP_QUALITIES[i];
    if (item.host === host && item.ok && containsString(candidates, item.ip)) {
      results.push(item);
    }
  }
  if (results.length === 0) {
    return [];
  }

  results.sort((left: HostIpQuality, right: HostIpQuality) => {
    if (left.latencyMs !== right.latencyMs) {
      return left.latencyMs - right.latencyMs;
    }
    return left.ip.localeCompare(right.ip);
  });
  const ranked: string[] = [];
  const limit = Math.min(FRONTING_FAST_IP_LIMIT, results.length);
  for (let i = 0; i < limit; i++) {
    ranked.push(results[i].ip);
  }
  return ranked;
}

async function runEhFrontingBenchmark(generation: number): Promise<void> {
  const targets = collectFrontingProbeTargets();
  if (targets.length === 0) {
    return;
  }
  let nextIndex = 0;
  const workers: Promise<void>[] = [];
  const workerCount = Math.min(FRONTING_PROBE_CONCURRENCY, targets.length);
  for (let i = 0; i < workerCount; i++) {
    workers.push(new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
      runFrontingProbeWorker(targets, generation, () => {
        const index = nextIndex;
        nextIndex++;
        return index;
      }).then(() => {
        resolve();
      }).catch(() => {
        resolve();
      });
    }));
  }
  await Promise.all(workers);
}

async function runFrontingProbeWorker(targets: HostIpProbeTarget[], generation: number,
  next: () => number): Promise<void> {
  while (generation === frontingProbeGeneration) {
    const index = next();
    if (index >= targets.length) {
      return;
    }
    const result = await probeFrontingIp(targets[index]);
    if (generation === frontingProbeGeneration) {
      recordIpQuality(result);
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
    await requestWithProbeDeadline(request, 'https://' + target.ip + '/', options, FRONTING_PROBE_DEADLINE_MS);
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

function requestWithProbeDeadline(request: http.HttpRequest, url: string, options: http.HttpRequestOptions,
  timeoutMs: number): Promise<http.HttpResponse> {
  return new Promise<http.HttpResponse>((resolve: (value: http.HttpResponse) => void, reject: (reason: Error) => void) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      try {
        request.destroy();
      } catch (error) {
      }
      reject(new Error('Probe timed out'));
    }, timeoutMs);

    request.request(url, options).then((response: http.HttpResponse) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve(response);
    }).catch((error: Error) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      reject(error);
    });
  });
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

function clearIpQualities(): void {
  HOST_IP_QUALITIES.splice(0, HOST_IP_QUALITIES.length);
  for (let i = 0; i < HOST_IP_CURSORS.length; i++) {
    HOST_IP_CURSORS[i].next = -1;
  }
}

function frontingBenchmarkKey(): string {
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On') {
    return 'Off';
  }
  return ehSettingsStore.getValue('built_in_hosts', 'Off') + ':' +
    ehSettingsStore.getValue('built_ex_hosts', 'Off') + ':' +
    ehSettingsStore.getValue('proxy', 'System') + ':' +
    ehSettingsStore.getValue('proxy_host', '') + ':' +
    ehSettingsStore.getValue('proxy_port', '');
}

function containsString(values: string[], value: string): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
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
