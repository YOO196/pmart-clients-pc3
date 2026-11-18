// 내 인사 정보 목: hr-service `GET /hr/employees/me` — 토큰의 운영자 ID 로 찾고, 없으면 404(인사 기록 없음).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/hr';
import { operator, problem, unauthorized } from './support';

type EmployeeSelf = components['schemas']['EmployeeSelf'];

const employees: Readonly<Record<string, EmployeeSelf>> = {
  'OP-sup-1': {
    operatorId: 'OP-sup-1',
    employeeNo: 'E-2026-0101',
    name: '정관리',
    mailAddress: 'sup1@pmart.test',
    employmentType: 'REGULAR',
    affiliation: { type: 'CENTER', code: 'MFC-BSN-01' },
    status: 'ACTIVE',
  },
  'OP-sup-2': {
    operatorId: 'OP-sup-2',
    employeeNo: 'E-2026-0102',
    name: '한관리',
    mailAddress: 'sup2@pmart.test',
    employmentType: 'REGULAR',
    affiliation: { type: 'HQ_DEPARTMENT', code: '1004' },
    status: 'ACTIVE',
  },
};

export const meHandlers = [
  http.get(`${API_BASE}/hr/employees/me`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const me = employees[who.subject];
    return me ? HttpResponse.json(me) : problem(404, 'NOT_FOUND');
  }),
];
