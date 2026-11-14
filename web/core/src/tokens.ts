// access token 은 메모리에만 둔다(localStorage 금지, BR-03).
// refresh token 은 서버가 정한 방식(TokenPair.refreshTransport — employee-auth-service 0.3.0, ADR-0059)으로 오간다.
// - COOKIE(웹 백오피스): HttpOnly 쿠키라 화면 코드는 값을 볼 수 없다. 여기에는 세션 ID 만 둔다(갱신 주소·CSRF 쿠키 이름에 쓴다).
// - BODY(목·시험·다른 앱): 본문으로 오간다. 한 번만 쓴다(ADR-0018 회전): 갱신 응답의 새 값으로 바로 바꾼다.
// 새로고침 복원용으로 이 탭의 sessionStorage 에 두는 것은 `sessionPersistence.ts`(탭을 닫으면 사라진다).
// X-Device-Id 는 갱신 때 로그인 때와 같은 값을 보내야 하므로 함께 복원한다.

import { randomUuid } from './uuid';

export type RefreshTransport = 'BODY' | 'COOKIE';

export interface TokenPairLike {
  readonly accessToken: string;
  /** BODY 일 때만. COOKIE 면 없다(null) */
  readonly refreshToken?: string | null;
  /** 없으면 본문에 refresh token 이 있을 때 BODY 로 본다(0.3.0 전 응답·시험) */
  readonly refreshTransport?: RefreshTransport;
  readonly sessionId?: string;
  readonly accessTokenExpiresAt?: string;
}

/** 새로고침 복원에 쓰는 값 — COOKIE 면 sessionId, BODY 면 refreshToken */
export interface RestorableSession {
  readonly deviceId: string;
  readonly sessionId?: string;
  readonly refreshToken?: string;
}

type Listener = (accessToken: string | null) => void;

export class TokenStore {
  private access: string | null = null;
  private refresh: string | null = null;
  /** refresh 쿠키 세션의 ID(COOKIE 일 때만) */
  private cookieSession: string | null = null;
  private listeners = new Set<Listener>();
  private device: string = randomUuid();

  /** 이 탭의 기기 ID(로그인·갱신에 같은 값) */
  get deviceId(): string {
    return this.device;
  }

  /** 새로고침 복원: 저장해 둔 세션 ID(쿠키) 또는 refresh token(본문)과 기기 ID 를 되살린다(access 는 갱신으로 받는다). 알리지 않는다. */
  restore(saved: RestorableSession): void {
    this.refresh = saved.refreshToken ?? null;
    this.cookieSession = saved.refreshToken ? null : (saved.sessionId ?? null);
    this.device = saved.deviceId;
  }

  /** 로그인 복귀(employee-auth): 로그인을 시작할 때의 기기 ID 로 되돌린다(티켓 교환·갱신이 그 값에 묶인다). */
  useDevice(deviceId: string): void {
    this.device = deviceId;
  }

  get accessToken(): string | null {
    return this.access;
  }

  /** 테스트·목 세션용. refresh 없이 access 만 둔다. */
  set accessToken(value: string | null) {
    this.access = value;
    if (value === null) {
      this.refresh = null;
      this.cookieSession = null;
    }
    this.emit();
  }

  /** 본문으로 오가는 refresh token(BODY). COOKIE 면 늘 null */
  get refreshToken(): string | null {
    return this.refresh;
  }

  /** refresh 쿠키 세션의 ID(COOKIE). BODY 면 null */
  get cookieSessionId(): string | null {
    return this.cookieSession;
  }

  setPair(pair: TokenPairLike): void {
    this.access = pair.accessToken;
    if (pair.refreshTransport === 'COOKIE') {
      this.refresh = null;
      this.cookieSession = pair.sessionId ?? null;
    } else {
      this.refresh = pair.refreshToken ?? null;
      this.cookieSession = null;
    }
    this.emit();
  }

  clear(): void {
    if (this.access === null && this.refresh === null && this.cookieSession === null) return;
    this.access = null;
    this.refresh = null;
    this.cookieSession = null;
    this.emit();
  }

  /** 토큰이 바뀌면(로그인·갱신·만료) 알린다. 해제 함수를 돌려준다. */
  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit() {
    for (const l of this.listeners) l(this.access);
  }
}
