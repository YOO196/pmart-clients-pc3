// 새로고침 뒤 세션 복원용 보관(BR-03 확정 전 임시). access token 은 절대 저장하지 않는다.
// refresh token + 기기 ID 만 이 탭의 sessionStorage 에 둔다: 탭을 닫으면 사라지고 다른 탭과 공유되지 않는다.
// localStorage 는 쓰지 않는다(규칙). 쿠키 방식이 정해지면 이 파일을 지운다.
import type { TokenStore } from './tokens';

export interface SavedSession {
  readonly refreshToken: string;
  readonly deviceId: string;
}

export interface SessionPersistence {
  readonly loadSavedSession: () => SavedSession | null;
  /** 토큰이 바뀔 때마다 호출한다. refresh 가 있으면 저장, 없으면(로그아웃·세션 종료) 지운다. */
  readonly syncSavedSession: (store: TokenStore) => void;
  readonly clearSavedSession: () => void;
}

function storage(): Storage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

/** 앱마다 다른 보관 키(예: pmart.backoffice.session)로 만든다. */
export function createSessionPersistence(key: string): SessionPersistence {
  return {
    loadSavedSession() {
      const raw = storage()?.getItem(key);
      if (!raw) return null;
      try {
        const v = JSON.parse(raw) as Partial<SavedSession>;
        return typeof v.refreshToken === 'string' && typeof v.deviceId === 'string' ? { refreshToken: v.refreshToken, deviceId: v.deviceId } : null;
      } catch {
        return null;
      }
    },
    syncSavedSession(store) {
      const s = storage();
      if (!s) return;
      const refreshToken = store.refreshToken;
      if (refreshToken) s.setItem(key, JSON.stringify({ refreshToken, deviceId: store.deviceId } satisfies SavedSession));
      else s.removeItem(key);
    },
    clearSavedSession() {
      storage()?.removeItem(key);
    },
  };
}
