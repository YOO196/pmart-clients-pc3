// 토큰은 메모리에만 둔다(localStorage 금지). 새로고침하면 다시 로그인한다.
// refresh token 을 HttpOnly 쿠키로 옮길지는 BR-03 결정 대기.
export class TokenStore {
  accessToken: string | null = null;

  clear(): void {
    this.accessToken = null;
  }
}
