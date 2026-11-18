// hr-service 본인 조회 `GET /hr/employees/me`(계약 hr-service.yaml `getMyEmployee`·`EmployeeSelf`)만 옮긴 타입.
// mfc-backoffice 웹 생성 목록(tools/web-tools/gen-api.mjs — PC 2)에 `hr` 이 없어서 이 경로 하나만 계약 그대로 적었다.
// 목록에 `hr` 이 들어오면 이 파일을 지우고 `./generated/hr` 의 `paths` 를 쓴다(모양이 같다).
// 본인 비밀번호 바꾸기(EA-3)·연락처(HR-3)는 계약에 아직 없다 — 여기에 만들어 넣지 않는다.

export type EmploymentStatus = 'ACTIVE' | 'SUSPENDED' | 'LEFT';
export type EmploymentType = 'REGULAR' | 'PART_TIME' | 'DAILY';

export interface Affiliation {
  code: string;
  type: 'HQ_DEPARTMENT' | 'CENTER';
}

export interface EmployeeSelf {
  affiliation: Affiliation;
  employeeNo: string;
  employmentType: EmploymentType;
  mailAddress: string;
  name: string;
  operatorId: string;
  status: EmploymentStatus;
}

interface ErrorResponse {
  code: string;
  detail?: string;
  details?: { field?: string; reason?: string }[];
  status: number;
  title: string;
  type: string;
}

export interface HrSelfPaths {
  '/hr/employees/me': {
    parameters: { query?: never; header?: never; path?: never; cookie?: never };
    get: {
      parameters: { query?: never; header?: never; path?: never; cookie?: never };
      requestBody?: never;
      responses: {
        200: { headers: { [name: string]: unknown }; content: { 'application/json': EmployeeSelf } };
        404: { headers: { [name: string]: unknown }; content: { 'application/problem+json': ErrorResponse } };
      };
    };
    put?: never;
    post?: never;
    delete?: never;
    options?: never;
    head?: never;
    patch?: never;
    trace?: never;
  };
}
