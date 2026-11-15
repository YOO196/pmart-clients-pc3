// 센터 고르기(handoff §1·§2-1): 고를 수 있는 센터는 토큰의 `centers` 다(로그인 응답·access token 클레임에만 있다 — sessions/current 에는 없다).
// 이름은 center-master `GET /centers` 에서 붙인다. 전체 센터를 주므로 토큰 centers 와 겹치는 것만 쓴다.
// 이름을 못 불러와도 센터 목록은 비지 않는다(코드로만 보이고 안내).
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';

import { request } from '@pmart/web-core';
import { useApi } from '../../app/ApiContext';
import { messages as m } from '../../shared/messages';

const PAGE_SIZE = 200; // 계약 PageSize 최댓값

export function useCenterNames() {
  const api = useApi();
  return useQuery({
    queryKey: ['centers', 'names'],
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const page = await request('GET', api.center.GET('/centers', { params: { query: { type: 'MFC', size: PAGE_SIZE } } }));
      return new Map((page.items ?? []).flatMap((c) => (c.centerId && c.name ? [[c.centerId, c.name] as const] : [])));
    },
  });
}

export const centerLabel = (id: string, names: ReadonlyMap<string, string> | undefined) => {
  const name = names?.get(id);
  return name ? `${name} (${id})` : id;
};

/** 센터가 둘 이상일 때만 보인다. 바꾸면 같은 메뉴의 다른 센터로 간다. */
export function CenterSwitcher({ centers, current, segment }: { readonly centers: readonly string[]; readonly current: string; readonly segment: string }) {
  const names = useCenterNames();
  const navigate = useNavigate();
  if (centers.length < 2) {
    return (
      <div className="text-sm">
        <span className="opacity-70">{m.center.label}</span> <strong>{centerLabel(current, names.data)}</strong>
        {names.isError && <p className="text-warning text-xs">{m.center.namesFailed}</p>}
      </div>
    );
  }
  return (
    <label className="flex items-center gap-2 text-sm">
      <span className="opacity-70">{m.center.choose}</span>
      <select
        className="select select-sm w-auto"
        value={current}
        onChange={(e) => void navigate(`/c/${encodeURIComponent(e.target.value)}/${segment}`)}
      >
        {centers.map((c) => (
          <option key={c} value={c}>
            {centerLabel(c, names.data)}
          </option>
        ))}
      </select>
      {names.isError && <span className="text-warning text-xs">{m.center.namesFailed}</span>}
    </label>
  );
}
