// 새로고침 뒤 세션 복원용 보관. access token 은 절대 저장하지 않는다.
// 이 탭의 sessionStorage 에만 둔다: 탭을 닫으면 사라지고 다른 탭과 공유되지 않는다. localStorage 는 쓰지 않는다(규칙).
// - refresh 쿠키 세션(COOKIE — ADR-0059): 세션 ID + 기기 ID 만. refresh token 은 HttpOnly 쿠키라 여기에 없다.
// - 본문 세션(BODY — 목·시험): refresh token + 기기 ID.
import type { RestorableSession, TokenStore } from './tokens';

export type SavedSession = RestorableSession;

export interface SessionPersistence {
  readonly loadSavedSession: () => SavedSession | null;
  /** 토큰이 바뀔 때마다 호출한다. 되살릴 세션이 있으면 저장, 없으면(로그아웃·세션 종료) 지운다. */
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
        if (typeof v.deviceId !== 'string') return null;
        if (typeof v.refreshToken === 'string') return { refreshToken: v.refreshToken, deviceId: v.deviceId };
        if (typeof v.sessionId === 'string') return { sessionId: v.sessionId, deviceId: v.deviceId };
        return null;
      } catch {
        return null;
      }
    },
    syncSavedSession(store) {
      const s = storage();
      if (!s) return;
      const { refreshToken, cookieSessionId, deviceId } = store;
      if (refreshToken) s.setItem(key, JSON.stringify({ refreshToken, deviceId } satisfies SavedSession));
      else if (cookieSessionId) s.setItem(key, JSON.stringify({ sessionId: cookieSessionId, deviceId } satisfies SavedSession));
      else s.removeItem(key);
    },
    clearSavedSession() {
      storage()?.removeItem(key);
    },
  };
}
