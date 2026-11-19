// 센터 직원 연락처 목(mfc-capacity 0.21.0).
// - 목록 `GET /mfcs/{mfcId}/staff-contacts`: 모든 운영자(센터 무관) — 휴대폰·이메일 중 하나라도 있는 사람만, 이름 순(이름 없으면 운영자 ID).
// - 내 것 `GET·PUT …/staff-contacts/me`: 그 센터 운영자 본인. 없으면 빈 값·version 0. PUT 은 X-Expected-Version(다르면 409),
//   형식(phone 숫자·- 만 9~11자리, email, name 50자)이 틀리면 400 VALIDATION_FAILED details field. 빈 값·null 은 지운다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db, timestamp, type MockStaffContact } from './db';
import { expectedVersion, idempotent, operator, problem, unauthorized } from './support';

const keyOf = (mfcId: string, operatorId: string) => `${mfcId}/${operatorId}`;
const blank = (v: string | null | undefined) => {
  const s = (v ?? '').trim();
  return s === '' ? null : s;
};

export const staffContactHandlers = [
  http.get(`${API_BASE}/mfcs/:mfcId/staff-contacts`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const mfcId = String(params.mfcId);
    const items = [...db.staffContacts.values()]
      .filter((c) => c.mfcId === mfcId && (c.phone || c.email))
      .sort((a, b) => (a.name ?? a.operatorId).localeCompare(b.name ?? b.operatorId));
    return HttpResponse.json({ items });
  }),

  http.get(`${API_BASE}/mfcs/:mfcId/staff-contacts/me`, ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const mfcId = String(params.mfcId);
    if (!who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    const c = db.staffContacts.get(keyOf(mfcId, who.subject));
    return HttpResponse.json(c ?? { mfcId, operatorId: who.subject, name: null, phone: null, email: null, version: 0, updatedAt: null });
  }),

  http.put(`${API_BASE}/mfcs/:mfcId/staff-contacts/me`, async ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const mfcId = String(params.mfcId);
    if (!who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { name?: string | null; phone?: string | null; email?: string | null };
    const name = blank(body.name);
    const phone = blank(body.phone);
    const email = blank(body.email);
    const bad: Array<{ field: string; reason: string }> = [];
    if (name && name.length > 50) bad.push({ field: 'name', reason: 'TOO_LONG' });
    if (phone && !(/^[\d-]+$/.test(phone) && /^\d{9,11}$/.test(phone.replace(/-/g, '')))) bad.push({ field: 'phone', reason: 'FORMAT' });
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) bad.push({ field: 'email', reason: 'FORMAT' });
    if (bad.length) return problem(400, 'VALIDATION_FAILED', bad);
    return idempotent(request, () => {
      const key = keyOf(mfcId, who.subject);
      const cur = db.staffContacts.get(key);
      const v = expectedVersion(request);
      if (v !== undefined && v !== (cur?.version ?? 0)) return problem(409, 'VERSION_CONFLICT');
      const next: MockStaffContact = { mfcId, operatorId: who.subject, name, phone, email, version: (cur?.version ?? 0) + 1, updatedAt: timestamp() };
      db.staffContacts.set(key, next);
      return { status: 200, body: next };
    });
  }),
];
