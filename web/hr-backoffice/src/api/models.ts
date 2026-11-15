// 화면이 쓰는 모델. 생성 타입에서만 뽑는다(필드를 손으로 만들지 않는다) — 계약 hr-service.yaml 0.1.0.
import type { components as Hr } from './generated/hr';

type H = Hr['schemas'];

export type Employee = H['Employee'];
export type EmployeeSelf = H['EmployeeSelf'];
export type EmployeePage = H['EmployeePage'];
export type EmployeeRegistration = H['EmployeeRegistration'];
export type Affiliation = H['Affiliation'];
export type AffiliationType = Affiliation['type'];
export type RequestedGrant = H['RequestedGrant'];
export type GrantRequestState = H['GrantRequestState'];
export type GrantSubmission = GrantRequestState['submission'];
export type Provisioning = H['Provisioning'];
export type ProvisioningStep = H['ProvisioningStep'];
export type EmploymentType = H['EmploymentType'];
export type EmploymentStatus = H['EmploymentStatus'];

export const EMPLOYMENT_TYPES = ['REGULAR', 'PART_TIME', 'DAILY'] as const satisfies readonly EmploymentType[];
export const EMPLOYMENT_STATUSES = ['ACTIVE', 'SUSPENDED', 'LEFT'] as const satisfies readonly EmploymentStatus[];
export const AFFILIATION_TYPES = ['HQ_DEPARTMENT', 'CENTER'] as const satisfies readonly AffiliationType[];

/** 계정 발급이 아직 진행 중인 단계(상세 화면이 몇 초마다 다시 조회한다) */
export const PROVISIONING_IN_PROGRESS: readonly ProvisioningStep[] = ['REQUESTED', 'MAILBOX_CREATED', 'IAM_CREATED', 'INVITE_SENT'];
/** 발급 다시 시도 버튼을 보이는 단계(계약 retryProvisioning — 그 밖은 409 INVALID_STATE) */
export const PROVISIONING_RETRYABLE: readonly ProvisioningStep[] = ['FAILED', 'COMPENSATED'];

// 요청 권한으로 고를 수 있는 역할은 고정 목록 대신 `GET /employee-auth/roles`(employee-auth 0.5.0, BR-57 — 백엔드 알림
// hr-backoffice/2026-11-15-notice-role-list-and-departments §1)에서 받는다: features/employees/roles.ts.

/** 계약 EmployeeRegistration.mailId pattern(입력 도움용 — 판정은 서버) */
export const MAIL_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/;
/** 계약 Affiliation.code·센터 코드 pattern */
export const CODE_PATTERN = /^[A-Za-z0-9_.-]{1,64}$/;
