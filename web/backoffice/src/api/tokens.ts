// 토큰은 메모리에만 둔다(localStorage 금지, BR-03). 새로고침하면 다시 로그인한다.
// refresh token 은 한 번만 쓴다(ADR-0018 회전): 갱신 응답의 새 값으로 바로 바꾼다.
// X-Device-Id 도 이 탭의 메모리에 둔다. 갱신 때 로그인 때와 같은 값을 보내야 하고, refresh 가 메모리에만 있으니 탭 단위로 충분하다.

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
  /** 이 탭의 기기 ID(로그인·갱신에 같은 값) */
  readonly deviceId: string = crypto.randomUUID();

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
