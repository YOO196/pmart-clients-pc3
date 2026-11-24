// 목 핸들러 공통: Problem 응답, 토큰 클레임, 멱등 재생, 기대 버전.
import { HttpResponse } from 'msw';

import { parseOperatorToken, type OperatorSession } from '@pmart/web-core';
import { db } from './db';

export function problem(
  status: number,
  code: string,
  details: ReadonlyArray<{ field?: string; reason?: string }> = [],
): HttpResponse<Record<string, unknown>> {
  return HttpResponse.json(
    { type: 'about:blank', title: code, status, code, traceId: 'mock-trace', details },
    { status, headers: { 'content-type': 'application/problem+json', 'x-request-id': `mock-${status}-${code}` } },
  );
}

/** 게이트웨이처럼 access token 을 확인한다: 만료(exp)·폐기된 세션(sid)이면 null(→ 401). */
export function operator(request: Request): OperatorSession | null {
  const auth = request.headers.get('Authorization');
  const who = auth?.startsWith('Bearer ') ? parseOperatorToken(auth.slice(7)) : null;
  if (!who) return null;
  if (who.expiresAtSeconds !== undefined && who.expiresAtSeconds * 1000 <= Date.now()) return null;
  if (who.sessionId && db.sessions.get(who.sessionId)?.revoked) return null;
  return who;
}

export const unauthorized = () => new HttpResponse(null, { status: 401 });

export const keyOf = (request: Request) => request.headers.get('Idempotency-Key') ?? '';

export function expectedVersion(request: Request): number | undefined {
  const v = request.headers.get('X-Expected-Version');
  return v === null ? undefined : Number(v);
}

/** 같은 키 = 저장된 응답 재생(서버 멱등 규칙). */
export async function idempotent(
  request: Request,
  run: () => Promise<{ status: number; body: unknown } | HttpResponse<Record<string, unknown>>> | { status: number; body: unknown } | HttpResponse<Record<string, unknown>>,
) {
  const id = `${request.method} ${new URL(request.url).pathname} ${keyOf(request)}`;
  const saved = db.idempotent.get(id);
  if (saved) return HttpResponse.json(saved.body as Record<string, unknown>, { status: saved.status });
  const result = await run();
  if (result instanceof Response) return result;
  db.idempotent.set(id, result);
  return HttpResponse.json(result.body as Record<string, unknown>, { status: result.status });
}

export const hash = (value: unknown) => {
  const s = JSON.stringify(value);
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return `h${(h >>> 0).toString(16)}`;
};

/**
 * 사진 형식 — 서버처럼 파일 앞부분(매직 바이트)으로 판정(2026-11-24 사용자 "목업 서버에서는 아무 사진이나 다 올라가는데 정상임?" —
 * 목은 이름표(MIME)만 보고 받아 실서버와 달랐다). JPEG FF D8 FF · PNG 89 50 4E 47 · WEBP "RIFF"…"WEBP". 그 밖은 null.
 */
export async function imageKindOf(file: Blob): Promise<'image/jpeg' | 'image/png' | 'image/webp' | null> {
  const b = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  const ascii = (from: number, to: number) => String.fromCharCode(...b.slice(from, to));
  if (ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WEBP') return 'image/webp';
  return null;
}
