// 변경 명령 헬퍼와 결과 불명 해소. pmart_core(Dart) 의 IdempotencyKey·ResultResolver 와 같은 규칙.
import { PmartFailure } from './failure';
import { randomUuid } from './uuid';

/** `_common.yaml` CommandStatus. ACCEPTED 는 접수일 뿐 성공이 아니다. */
export type CommandStatus = 'ACCEPTED' | 'APPLIED' | 'REJECTED' | 'UNKNOWN_RESULT';

export interface CommandResponse {
  readonly status: CommandStatus;
  readonly requestId: string;
  readonly resultId?: string;
  readonly version?: number;
  readonly retryable?: boolean;
  readonly nextAction?: string;
  readonly occurredAt?: string;
}

export const isFinal = (s: CommandStatus) => s === 'APPLIED' || s === 'REJECTED';

/** 사용자 행위 1회 = 키 1개. 재시도는 같은 키를 다시 쓴다. */
export class IdempotencyKey {
  static readonly maxLength = 128;

  constructor(readonly value: string) {
    if (value.length === 0 || value.length > IdempotencyKey.maxLength) {
      throw new RangeError(`Idempotency-Key 길이는 1~${IdempotencyKey.maxLength}`);
    }
  }

  static generate(): IdempotencyKey {
    return new IdempotencyKey(randomUuid());
  }
}

/** openapi-fetch 호출 옵션에 펼쳐 넣는다: `client.POST(path, { ...command(key, version), body })` */
export function command(key: IdempotencyKey, expectedVersion?: number): { headers: Record<string, string> } {
  return {
    headers: {
      'Idempotency-Key': key.value,
      ...(expectedVersion === undefined ? {} : { 'X-Expected-Version': String(expectedVersion) }),
    },
  };
}

/** `_common.yaml` IdempotencyKey·SourceSystem·ExpectedVersion 헤더 파라미터. 값 확정은 BR-08. */
export const SOURCE_SYSTEM = 'backoffice-web';

interface CommandHeader {
  readonly 'Idempotency-Key': string;
  readonly 'X-Source-System': string;
  readonly 'X-Expected-Version'?: number;
}

/**
 * openapi-fetch 호출용. 계약이 헤더를 필수 파라미터로 두므로 params.header 로 넣는다.
 *   client.POST(path, { ...commandParams(key, { path: { id }, version }), body })
 */
export function commandParams<P extends object>(
  key: IdempotencyKey,
  options: { readonly path: P; readonly version?: number | undefined },
): { params: { header: CommandHeader; path: P } };
export function commandParams(
  key: IdempotencyKey,
  options?: { readonly version?: number | undefined },
): { params: { header: CommandHeader } };
export function commandParams(
  key: IdempotencyKey,
  { path, version }: { readonly path?: object; readonly version?: number | undefined } = {},
): { params: { header: CommandHeader; path?: object } } {
  return {
    params: {
      header: {
        'Idempotency-Key': key.value,
        'X-Source-System': SOURCE_SYSTEM,
        ...(version === undefined ? {} : { 'X-Expected-Version': version }),
      },
      ...(path ? { path } : {}),
    },
  };
}

export type Resolution =
  | { readonly kind: 'resolved'; readonly response: CommandResponse }
  | { readonly kind: 'unknown'; readonly last?: CommandResponse; readonly lastFailure?: PmartFailure };

/**
 * 짝 조회(`GET …/{requestId}`)로 결과 불명을 해소한다. 화면이 열려 있는 동안만 짧게 폴링한다.
 * 끝까지 모르면 'unknown' — 실패로 확정하지 않고 같은 행위를 막는다.
 */
export async function resolveResult(
  query: () => Promise<CommandResponse>,
  { intervalMs = 2000, maxAttempts = 5, sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms)) } = {},
): Promise<Resolution> {
  let last: CommandResponse | undefined;
  let lastFailure: PmartFailure | undefined;
  for (let i = 0; i < maxAttempts; i++) {
    if (i > 0) await sleep(intervalMs);
    try {
      const response = await query();
      if (isFinal(response.status)) return { kind: 'resolved', response };
      last = response;
    } catch (e) {
      if (!(e instanceof PmartFailure)) throw e;
      lastFailure = e;
    }
  }
  return {
    kind: 'unknown',
    ...(last ? { last } : {}),
    ...(lastFailure ? { lastFailure } : {}),
  };
}
