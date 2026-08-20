import type { DnsAdapter, DnsRecordInput } from "../index";

export interface GoDaddyDnsConfig {
  personalAccessToken: string;
  baseUrl?: string;
}

type GoDaddyDnsRecord = {
  recordId: string;
  type: DnsRecordInput["type"] | "SRV" | "NS" | "SOA";
  name: string;
  data: string;
  ttl: number;
  priority?: number;
};

type GoDaddyDnsCollection = {
  items: GoDaddyDnsRecord[];
  page?: number;
  pageSize?: number;
  total?: number;
};

const SUPPORTED_RECORD_TYPES = new Set<DnsRecordInput["type"]>(["A", "AAAA", "CNAME", "TXT", "MX", "CAA"]);

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

  private async listDetailed(domain: string): Promise<GoDaddyDnsRecord[]> {
    const items: GoDaddyDnsRecord[] = [];
    let page = 1;
    const pageSize = 100;

    while (true) {
      const url = new URL(`${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records`);
      url.searchParams.set("page", String(page));
      url.searchParams.set("pageSize", String(pageSize));

      const response = await fetch(url, { headers: this.headers(), cache: "no-store" });
      if (!response.ok) throw new Error(`GoDaddy DNS list failed (${response.status})`);

      const payload = await response.json() as GoDaddyDnsCollection;
      const pageItems = Array.isArray(payload.items) ? payload.items : [];
      items.push(...pageItems);

      if (pageItems.length < pageSize || (payload.total != null && items.length >= payload.total)) break;
      page += 1;
    }

    return items;
  }

  async listRecords(domain: string): Promise<DnsRecordInput[]> {
    const records = await this.listDetailed(domain);
    return records
      .filter((record): record is GoDaddyDnsRecord & { type: DnsRecordInput["type"] } => SUPPORTED_RECORD_TYPES.has(record.type as DnsRecordInput["type"]))
      .map(record => ({
        type: record.type,
        name: record.name,
        value: record.data,
        ttl: record.ttl,
        priority: record.priority
      }));
  }

  async upsertRecord(domain: string, record: DnsRecordInput): Promise<void> {
    const existing = await this.listDetailed(domain);
    const identical = existing.some(item =>
      item.type === record.type &&
      item.name === record.name &&
      item.data === record.value &&
      (record.priority == null || item.priority === record.priority)
    );
    if (identical) return;

    const response = await fetch(`${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records`, {
      method: "POST",
      headers: this.headers({ "Content-Type": "application/json" }),
      body: JSON.stringify({
        type: record.type,
        name: record.name,
        data: record.value,
        ttl: Math.max(600, Math.min(record.ttl ?? 600, 86400)),
        priority: record.priority
      })
    });
    if (!response.ok) throw new Error(`GoDaddy DNS create failed (${response.status})`);
  }

  async deleteRecord(domain: string, record: DnsRecordInput): Promise<void> {
    const existing = await this.listDetailed(domain);
    const matches = existing.filter(item =>
      item.type === record.type &&
      item.name === record.name &&
      item.data === record.value &&
      (record.priority == null || item.priority === record.priority)
    );

    for (const match of matches) {
      const response = await fetch(
        `${this.baseUrl}/domains/zones/${encodeURIComponent(domain)}/dns-records/${encodeURIComponent(match.recordId)}`,
        { method: "DELETE", headers: this.headers() }
      );
      if (!response.ok && response.status !== 404) throw new Error(`GoDaddy DNS delete failed (${response.status})`);
    }
  }
}
