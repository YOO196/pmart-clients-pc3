// 그 물건이 있는 곳에서 바로 시작하기(2026-11-19 사용자 "배송 번호가 길어 사람이 기억할 수 없다 — 시스템적으로 해결할 방법").
// 배송을 보고 있는 화면(상세·미리보기·접수 건의 연결 배송)에 단추를 두고, 누르면 그 배송이 이미 채워진 입력 화면이 열린다 — 번호를 옮겨 적지 않는다.
// 단추는 그 사람 역할로 열 수 있는 메뉴만(메뉴와 같은 규칙, 판정은 서버가 다시 한다).
import { Link } from 'react-router';

import { useSession } from '../app/SessionContext';
import { visibleGroups } from '../app/nav';
import { messages } from './messages';

const m = messages.startActions;

export function DeliveryStartActions({ deliveryId, size = 'sm', noMisdelivery = false }: { readonly deliveryId: string; readonly size?: 'sm' | 'xs'; readonly noMisdelivery?: boolean }) {
  const { session } = useSession();
  const paths = new Set(visibleGroups(session?.roles ?? []).flatMap((g) => g.items.map((i) => i.to)));
  const q = `deliveryId=${encodeURIComponent(deliveryId)}`;
  const btn = `btn btn-${size}`;
  const actions = [
    !noMisdelivery && paths.has('/cases/new-misdelivery') && (
      <Link key="mis" className={btn} to={`/cases/new-misdelivery?${q}`} data-testid="start-misdelivery">
        {m.misdelivery}
      </Link>
    ),
    paths.has('/rider-complaints') && (
      <Link key="cmp" className={btn} to={`/rider-complaints/new?${q}`} data-testid="start-complaint">
        {m.complaint}
      </Link>
    ),
  ].filter(Boolean);
  if (actions.length === 0) return null;
  return (
    <span className="inline-flex flex-wrap items-center gap-1.5" role="group" aria-label={m.label}>
      {actions}
    </span>
  );
}
