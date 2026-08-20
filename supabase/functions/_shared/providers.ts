export type RuntimeMaterial={provider_key:string;environment:string;config:Record<string,unknown>;secrets:Record<string,string>};
export type OutboundMessage={id:string;organisation_id:string;project_id?:string|null;channel:'email'|'whatsapp'|'sms';provider_key:string;environment:'sandbox'|'production';idempotency_key:string;recipient:string;purpose:string;template_key?:string|null;subject?:string|null;payload?:Record<string,unknown>;variables?:Record<string,unknown>};

const enc=new TextEncoder();
export async function sha256Hex(value:string|Uint8Array){const bytes=typeof value==='string'?enc.encode(value):value;const hash=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes));return [...hash].map(v=>v.toString(16).padStart(2,'0')).join('');}
export async function hmacSha256Hex(secret:string,message:string){const key=await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);const sig=new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(message)));return [...sig].map(v=>v.toString(16).padStart(2,'0')).join('');}
export function timingSafeTextEqual(a:string,b:string){if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}

function stringValue(v:unknown,fallback=''){return typeof v==='string'?v:fallback;}
function arrayValue(v:unknown){return Array.isArray(v)?v.map(x=>String(x)):[];}

export async function sendResend(message:OutboundMessage,material:RuntimeMaterial){
  const apiKey=material.secrets.api_key;if(!apiKey)throw new Error('resend_api_key_missing');
  const from=stringValue(material.config.from_email);if(!from)throw new Error('resend_from_email_missing');
  const payload=message.payload||{};const subject=message.subject||stringValue(payload.subject);if(!subject)throw new Error('email_subject_required');
  const body:Record<string,unknown>={from,to:[message.recipient],subject};
  const html=stringValue(payload.html);const text=stringValue(payload.text)||stringValue(payload.body);if(html)body.html=html;if(text)body.text=text;if(!html&&!text)throw new Error('email_body_required');
  const replyTo=stringValue(material.config.reply_to);if(replyTo)body.reply_to=replyTo;
  const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':message.idempotency_key},body:JSON.stringify(body)});
  const data=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok)throw new Error(`resend_${response.status}:${stringValue(data.message,'request_failed')}`);
  return {providerMessageId:stringValue(data.id),status:'accepted' as const,raw:data};
}

export async function sendAiSensy(message:OutboundMessage,material:RuntimeMaterial){
  const apiKey=material.secrets.api_key;if(!apiKey)throw new Error('aisensy_api_key_missing');
  const campaignName=message.template_key||stringValue(material.config.default_campaign);if(!campaignName)throw new Error('aisensy_campaign_required');
  const payload=message.payload||{};const userName=stringValue(payload.user_name,'Concept Spaces Client');
  const body:Record<string,unknown>={apiKey,campaignName,destination:message.recipient,userName,source:stringValue(payload.source,'Concept Spaces'),templateParams:arrayValue(payload.template_params),tags:arrayValue(payload.tags),attributes:typeof payload.attributes==='object'&&payload.attributes?payload.attributes:{}};
  if(payload.media&&typeof payload.media==='object')body.media=payload.media;
  if(Array.isArray(payload.buttons))body.buttons=payload.buttons;
  const response=await fetch('https://backend.aisensy.com/campaign/t1/api/v2',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const data=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok)throw new Error(`aisensy_${response.status}:${stringValue(data.message,'request_failed')}`);
  return {providerMessageId:stringValue(data.messageId)||stringValue(data.id),status:'accepted' as const,raw:data};
}

export async function sendFast2Sms(message:OutboundMessage,material:RuntimeMaterial){
  const apiKey=material.secrets.api_key;if(!apiKey)throw new Error('fast2sms_api_key_missing');
  const config=material.config;const payload=message.payload||{};const route=stringValue(config.route,'dlt');const senderId=stringValue(config.sender_id);if(!senderId)throw new Error('fast2sms_sender_id_missing');
  const params=new URLSearchParams({route,sender_id:senderId,numbers:message.recipient,sms_details:'1'});
  if(route==='dlt'){const messageId=message.template_key||stringValue(config.message_id);if(!messageId)throw new Error('fast2sms_dlt_message_id_required');params.set('message',messageId);const values=stringValue(payload.variables_values);if(values)params.set('variables_values',values);}
  else if(route==='dlt_manual'){const body=stringValue(payload.body);if(!body)throw new Error('fast2sms_message_body_required');params.set('message',body);const templateId=message.template_key||stringValue(config.template_id);if(templateId)params.set('template_id',templateId);const entityId=stringValue(config.entity_id);if(entityId)params.set('entity_id',entityId);}
  else {const body=stringValue(payload.body);if(!body)throw new Error('fast2sms_message_body_required');params.set('message',body);}
  const response=await fetch(`https://www.fast2sms.com/dev/bulkV2?${params.toString()}`,{headers:{Authorization:apiKey,accept:'application/json'}});
  const data=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok||data.return===false)throw new Error(`fast2sms_${response.status}:${stringValue(data.message,'request_failed')}`);
  const requestId=Array.isArray(data.request_id)?String(data.request_id[0]||''):stringValue(data.request_id);
  return {providerMessageId:requestId,status:'accepted' as const,raw:data};
}

export async function createRazorpayOrder(material:RuntimeMaterial,input:{amount_minor:number;currency:string;receipt:string;invoice_id:string;idempotency_key:string}){
  const keyId=material.secrets.key_id;const keySecret=material.secrets.key_secret;if(!keyId||!keySecret)throw new Error('razorpay_credentials_missing');
  const auth=btoa(`${keyId}:${keySecret}`);const response=await fetch('https://api.razorpay.com/v1/orders',{method:'POST',headers:{Authorization:`Basic ${auth}`,'Content-Type':'application/json'},body:JSON.stringify({amount:input.amount_minor,currency:input.currency,receipt:input.receipt,notes:{invoice_id:input.invoice_id,idempotency_key:input.idempotency_key}})});
  const data=await response.json().catch(()=>({})) as Record<string,unknown>;if(!response.ok)throw new Error(`razorpay_${response.status}:${stringValue((data.error as Record<string,unknown>|undefined)?.description,'request_failed')}`);
  return {orderId:stringValue(data.id),keyId,raw:data};
}

export async function verifyRazorpayWebhook(raw:string,signature:string,secret:string){const expected=await hmacSha256Hex(secret,raw);return timingSafeTextEqual(expected,signature);}

function decodeBase64(input:string){const clean=input.replace(/^whsec_/,'').replace(/-/g,'+').replace(/_/g,'/');const padded=clean+'='.repeat((4-clean.length%4)%4);const binary=atob(padded);return Uint8Array.from(binary,c=>c.charCodeAt(0));}
export async function verifyResendWebhook(raw:string,headers:Headers,secret:string,toleranceSeconds=300){
  const id=headers.get('svix-id')||'';const timestamp=headers.get('svix-timestamp')||'';const signature=headers.get('svix-signature')||'';if(!id||!timestamp||!signature||!secret)return false;
  const ts=Number(timestamp);if(!Number.isFinite(ts)||Math.abs(Math.floor(Date.now()/1000)-ts)>toleranceSeconds)return false;
  const keyBytes=decodeBase64(secret);const key=await crypto.subtle.importKey('raw',keyBytes,{name:'HMAC',hash:'SHA-256'},false,['sign']);const signed=new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(`${id}.${timestamp}.${raw}`)));let binary='';for(const b of signed)binary+=String.fromCharCode(b);const expected=btoa(binary);
  return signature.split(' ').some(part=>{const [version,value]=part.split(',');return version==='v1'&&typeof value==='string'&&timingSafeTextEqual(value,expected);});
}
