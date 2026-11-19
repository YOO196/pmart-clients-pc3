// 처리한 뒤 알림 숫자를 바로 맞춘다(2026-11-19 사용자 "뭔가 처리했을 때 알람 수가 바로 안 사라지고 시간이 좀 걸린다").
// 원인: 메뉴 알림(['menu-alert', …])·대시보드 숫자(['dashboard', …])는 자기 키로 60초마다만 다시 읽었고,
// 처리 화면은 자기 목록 키(['approval']·['inquiries']·['bff','pending-work'] 등)만 다시 읽었다.
// 그래서 한곳에서 지켜본다 — 업무 목록 키가 "다시 읽기(invalidate)"되면 = 무엇을 처리했다는 뜻 → 알림·대시보드 숫자도 다시 읽는다.
// 서버가 ACCEPTED(접수만)로 받아 뒤에서 반영하는 명령이 있어 3초 뒤 한 번 더 읽는다. 숫자는 서버 값만 — 화면이 미리 빼지 않는다.
import { useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';

/** 처리 뒤 다시 읽히는 업무 목록 키(첫 칸) — 이것이 다시 읽히면 알림도 */
const WORK_ROOTS: ReadonlySet<string> = new Set(['approval', 'inquiries', 'cases', 'obligations', 'claims', 'cs-intakes', 'handovers', 'rider-complaints', 'help-request']);
const isWork = (key: readonly unknown[]) => (key[0] === 'bff' && key[1] === 'pending-work') || (typeof key[0] === 'string' && WORK_ROOTS.has(key[0]));
/** 알림·숫자 키 — 이것끼리는 서로 부르지 않는다(돌고 도는 다시 읽기 방지) */
const isAlert = (key: readonly unknown[]) => key[0] === 'menu-alert' || key[0] === 'dashboard' || (key[0] === 'cases' && key[1] === 'badge');

export const ALERT_RECHECK_MS = { value: 3_000 };

export function AlertsAutoRefresh() {
  const queryClient = useQueryClient();
  useEffect(() => {
    let pending = false;
    const timers = new Set<ReturnType<typeof setTimeout>>();
    const refresh = () => void queryClient.invalidateQueries({ predicate: (q) => isAlert(q.queryKey) });
    const unsubscribe = queryClient.getQueryCache().subscribe((event) => {
      if (event.type !== 'updated' || event.action.type !== 'invalidate') return;
      const key = event.query.queryKey as readonly unknown[];
      if (isAlert(key) || !isWork(key) || pending) return;
      // 한 번 처리에 여러 키가 같이 다시 읽혀도 한 번만
      pending = true;
      queueMicrotask(() => {
        pending = false;
        refresh();
        const t = setTimeout(() => {
          timers.delete(t);
          refresh();
        }, ALERT_RECHECK_MS.value);
        timers.add(t);
      });
    });
    return () => {
      unsubscribe();
      for (const t of timers) clearTimeout(t);
    };
  }, [queryClient]);
  return null;
}
