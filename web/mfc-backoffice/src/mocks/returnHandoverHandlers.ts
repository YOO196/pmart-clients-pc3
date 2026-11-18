// 반납 인증번호 목(delivery-execution 0.28.0): `GET /return-handovers?mfcId=`(그 센터 직원 — mfcId 필수), `POST …/{deliveryId}/code-reissues`
// (새 번호·틀린 횟수 0·잠김 풀림, 반납을 기다리는 배송이 아니면 409, 같은 키 = 같은 결과). 데이터는 db.returnHandovers(번호는 목 값).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/delivery-execution';
import { db, type MockReturnHandover } from './db';
import { idempotent, operator, problem, unauthorized } from './support';

type ReturnHandover = components['schemas']['ReturnHandover'];

const view = (h: MockReturnHandover): ReturnHandover => {
  const { mfcId, ...rest } = h;
  void mfcId;
  return rest;
};

export const returnHandoverHandlers = [
  http.get(`${API_BASE}/return-handovers`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const mfcId = new URL(request.url).searchParams.get('mfcId');
    if (!mfcId || !who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    return HttpResponse.json({ items: db.returnHandovers.filter((h) => h.mfcId === mfcId).map(view) });
  }),
  http.post(`${API_BASE}/return-handovers/:deliveryId/code-reissues`, ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const id = String(params.deliveryId);
    const h = db.returnHandovers.find((x) => x.deliveryId === id);
    if (h && !who.centers.includes(h.mfcId)) return problem(403, 'FORBIDDEN');
    return idempotent(request, () => {
      const cur = db.returnHandovers.find((x) => x.deliveryId === id);
      if (!cur) return problem(409, 'INVALID_STATE');
      db.seq += 1;
      const next: MockReturnHandover = { ...cur, code: String(db.seq * 37).padStart(4, '0').slice(-4), failedAttempts: 0, locked: false, issuedAt: new Date().toISOString() };
      db.returnHandovers = db.returnHandovers.map((x) => (x.deliveryId === id ? next : x));
      return { status: 200, body: view(next) };
    });
  }),
];
