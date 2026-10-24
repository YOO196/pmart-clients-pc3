// 연동 실패 분류. pmart_core(Dart) failure.dart 와 같은 규칙이다.
//
// 핵심: 변경 요청의 타임아웃·연결 끊김·5xx·UNKNOWN_RESULT 는 UnknownResultFailure.
// "실패"로 확정하지 않고 짝 조회(resolveResult)로 해소한다.

export const ProblemCode = {
  validationFailed: 'VALIDATION_FAILED',
  forbidden: 'FORBIDDEN',
  notFound: 'NOT_FOUND',
  invalidState: 'INVALID_STATE',
  versionConflict: 'VERSION_CONFLICT',
  idempotencyConflict: 'IDEMPOTENCY_CONFLICT',
  configRequired: 'CONFIG_REQUIRED',
  dependencyUnavailable: 'DEPENDENCY_UNAVAILABLE',
  unknownResult: 'UNKNOWN_RESULT',
  rateLimited: 'RATE_LIMITED',
  unknown: 'CLIENT_UNKNOWN_PROBLEM',
} as const;

/** RFC 9457 Problem + PMart 확장 (`_common.yaml` ErrorResponse). 분기는 code 로만 한다. */
export interface Problem {
  readonly status: number;
  readonly code: string;
  readonly type: string;
  readonly title?: string;
  readonly detail?: string;
  readonly traceId?: string;
  readonly requestId?: string;
  readonly retryable: boolean;
  readonly details: ReadonlyArray<{ readonly field?: string; readonly reason?: string }>;
  readonly raw: Readonly<Record<string, unknown>>;
}

export class PmartFailure extends Error {
  constructor(
    message: string,
    readonly requestId?: string,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ProblemFailure extends PmartFailure {
  constructor(
    readonly problem: Problem,
    requestId?: string,
  ) {
    super(`${problem.status} ${problem.code}`, requestId ?? problem.requestId);
  }
}

export class UnknownResultFailure extends PmartFailure {
  constructor(
    readonly origin?: unknown,
    requestId?: string,
  ) {
    super('UNKNOWN_RESULT', requestId);
  }
}

export class NetworkFailure extends PmartFailure {
  constructor(
    readonly origin?: unknown,
    requestId?: string,
  ) {
    super('NETWORK', requestId);
  }
}

/** 2xx 인데 계약과 다르다. 빈 값·0으로 메우지 않고 오류로 그린다. */
export class ContractViolationFailure extends PmartFailure {
  constructor(reason: string, requestId?: string) {
    super(`CONTRACT_VIOLATION: ${reason}`, requestId);
  }
}

export class UnexpectedResponseFailure extends PmartFailure {
  constructor(
    readonly httpStatus: number,
    requestId?: string,
  ) {
    super(`UNEXPECTED_RESPONSE ${httpStatus}`, requestId);
  }
}

export class SessionExpiredFailure extends PmartFailure {}

export function isMutation(method: string): boolean {
  return !['GET', 'HEAD', 'OPTIONS'].includes(method.toUpperCase());
}

export function parseProblem(body: unknown, httpStatus: number): Problem | undefined {
  if (typeof body !== 'object' || body === null) return undefined;
  const o = body as Record<string, unknown>;
  if (typeof o['code'] !== 'string' && typeof o['type'] !== 'string') return undefined;
  const details = Array.isArray(o['details'])
    ? (o['details'] as unknown[]).flatMap((d) => {
        if (typeof d !== 'object' || d === null) return [];
        const r = d as Record<string, unknown>;
        return [
          {
            ...(typeof r['field'] === 'string' ? { field: r['field'] } : {}),
            ...(typeof r['reason'] === 'string' ? { reason: r['reason'] } : {}),
          },
        ];
      })
    : [];
  return {
    status: typeof o['status'] === 'number' ? o['status'] : httpStatus,
    code: typeof o['code'] === 'string' ? o['code'] : ProblemCode.unknown,
    type: typeof o['type'] === 'string' ? o['type'] : 'about:blank',
    ...(typeof o['title'] === 'string' ? { title: o['title'] } : {}),
    ...(typeof o['detail'] === 'string' ? { detail: o['detail'] } : {}),
    ...(typeof o['traceId'] === 'string' ? { traceId: o['traceId'] } : {}),
    ...(typeof o['requestId'] === 'string' ? { requestId: o['requestId'] } : {}),
    retryable: o['retryable'] === true,
    details,
    raw: o,
  };
}

/**
 * 오류 응답 → 실패. [body] 는 이미 읽은 본문이다(openapi-fetch 가 읽어 `error` 로 준다.
 * Response 본문은 한 번만 읽을 수 있어서 여기서 다시 읽지 않는다).
 */
export function failureFromResponse(res: Response, body: unknown, method: string): PmartFailure {
  const requestId = res.headers.get('x-request-id') ?? undefined;
  const contentType = res.headers.get('content-type') ?? '';
  const problem = contentType.includes('json') ? parseProblem(body, res.status) : undefined;
  const mutation = isMutation(method);
  if (problem) {
    const unknown =
      problem.code === ProblemCode.unknownResult || problem.code === ProblemCode.dependencyUnavailable;
    return mutation && unknown
      ? new UnknownResultFailure(problem, requestId ?? problem.requestId)
      : new ProblemFailure(problem, requestId);
  }
  if (mutation && res.status >= 500) return new UnknownResultFailure(res.status, requestId);
  return new UnexpectedResponseFailure(res.status, requestId);
}

/** fetch 가 응답 없이 실패(타임아웃·연결 오류). 변경 요청이면 반영 여부를 모른다. */
export function failureFromTransport(error: unknown, method: string): PmartFailure {
  if (error instanceof PmartFailure) return error;
  return isMutation(method) ? new UnknownResultFailure(error) : new NetworkFailure(error);
}
