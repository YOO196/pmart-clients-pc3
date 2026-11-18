// 내 인사 정보 목: hr-service `GET /hr/employees/me` — 토큰의 운영자 ID 로 찾고, 없으면 404(인사 기록 없음).
// 운영자 표시 `GET /hr/employee-labels?operatorIds=`(0.8.0) — 아는 ID 만(퇴사자 포함), 모르는 ID 는 빠진다. 1~50개가 아니면 400.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/hr';
import { operator, problem, unauthorized } from './support';

type EmployeeSelf = components['schemas']['EmployeeSelf'];
type EmployeeLabel = components['schemas']['EmployeeLabel'];

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

/** 관리자·작업자 이름(db 작업자와 같은 이름) — 사번은 목 값 */
const labels: Readonly<Record<string, Omit<EmployeeLabel, 'operatorId'>>> = {
  'OP-sup-1': { name: '정관리', employeeNo: 'E-2026-0101' },
  'OP-sup-2': { name: '한관리', employeeNo: 'E-2026-0102' },
  'OP-admin-1': { name: '오본사', employeeNo: 'E-2026-0001' },
  'OP-wkr-1': { name: '김현장', employeeNo: 'E-2026-0201' },
  'OP-wkr-2': { name: '이알바', employeeNo: 'E-2026-0202' },
  'OP-wkr-3': { name: '최정지', employeeNo: 'E-2026-0203' },
  'OP-wkr-5': { name: '송파작업자', employeeNo: 'E-2026-0205' },
  'OP-wkr-9': { name: '정퇴사', employeeNo: 'E-2026-0209' },
  'OP-day-1': { name: '박일일', employeeNo: 'E-2026-0301' },
};

export const meHandlers = [
  http.get(`${API_BASE}/hr/employee-labels`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const ids = [...new Set(new URL(request.url).searchParams.getAll('operatorIds'))];
    if (ids.length < 1 || ids.length > 50) return problem(400, 'VALIDATION_FAILED');
    return HttpResponse.json({ items: ids.flatMap((id) => (labels[id] ? [{ operatorId: id, ...labels[id] }] : [])) });
  }),
  http.get(`${API_BASE}/hr/employees/me`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const me = employees[who.subject];
    return me ? HttpResponse.json(me) : problem(404, 'NOT_FOUND');
  }),
];
