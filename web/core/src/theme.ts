// 백오피스 다섯 앱(backoffice·hr·mfc·rider·cdc) 공통 밝은/어두운 테마(사용자 2026-11-26 "다크-라이트 동기화").
// 고른 값은 쿠키 하나(`pmart_theme`, Path=/)에 둔다 — 쿠키는 포트가 달라도 같은 호스트면 같이 보여서
// (https://192.168.0.40:8443~8447, 개발 localhost:5173~5177) 한 앱에서 바꾸면 다른 앱도 같은 테마가 된다.
// localStorage 는 포트(오리진)마다 따로라 공유되지 않는다. 고른 적이 없으면 기기 설정(prefers-color-scheme)을 따른다.
// 테마는 보는 사람 한 명의 편의일 뿐 — 토큰·개인정보는 두지 않는다. 서버에는 보내지 않는다(백엔드 없음).

export type Theme = 'pmart' | 'pmart-dark';

export const THEME_COOKIE = 'pmart_theme';

/** 1년 — 지우지 않는 한 남는다. */
const MAX_AGE = 60 * 60 * 24 * 365;

/** 고른 테마(쿠키). 고른 적이 없거나 쿠키를 못 읽으면 null. */
export function readChosenTheme(): Theme | null {
  try {
    const hit = document.cookie
      .split(';')
      .map((c) => c.trim())
      .find((c) => c.startsWith(`${THEME_COOKIE}=`));
    const v = hit?.slice(THEME_COOKIE.length + 1);
    return v === 'pmart' || v === 'pmart-dark' ? v : null;
  } catch {
    return null;
  }
}

/** 기기 설정 — 어두운 화면이면 pmart-dark. 알 수 없으면 밝은 테마. */
export function deviceTheme(): Theme {
  try {
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'pmart-dark' : 'pmart';
  } catch {
    return 'pmart';
  }
}

/** 지금 쓸 테마: 고른 값, 없으면 기기 설정. */
export function readSharedTheme(): Theme {
  return readChosenTheme() ?? deviceTheme();
}

/** 고른 테마를 다섯 앱이 같이 보게 쿠키에 둔다. 못 쓰면 이 화면만 바뀐다. */
export function writeSharedTheme(t: Theme): void {
  try {
    const secure = window.location.protocol === 'https:' ? '; Secure' : '';
    document.cookie = `${THEME_COOKIE}=${t}; Path=/; Max-Age=${MAX_AGE}; SameSite=Lax${secure}`;
  } catch {
    /* 기억만 못 할 뿐 바꾸기는 된다 */
  }
}

/** `<html data-theme>` 에 붙인다(시작할 때 그리기 전에 한 번 — 깜빡임 방지). */
export function applyTheme(t: Theme): void {
  document.documentElement.setAttribute('data-theme', t);
}

/**
 * 다른 앱(탭)에서 바꾼 테마·기기 설정이 바뀐 것을 따라간다. 쿠키는 바뀜 알림이 없어, 이 탭으로 돌아올 때
 * (창 포커스·탭이 다시 보임) 다시 읽는다. 고른 적이 없으면 기기 설정이 바뀔 때도 따른다. 해제 함수를 돌려준다.
 */
export function watchSharedTheme(onChange: (t: Theme) => void): () => void {
  let last = readSharedTheme();
  const check = () => {
    const now = readSharedTheme();
    if (now !== last) {
      last = now;
      onChange(now);
    }
  };
  const onVisible = () => {
    if (document.visibilityState === 'visible') check();
  };
  window.addEventListener('focus', check);
  document.addEventListener('visibilitychange', onVisible);
  let media: MediaQueryList | null = null;
  try {
    media = window.matchMedia?.('(prefers-color-scheme: dark)') ?? null;
    media?.addEventListener?.('change', check);
  } catch {
    media = null;
  }
  return () => {
    window.removeEventListener('focus', check);
    document.removeEventListener('visibilitychange', onVisible);
    media?.removeEventListener?.('change', check);
  };
}
