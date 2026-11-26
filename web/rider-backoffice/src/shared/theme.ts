// 밝은/어두운 테마 — 다섯 백오피스(backoffice·hr·mfc·rider·cdc)가 같은 값을 쓴다(사용자 2026-11-26 "다크-라이트 동기화").
// 고른 값은 @pmart/web-core 의 쿠키 하나(pmart_theme — 포트가 달라도 같은 호스트면 공유), 고른 적이 없으면 기기 설정.
// 다른 앱에서 바꾸면 이 탭으로 돌아올 때 따라 바뀐다. 시작할 때(main.tsx) 그리기 전에 한 번 붙여 깜빡임을 막는다.
// 테마는 보는 사람 한 명의 편의일 뿐 — 토큰·개인정보는 두지 않는다(BR-03).
import { useEffect, useState } from 'react';
import { applyTheme, readSharedTheme, watchSharedTheme, writeSharedTheme, type Theme } from '@pmart/web-core';

export type { Theme };
export { applyTheme };

export function readTheme(): Theme {
  return readSharedTheme();
}

export function useTheme(): readonly [Theme, () => void] {
  const [theme, setTheme] = useState<Theme>(readTheme);
  useEffect(
    () =>
      watchSharedTheme((t) => {
        applyTheme(t);
        setTheme(t);
      }),
    [],
  );
  const toggle = () => {
    const next: Theme = theme === 'pmart' ? 'pmart-dark' : 'pmart';
    applyTheme(next);
    writeSharedTheme(next);
    setTheme(next);
  };
  return [theme, toggle];
}
