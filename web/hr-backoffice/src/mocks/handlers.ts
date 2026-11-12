import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { authHandlers } from './authHandlers';
import { hrHandlers } from './hrHandlers';
import { operator, unauthorized } from './support';

/** 게이트웨이 공개 경로(계약 security: []) */
const PUBLIC = [`${API_BASE}/employee-auth/tokens`, `${API_BASE}/employee-auth/tokens/refresh`];

/** 게이트웨이처럼: 공개 경로가 아니면 유효한 access token 이 있어야 한다(없거나 만료·폐기 → 401). */
const gateway = http.all(`${API_BASE}/*`, ({ request }) => {
  const url = request.url.split('?')[0] ?? '';
  if (PUBLIC.includes(url)) return undefined;
  return operator(request) ? undefined : unauthorized();
});

/** center-master `GET /centers`(계약 Center 의 일부 필드). 소속·요청 권한의 센터 고르기에 쓴다 */
export const centerList = {
  items: [
    { centerId: 'CDC01', type: 'CDC', name: '수도권 CDC', state: 'ACTIVE' },
    { centerId: 'MFC-BSN-01', type: 'MFC', name: '부산진구 MFC', state: 'ACTIVE' },
    { centerId: 'MFC-SEL-01', type: 'MFC', name: '송파 MFC', state: 'PLANNED' },
  ],
  page: { nextCursor: null, size: 200 },
};

export const handlers = [gateway, http.get(`${API_BASE}/centers`, () => HttpResponse.json(centerList)), ...authHandlers, ...hrHandlers];
