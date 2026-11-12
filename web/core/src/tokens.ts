// access token 은 메모리에만 둔다(localStorage 금지, BR-03). refresh token 과 기기 ID 는 새로고침 복원을 위해
// 이 탭의 sessionStorage 에만 둔다(`sessionPersistence.ts`, 탭을 닫으면 사라진다) — BR-03(쿠키) 확정 전까지의 방식.
// refresh token 은 한 번만 쓴다(ADR-0018 회전): 갱신 응답의 새 값으로 바로 바꾼다.
// X-Device-Id 는 갱신 때 로그인 때와 같은 값을 보내야 하므로 refresh 와 함께 복원한다.

import { randomUuid } from './uuid';

export interface TokenPairLike {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly accessTokenExpiresAt?: string;
}

type Listener = (accessToken: string | null) => void;

export class TokenStore {
  private access: string | null = null;
  private refresh: string | null = null;
  private listeners = new Set<Listener>();
  private device: string = randomUuid();

  /** 이 탭의 기기 ID(로그인·갱신에 같은 값) */
  get deviceId(): string {
    return this.device;
  }

  /** 새로고침 복원: 저장해 둔 refresh token 과 기기 ID 를 되살린다(access 는 갱신으로 받는다). 알리지 않는다. */
  restore(refreshToken: string, deviceId: string): void {
    this.refresh = refreshToken;
    this.device = deviceId;
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
    if (value === null) this.refresh = null;
    this.emit();
  }

  get refreshToken(): string | null {
    return this.refresh;
  }

  setPair(pair: TokenPairLike): void {
    this.access = pair.accessToken;
    this.refresh = pair.refreshToken;
    this.emit();
  }

  clear(): void {
    if (this.access === null && this.refresh === null) return;
    this.access = null;
    this.refresh = null;
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
