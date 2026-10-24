// 화면이 쓰는 bff 응답 타입(생성 타입에서 뽑는다).
import type { paths } from './generated/backoffice-bff';

export type ApprovalInboxView =
  paths['/views/approval-inbox']['get']['responses']['200']['content']['application/json'];
