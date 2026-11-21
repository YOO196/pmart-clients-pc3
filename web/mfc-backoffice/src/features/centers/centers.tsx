// 센터 고르기(handoff §1·§2-1): 고를 수 있는 센터는 세션 응답(`GET /employee-auth/sessions/current`, 0.6.0)의 `centers` 다(토큰을 풀지 않는다 — 백엔드 요청 2026-11-15 session-roles-centers).
// 이름은 같은 응답의 `centerDetails`(0.9.0, 백엔드 알림 web-common/2026-11-16-notice-session-center-names) — 서버가 이름을 못 읽은 센터는 코드로 보이고 안내한다.
// 이름은 표시용이다. 주소·API 호출은 코드(centers)로.
import { useNavigate } from 'react-router';

import { centerDisplayName } from '@pmart/web-core';
import { useSession } from '../../app/SessionContext';
import { messages as m } from '../../shared/messages';

/** 센터가 둘 이상일 때만 고르기가 보인다. 바꾸면 같은 메뉴의 다른 센터로 간다. */
export function CenterSwitcher({ centers, current, segment }: { readonly centers: readonly string[]; readonly current: string; readonly segment: string }) {
  const { session } = useSession();
  const navigate = useNavigate();
  const missingNames = centers.some((c) => !session?.centerNames?.has(c));
  if (centers.length < 2) {
    return (
      <div className="min-w-0 text-sm">
        {/* 좁은 화면(2026-11-21): "센터" 글자는 빼고 이름은 한 줄로 줄인다 */}
        <span className="hidden opacity-70 sm:inline">{m.center.label} </span>
        <strong className="inline-block max-w-[6rem] truncate align-bottom sm:max-w-none" title={centerDisplayName(session, current)}>
          {centerDisplayName(session, current)}
        </strong>
        {missingNames && <p className="text-warning text-xs">{m.center.namesFailed}</p>}
      </div>
    );
  }
  return (
    <div className="flex items-center gap-2 text-sm">
      <label className="flex items-center gap-2">
        <span className="hidden opacity-70 sm:inline">{m.center.choose}</span>
        <select
          aria-label={m.center.choose}
          className="select select-sm w-auto max-w-[7rem] sm:max-w-none"
          value={current}
          onChange={(e) => void navigate(`/c/${encodeURIComponent(e.target.value)}/${segment}`)}
        >
          {centers.map((c) => (
            <option key={c} value={c}>
              {centerDisplayName(session, c)}
            </option>
          ))}
        </select>
      </label>
      {missingNames && <span className="text-warning text-xs">{m.center.namesFailed}</span>}
    </div>
  );
}
