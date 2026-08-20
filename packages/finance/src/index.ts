export type AccountType = "asset" | "liability" | "equity" | "income" | "expense";
export type JournalStatus = "draft" | "posted" | "reversed";
export type TaxKind = "GST" | "TDS" | "TCS" | "WITHHOLDING" | string;

export interface LedgerAccount {
  id:string;
  organisationId:string;
  code:string;
  name:string;
  type:AccountType;
  parentId?:string;
  currency?:string;
  active:boolean;
}

export interface JournalLine {
  id:string;
  accountId:string;
  projectId?:string;
  costCode?:string;
  counterpartyId?:string;
  debit:number;
  credit:number;
  currency:string;
  taxDeterminationId?:string;
  memo?:string;
}

export interface JournalEntry {
  id:string;
  organisationId:string;
  journalNumber:string;
  postingDate:string;
  status:JournalStatus;
  sourceType:string;
  sourceId?:string;
  lines:JournalLine[];
  createdBy:string;
  postedBy?:string;
  postedAt?:string;
}

export interface EffectiveRule<T = Record<string,unknown>> {
  id:string;
  ruleSet:string;
  code:string;
  jurisdiction:string;
  effectiveFrom:string;
  effectiveUntil?:string;
  priority:number;
  conditions:Record<string,unknown>;
  outcome:T;
  sourceReference:string;
  publicationStatus:"draft" | "review" | "published" | "retired";
}

export interface TaxContext {
  transactionDate:string;
  supplierState?:string;
  recipientState?:string;
  placeOfSupplyState?:string;
  supplierRegistrationType?:string;
  recipientRegistrationType?:string;
  serviceCode?:string;
  goodsCode?:string;
  taxableAmount:number;
  reverseChargeCandidate?:boolean;
  counterpartyType?:string;
  projectId?:string;
}

export interface TaxComponent {
  name:string;
  rate:number;
  amount:number;
  payableBy:"supplier" | "recipient" | "withholder";
  ledgerCode?:string;
}

export interface TaxDetermination {
  id:string;
  context:TaxContext;
  ruleIds:string[];
  components:TaxComponent[];
  status:"determined" | "needs_review" | "not_verified";
  explanation:string[];
}

export interface BankTransaction {
  id:string;
  bankAccountId:string;
  bookedAt:string;
  valueDate?:string;
  amount:number;
  currency:string;
  direction:"credit" | "debit";
  reference?:string;
  counterparty?:string;
  matchedJournalLineId?:string;
  reconciliationStatus:"unmatched" | "suggested" | "matched" | "excluded";
}

export interface ProjectFinancialSnapshot {
  projectId:string;
  asOf:string;
  contractedRevenue:number;
  recognisedRevenue:number;
  invoiced:number;
  collected:number;
  receivables:number;
  tdsReceivable:number;
  committedCost:number;
  actualCost:number;
  forecastCost:number;
  grossMargin:number;
  cashPosition:number;
}

export function journalBalances(entry: JournalEntry){
  const debit=entry.lines.reduce((s,l)=>s+l.debit,0);
  const credit=entry.lines.reduce((s,l)=>s+l.credit,0);
  return {debit,credit,balanced:Math.abs(debit-credit)<0.005};
}

export function selectEffectiveRules<T>(rules: EffectiveRule<T>[], date:string){
  const d=new Date(date).getTime();
  return rules.filter(rule => {
    const from=new Date(rule.effectiveFrom).getTime();
    const until=rule.effectiveUntil ? new Date(rule.effectiveUntil).getTime() : Number.POSITIVE_INFINITY;
    return rule.publicationStatus === "published" && d >= from && d <= until;
  }).sort((a,b)=>b.priority-a.priority);
}
