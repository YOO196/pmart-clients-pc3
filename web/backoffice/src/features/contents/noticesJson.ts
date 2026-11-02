// 고시 정보 JSON 읽기. 콘텐츠 초안 폼의 "JSON 파일로 채우기"가 쓴다.
//
// 받는 모양(어느 것이든):
//  1. seed-v1 product.json  — { content: { notices: [...], name, description, storageGuide, returnGuide } }
//  2. { notices: [...] }     — 콘텐츠 초안 본문 모양(name 등 다른 필드가 있으면 함께 읽는다)
//  3. ["항목: 값", ...]       — 문자열 배열
//  4. [{ label, value }, ...] — 캡처 원본(PRODUCT_INFO) 모양 → "label: value"
//  5. { "항목": "값", ... }   — 객체 → "항목: 값"
// 계약(`ContentDraft.notices`)은 "항목: 값" 문자열 배열(항목당 500자)이라 결과도 그 모양이다.

export interface NoticesJson {
  readonly notices: readonly string[];
  /** 함께 들어 있던 콘텐츠 필드. 폼의 빈 칸만 채운다. */
  readonly fields: {
    readonly name?: string;
    readonly description?: string;
    readonly storageGuide?: string;
    readonly returnGuide?: string;
  };
}

export class NoticesJsonError extends Error {}

const MAX_NOTICE_LENGTH = 500;

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null && !Array.isArray(x);
}

function text(x: unknown): string | undefined {
  if (typeof x === 'string') return x.trim() || undefined;
  if (typeof x === 'number' || typeof x === 'boolean') return String(x);
  return undefined;
}

function noticeLine(label: string, value: unknown): string | undefined {
  const l = label.trim();
  const v = text(value);
  if (!l) return v;
  if (v === undefined) return undefined;
  return `${l}: ${v}`;
}

/** 배열 → 고시 문자열 목록. 문자열·{label,value} 섞여 있어도 된다. */
function noticesFromArray(items: readonly unknown[]): string[] {
  const out: string[] = [];
  for (const item of items) {
    if (typeof item === 'string') {
      const s = item.trim();
      if (s) out.push(s);
    } else if (isRecord(item)) {
      const label = text(item['label'] ?? item['name'] ?? item['key'] ?? item['title']);
      const line = noticeLine(label ?? '', item['value'] ?? item['content']);
      if (line) out.push(line);
    } else {
      throw new NoticesJsonError('notices 항목은 문자열이거나 {label, value} 여야 해요');
    }
  }
  return out;
}

function noticesFromObject(obj: Record<string, unknown>): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(obj)) {
    const line = noticeLine(k, v);
    if (line) out.push(line);
  }
  return out;
}

const FIELD_KEYS = ['name', 'description', 'storageGuide', 'returnGuide'] as const;

function fieldsOf(obj: Record<string, unknown>): NoticesJson['fields'] {
  const fields: { -readonly [K in keyof NoticesJson['fields']]: NoticesJson['fields'][K] } = {};
  for (const k of FIELD_KEYS) {
    const v = text(obj[k]);
    if (v !== undefined) fields[k] = v;
  }
  return fields;
}

export function parseNoticesJson(raw: string): NoticesJson {
  let data: unknown;
  try {
    data = JSON.parse(raw) as unknown;
  } catch {
    throw new NoticesJsonError('JSON 형식이 아니에요');
  }
  const result = parseValue(data);
  const tooLong = result.notices.find((n) => n.length > MAX_NOTICE_LENGTH);
  if (tooLong !== undefined) {
    throw new NoticesJsonError(`항목이 ${MAX_NOTICE_LENGTH}자를 넘어요: ${tooLong.slice(0, 20)}…`);
  }
  if (result.notices.length === 0) throw new NoticesJsonError('고시 정보 항목이 없어요');
  return result;
}

function parseValue(data: unknown): NoticesJson {
  if (Array.isArray(data)) return { notices: noticesFromArray(data), fields: {} };
  if (!isRecord(data)) throw new NoticesJsonError('객체나 배열이어야 해요');

  // seed-v1 product.json
  const content = data['content'];
  if (isRecord(content)) return parseValue(content);

  const notices = data['notices'];
  if (notices !== undefined) {
    if (Array.isArray(notices)) return { notices: noticesFromArray(notices), fields: fieldsOf(data) };
    if (isRecord(notices)) return { notices: noticesFromObject(notices), fields: fieldsOf(data) };
    throw new NoticesJsonError('notices 는 배열이거나 객체여야 해요');
  }
  // 그 밖의 객체는 통째로 "항목: 값"
  return { notices: noticesFromObject(data), fields: {} };
}
