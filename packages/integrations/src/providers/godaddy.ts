import type { DnsAdapter, DnsRecordInput } from "../index";

export interface GoDaddyDnsConfig {
  personalAccessToken: string;
  baseUrl?: string;
}

type GoDaddyDnsRecord = {
  type: DnsRecordInput["type"] | "SRV" | "NS" | "SOA" | "ALIAS";
  name: string;
  data: string;
  ttl: number;
  priority?: number;
};

export class GoDaddyDnsAdapter implements DnsAdapter {
  private readonly baseUrl: string;
  constructor(private readonly config: GoDaddyDnsConfig) {
    this.baseUrl = config.baseUrl ?? "https://api.godaddy.com/v3";
  }

  private headers(extra?: HeadersInit): HeadersInit {
    return {
      Authorization: `Bearer ${this.config.personalAccessToken}`,
      Accept: "application/json",
      ...extra
    };
  }

  async listRecords(domain: string): Promise<DnsRecordInput[]> {
    const response = await fetch(`${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records?pageSize=100`, {
      headers: this.headers(),
      cache: "no-store"
    });
    if (!response.ok) throw new Error(`GoDaddy DNS list failed (${response.status})`);
    const payload = await response.json() as { records?: GoDaddyDnsRecord[] } | GoDaddyDnsRecord[];
    const records = Array.isArray(payload) ? payload : payload.records ?? [];
    return records
      .filter((record): record is GoDaddyDnsRecord & { type: DnsRecordInput["type"] } => ["A","AAAA","CNAME","TXT","MX","CAA"].includes(record.type))
      .map(record => ({ type: record.type, name: record.name, value: record.data, ttl: record.ttl, priority: record.priority }));
  }

  async upsertRecord(domain: string, record: DnsRecordInput): Promise<void> {
    // GoDaddy v3 exposes create and delete operations. A governed "upsert" is implemented
    // by checking the current record set first, then creating only when an identical record
    // does not already exist. Replacements should be performed by the higher-level DNS
    // change workflow so before/after evidence and rollback instructions are preserved.
    const existing = await this.listRecords(domain);
    if (existing.some(item => item.type === record.type && item.name === record.name && item.value === record.value)) return;

    const response = await fetch(`${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records`, {
      method: "POST",
      headers: this.headers({ "Content-Type": "application/json" }),
      body: JSON.stringify({ type: record.type, name: record.name, data: record.value, ttl: record.ttl ?? 600, priority: record.priority })
    });
    if (!response.ok) throw new Error(`GoDaddy DNS create failed (${response.status})`);
  }

  async deleteRecord(domain: string, record: DnsRecordInput): Promise<void> {
    const url = new URL(`${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records`);
    url.searchParams.set("type", record.type);
    url.searchParams.set("name", record.name);
    url.searchParams.set("data", record.value);
    const response = await fetch(url, { method: "DELETE", headers: this.headers() });
    if (!response.ok && response.status !== 404) throw new Error(`GoDaddy DNS delete failed (${response.status})`);
  }
}
