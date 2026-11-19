// 라이더 화면 표기 목(rider 0.18.0 `GET /riders/display-names?riderIds=` — RS-MFC, 센터 직원 허용).
// 쉼표 50개까지, 비우면 400. 없는 ID 는 빠진다. RD-39 는 탈퇴(이름 지워짐 → 번호만).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { operator, problem, unauthorized } from './support';

const names: Readonly<Record<string, { readonly riderNumber: string; readonly nameMasked: string | null }>> = {
  'RD-1': { riderNumber: '482913', nameMasked: '김*수' },
  'RD-2': { riderNumber: '503217', nameMasked: '박*민' },
  'RD-7': { riderNumber: '377102', nameMasked: '이*진' },
  'RD-8': { riderNumber: '611045', nameMasked: '최*훈' },
  'RD-9': { riderNumber: '290386', nameMasked: '정*아' },
  'RD-31': { riderNumber: '715520', nameMasked: '한*우' },
  'RD-32': { riderNumber: '826631', nameMasked: '오*림' },
  'RD-39': { riderNumber: '918742', nameMasked: null },
  'RD-41': { riderNumber: '104853', nameMasked: '윤*서' },
};

export const riderHandlers = [
  http.get(`${API_BASE}/riders/display-names`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const ids = (new URL(request.url).searchParams.get('riderIds') ?? '').split(',').filter((s) => s !== '');
    if (ids.length === 0 || ids.length > 50) return problem(400, 'VALIDATION_FAILED', [{ field: 'riderIds', reason: '1~50개' }]);
    return HttpResponse.json({ items: ids.flatMap((id) => (names[id] ? [{ riderId: id, ...names[id] }] : [])) });
  }),
];
