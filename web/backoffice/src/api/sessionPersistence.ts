// 새로고침 뒤 세션 복원용 보관(BR-03 확정 전 임시). access token 은 절대 저장하지 않는다.
// refresh token + 기기 ID 만 이 탭의 sessionStorage 에 둔다: 탭을 닫으면 사라지고 다른 탭과 공유되지 않는다.
// localStorage 는 쓰지 않는다(규칙). 쿠키 방식이 정해지면 이 파일을 지운다.
import type { TokenStore } from './tokens';

export const SESSION_STORAGE_KEY = 'pmart.backoffice.session';
const KEY = SESSION_STORAGE_KEY;

interface Saved {
  readonly refreshToken: string;
  readonly deviceId: string;
}

function storage(): Storage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

export function loadSavedSession(): Saved | null {
  const raw = storage()?.getItem(KEY);
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Partial<Saved>;
    return typeof v.refreshToken === 'string' && typeof v.deviceId === 'string' ? { refreshToken: v.refreshToken, deviceId: v.deviceId } : null;
  } catch {
    return null;
  }
}

/** 토큰이 바뀔 때마다 호출한다. refresh 가 있으면 저장, 없으면(로그아웃·세션 종료) 지운다. */
export function syncSavedSession(store: TokenStore): void {
  const s = storage();
  if (!s) return;
  const refreshToken = store.refreshToken;
  if (refreshToken) s.setItem(KEY, JSON.stringify({ refreshToken, deviceId: store.deviceId } satisfies Saved));
  else s.removeItem(KEY);
}

export function clearSavedSession(): void {
  storage()?.removeItem(KEY);
}
