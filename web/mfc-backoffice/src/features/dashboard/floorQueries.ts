// 센터 도면 — 칸(위치) 읽기. 칸이 수천 개라 한 쪽(최대 200)만 읽으면 숫자가 모자란다 → 거르기(온도대·상태)로 좁혀 끝까지 넘겨 읽는다.
import { request } from '@pmart/web-core';
import type { components } from '../../api/generated/mfc-location';
import type { useApi } from '../../app/ApiContext';

type Api = ReturnType<typeof useApi>;
export type Location = components['schemas']['Location'];

/** 칸 목록 끝까지(쪽 200, 안전 상한 60쪽) */
export async function fetchAllLocations(
  api: Api,
  mfcId: string,
  filter: { readonly temperatureZone?: Location['temperatureZone']; readonly state?: NonNullable<Location['state']> } = {},
): Promise<Location[]> {
  const out: Location[] = [];
  let cursor: string | undefined;
  for (let i = 0; i < 60; i++) {
    const res = await request('GET', api.location.GET('/locations', { params: { query: { mfcId, size: 200, ...filter, ...(cursor ? { cursor } : {}) } } }));
    out.push(...(res.items ?? []));
    cursor = res.page?.nextCursor ?? undefined;
    if (!cursor) break;
  }
  return out;
}
