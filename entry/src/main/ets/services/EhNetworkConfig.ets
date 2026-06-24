import { http } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { ehSettingsStore } from './EhSettingsStore';

const DOH_URL: string = 'https://77.88.8.1/dns-query';
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

interface HostRule {
  host: string;
  ips: string[];
}

export function applyEhNetworkOptions(options: http.HttpRequestOptions, url: string = ''): void {
  options.usingCache = false;
  options.usingProxy = proxyOption();
  if (ehSettingsStore.getValue('dns_over_https', 'Off') === 'On') {
    options.dnsOverHttps = DOH_URL;
  }
  const sniHost = domainFrontingSniHost(url);
  if (sniHost.length > 0) {
    options.sniHostName = sniHost;
  }
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

function domainFrontingSniHost(url: string): string {
  if (ehSettingsStore.getValue('domain_fronting', 'On') !== 'On' || !isHttpsUrl(url)) {
    return '';
  }
  return frontingIpForHost(requestHost(url));
}

function frontingIpForHost(host: string): string {
  const normalizedHost = host.toLowerCase();
  if (ehSettingsStore.getValue('built_in_hosts', 'Off') === 'On') {
    const ip = firstIpv4ForHost(normalizedHost, BUILT_IN_RULES);
    if (ip.length > 0) {
      return ip;
    }
  }
  if (ehSettingsStore.getValue('built_ex_hosts', 'Off') === 'On') {
    const ip = firstIpv4ForHost(normalizedHost, BUILT_EX_RULES);
    if (ip.length > 0) {
      return ip;
    }
  }
  return '';
}

function firstIpv4ForHost(host: string, rules: HostRule[]): string {
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].host !== host) {
      continue;
    }
    for (let j = 0; j < rules[i].ips.length; j++) {
      if (isIpv4(rules[i].ips[j])) {
        return rules[i].ips[j];
      }
    }
  }
  return '';
}

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#:]+)/i.exec(url);
  return match === null ? '' : match[1];
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
