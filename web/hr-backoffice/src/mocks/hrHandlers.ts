// hr-service 목(계약 hr-service.yaml 0.1.0). 응답 모양은 계약의 Employee·EmployeePage·EmployeeSelf 만 쓴다.
// 409 code 는 계약 info.description(백엔드 회신 2026-11-13 Q5): MAIL_ID_TAKEN, VERSION_CONFLICT, INVALID_STATE. 이미 그 상태인 정지·복귀·퇴사는 바꾸지 않고 200.
//
// 계정 발급 진행(목 규칙): 직원 조회(GET /hr/employees/{id})를 한 번 할 때마다 한 단계씩 나아간다
//   REQUESTED → MAILBOX_CREATED → IAM_CREATED → INVITE_SENT → DONE. 화면이 몇 초마다 다시 조회하는 것을 그대로 따라간다.
//   메일 ID 가 fail 로 시작하면 IAM_CREATED 로 가지 못하고 FAILED(IAM_USERNAME_TAKEN). 다시 시도하면 이어서 끝난다.
// 요청 권한(목 규칙): 발급이 끝나면 PENDING → SUBMITTED, 그 다음 조회에서 소속 센터의 MFC_WORKER 만 APPROVED(자동 승인).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { Affiliation, Employee, EmployeeRegistration, GrantRequestState, ProvisioningStep } from '../api/models';
import { db, nextSeq, timestamp, type MockEmployee } from './db';
import { expectedVersion, idempotent, operator, problem, unauthorized } from './support';

const ORDER: readonly ProvisioningStep[] = ['REQUESTED', 'MAILBOX_CREATED', 'IAM_CREATED', 'INVITE_SENT', 'DONE'];

function requireHr(request: Request) {
  const who = operator(request);
  if (!who) return unauthorized();
  return who.roles.includes('HR_ADMIN') ? null : problem(403, 'FORBIDDEN');
}

const mailIdOf = (e: Employee) => e.mailAddress.replace(/@pmart\.com$/, '');

function touch(m: MockEmployee, patch: Partial<Employee>): Employee {
  m.employee = { ...m.employee, ...patch, version: m.employee.version + 1, updatedAt: timestamp() };
  return m.employee;
}

/** 조회 한 번 = 발급 한 단계(위 목 규칙). version 은 올리지 않는다(발급 진행은 인사 정보 변경이 아니다). */
function advance(m: MockEmployee): void {
  const e = m.employee;
  const step = e.provisioning.step;
  const i = ORDER.indexOf(step);
  if (i >= 0 && i < ORDER.length - 1 && e.status === 'ACTIVE') {
    const next = ORDER[i + 1]!;
    if (m.failAt === next) {
      m.employee = { ...e, provisioning: { step: 'FAILED', attempts: 8, lastErrorCode: 'IAM_USERNAME_TAKEN', updatedAt: timestamp() } };
      return;
    }
    m.employee = { ...e, provisioning: { step: next, attempts: e.provisioning.attempts, updatedAt: timestamp() } };
    if (next === 'DONE') {
      m.employee = {
        ...m.employee,
        requestedGrants: (e.requestedGrants ?? []).map((g): GrantRequestState => (g.submission === 'PENDING' ? { ...g, submission: 'SUBMITTED' } : g)),
      };
    }
    return;
  }
  if (step === 'DONE') {
    const own = e.affiliation.type === 'CENTER' ? e.affiliation.code : null;
    m.employee = {
      ...e,
      requestedGrants: (e.requestedGrants ?? []).map(
        (g): GrantRequestState =>
          g.submission === 'SUBMITTED' && g.role === 'MFC_WORKER' && own !== null && g.centers.length === 1 && g.centers[0] === own
            ? { ...g, submission: 'APPROVED', approvalRef: `AP-mock-${nextSeq()}` }
            : g,
      ),
    };
  }
}

function find(request: Request, id: string | readonly string[] | undefined): MockEmployee | HttpResponse<Record<string, unknown>> {
  const denied = requireHr(request);
  if (denied) return denied as HttpResponse<Record<string, unknown>>;
  return db.employees.get(String(id)) ?? problem(404, 'NOT_FOUND');
}

/** X-Expected-Version 이 있고 다르면 409 */
const stale = (request: Request, m: MockEmployee) => {
  const v = expectedVersion(request);
  return v !== undefined && v !== m.employee.version;
};

const validAffiliation = (a: Affiliation | undefined): a is Affiliation =>
  !!a && (a.type === 'HQ_DEPARTMENT' || a.type === 'CENTER') && /^[A-Za-z0-9_.-]{1,64}$/.test(a.code ?? '');

function reasonCommand(
  path: string,
  apply: (m: MockEmployee, body: { reason: string; startDate?: string; endDate?: string; affiliation?: Affiliation }) => Employee | HttpResponse<Record<string, unknown>>,
) {
  return http.post(`${API_BASE}/hr/employees/:operatorId/${path}`, async ({ request, params }) => {
    const m = find(request, params['operatorId']);
    if (m instanceof Response) return m;
    const body = (await request.json()) as { reason?: string; startDate?: string; endDate?: string; affiliation?: Affiliation };
    if (!body.reason?.trim()) return problem(400, 'VALIDATION_FAILED', [{ field: 'reason', reason: 'REQUIRED' }]);
    return idempotent(request, () => {
      if (stale(request, m)) return problem(409, 'VERSION_CONFLICT');
      const result = apply(m, { ...body, reason: body.reason ?? '' });
      return result instanceof Response ? result : { status: 200, body: result };
    });
  });
}

export const hrHandlers = [
  http.get(`${API_BASE}/hr/employees`, ({ request }) => {
    const denied = requireHr(request);
    if (denied) return denied;
    const url = new URL(request.url);
    const status = url.searchParams.get('status');
    const affiliationCode = url.searchParams.get('affiliationCode');
    const q = url.searchParams.get('q')?.trim().toLowerCase() ?? '';
    const size = Number(url.searchParams.get('size') ?? 50);
    const offset = Number(url.searchParams.get('cursor') ?? 0);
    const all = [...db.employees.values()]
      .map((m) => m.employee)
      .filter((e) => !status || e.status === status)
      .filter((e) => !affiliationCode || e.affiliation.code === affiliationCode)
      .filter((e) => !q || e.name.toLowerCase().startsWith(q) || mailIdOf(e).startsWith(q) || e.employeeNo.toLowerCase().startsWith(q))
      .sort((a, b) => b.employeeNo.localeCompare(a.employeeNo));
    const items = all.slice(offset, offset + size);
    const next = offset + size < all.length ? String(offset + size) : undefined;
    return HttpResponse.json({ items, ...(next ? { nextCursor: next } : {}) });
  }),

  http.post(`${API_BASE}/hr/employees`, async ({ request }) => {
    const denied = requireHr(request);
    if (denied) return denied;
    const body = (await request.json()) as Partial<EmployeeRegistration>;
    const details: Array<{ field: string; reason: string }> = [];
    if (!body.name?.trim()) details.push({ field: 'name', reason: 'REQUIRED' });
    if (!body.mailId || !/^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/.test(body.mailId)) details.push({ field: 'mailId', reason: 'INVALID_FORMAT' });
    if (!validAffiliation(body.affiliation)) details.push({ field: 'affiliation', reason: 'REQUIRED' });
    if (!body.startDate) details.push({ field: 'startDate', reason: 'REQUIRED' });
    if (body.employmentType !== 'REGULAR' && !body.endDate) details.push({ field: 'endDate', reason: 'REQUIRED' });
    if (body.employmentType === 'REGULAR' && body.endDate) details.push({ field: 'endDate', reason: 'NOT_ALLOWED' });
    if (details.length > 0) return problem(400, 'VALIDATION_FAILED', details);
    const reg = body as EmployeeRegistration;
    return idempotent(request, () => {
      const mailAddress = `${reg.mailId}@pmart.com`;
      if ([...db.employees.values()].some((m) => m.employee.mailAddress === mailAddress)) return problem(409, 'MAIL_ID_TAKEN');
      const seq = nextSeq();
      const now = timestamp();
      const employee: Employee = {
        operatorId: `OP-mock-${seq}`,
        employeeNo: `P${reg.startDate.slice(0, 4)}-${String(seq).padStart(5, '0')}`,
        name: reg.name,
        mailAddress,
        employmentType: reg.employmentType,
        affiliation: reg.affiliation,
        startDate: reg.startDate,
        ...(reg.endDate ? { endDate: reg.endDate } : {}),
        status: 'ACTIVE',
        provisioning: { step: 'REQUESTED', attempts: 0, updatedAt: now },
        requestedGrants: (reg.requestedGrants ?? []).map((g) => ({
          role: g.role,
          centers: g.centers ?? [],
          validFrom: g.validFrom ?? reg.startDate,
          ...((g.validTo ?? reg.endDate) ? { validTo: (g.validTo ?? reg.endDate)! } : {}),
          ...(g.reason ? { reason: g.reason } : {}),
          submission: 'PENDING' as const,
        })),
        version: 0,
        createdAt: now,
        updatedAt: now,
      };
      db.employees.set(employee.operatorId, { employee, ...(reg.mailId.startsWith('fail') ? { failAt: 'IAM_CREATED' as const } : {}) });
      return { status: 201, body: employee };
    });
  }),

  // /me 는 /:operatorId 보다 먼저 둔다
  http.get(`${API_BASE}/hr/employees/me`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const e = db.employees.get(who.subject)?.employee;
    if (!e) return problem(404, 'NOT_FOUND');
    return HttpResponse.json({
      operatorId: e.operatorId,
      employeeNo: e.employeeNo,
      name: e.name,
      mailAddress: e.mailAddress,
      employmentType: e.employmentType,
      affiliation: e.affiliation,
      status: e.status,
    });
  }),

  http.get(`${API_BASE}/hr/employees/:operatorId`, ({ request, params }) => {
    const m = find(request, params['operatorId']);
    if (m instanceof Response) return m;
    const shown = m.employee;
    advance(m); // 다음 조회 때 한 단계 나아간 모습이 보인다
    return HttpResponse.json(shown);
  }),

  reasonCommand('affiliation-changes', (m, body) => {
    if (!validAffiliation(body.affiliation)) return problem(400, 'VALIDATION_FAILED', [{ field: 'affiliation', reason: 'REQUIRED' }]);
    if (m.employee.status === 'LEFT') return problem(409, 'INVALID_STATE');
    return touch(m, { affiliation: body.affiliation });
  }),

  reasonCommand('suspensions', (m) => {
    if (m.employee.status === 'LEFT') return problem(409, 'INVALID_STATE');
    return m.employee.status === 'SUSPENDED' ? m.employee : touch(m, { status: 'SUSPENDED' });
  }),

  reasonCommand('reinstatements', (m, body) => {
    if (m.employee.status === 'ACTIVE') return m.employee; // 이미 재직 — 바꾸지 않고 200
    // 파트타임·일일크루는 기존 계약 종료일이 지났으면 새 종료일이 필요하다(회신 2026-11-13 3절)
    const nextEnd = body.endDate ?? m.employee.endDate;
    if (m.employee.employmentType !== 'REGULAR' && (!nextEnd || nextEnd < new Date().toISOString().slice(0, 10))) {
      return problem(400, 'VALIDATION_FAILED', [{ field: 'endDate', reason: 'REQUIRED' }]);
    }
    return touch(m, { status: 'ACTIVE', ...(body.startDate ? { startDate: body.startDate } : {}), ...(body.endDate ? { endDate: body.endDate } : {}) });
  }),

  reasonCommand('departures', (m) => (m.employee.status === 'LEFT' ? m.employee : touch(m, { status: 'LEFT' }))),

  http.post(`${API_BASE}/hr/employees/:operatorId/invite-resends`, ({ request, params }) => {
    const m = find(request, params['operatorId']);
    if (m instanceof Response) return m;
    const step = m.employee.provisioning.step;
    if (m.employee.status !== 'ACTIVE' || (step !== 'INVITE_SENT' && step !== 'DONE')) return problem(409, 'INVALID_STATE');
    return new HttpResponse(null, { status: 202 });
  }),

  http.post(`${API_BASE}/hr/employees/:operatorId/provisioning-retries`, ({ request, params }) => {
    const m = find(request, params['operatorId']);
    if (m instanceof Response) return m;
    return idempotent(request, () => {
      const step = m.employee.provisioning.step;
      if (step !== 'FAILED' && step !== 'COMPENSATED') return problem(409, 'INVALID_STATE');
      delete m.failAt;
      m.employee = { ...m.employee, provisioning: { step: 'REQUESTED', attempts: 0, updatedAt: timestamp() } };
      return { status: 202, body: m.employee };
    });
  }),

  // 계약: 같은 Idempotency-Key 재전송도 결과를 재생하지 않는다(새로 발급). 응답은 저장하지 않는다.
  http.post(`${API_BASE}/hr/employees/:operatorId/mailbox-password-resets`, ({ request, params }) => {
    const m = find(request, params['operatorId']);
    if (m instanceof Response) return m;
    if (m.employee.provisioning.step === 'REQUESTED') return problem(409, 'INVALID_STATE'); // 사서함이 아직 없다
    return HttpResponse.json(
      { mailAddress: m.employee.mailAddress, initialPassword: `mock-${nextSeq()}-pw` },
      { headers: { 'cache-control': 'no-store' } },
    );
  }),
];
