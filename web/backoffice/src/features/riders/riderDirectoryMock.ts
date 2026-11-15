// ⚠ BR-54 — 직원용 라이더 목록·검색·상세(`GET /riders`, `GET /riders/{riderId}`)는 아직 계약에 없다(PC 5 BOD-3 예정).
// 화면을 먼저 만들기 위한 목 모드 전용 메모리 목. HTTP 경로를 지어내 부르지 않는다 — 실서버 모드에서는 이 화면이 안내만 보인다.
// 모양은 PC 5 제안(pmart-backend docs/architecture/service-requests/delivery-backoffice-staff-apis.md BOD-3)을 따른 가정이다. 계약이 나오면 생성 타입으로 바꾼다.
import type { components } from '../../api/generated/rider';

export type Restriction = components['schemas']['AccountRestriction'];
export type VehicleType = components['schemas']['VehicleType'];

export interface DraftRiderSummary {
  readonly riderId: string;
  readonly name: string;
  /** 가린 전화번호 */
  readonly phoneMasked: string;
  readonly vehicleType: VehicleType;
  readonly operating: 'ON' | 'OFF';
  readonly operatingMfcId: string | null;
  readonly restriction: Restriction;
}

export interface DraftRiderDetail extends DraftRiderSummary {
  /** 전화번호 전체(상세에서만) */
  readonly phone: string;
  readonly newDispatchOn: boolean;
  readonly joinedAt: string;
  readonly lastHeartbeatAt: string | null;
}

export interface DraftRiderFilter {
  readonly phone?: string | undefined;
  readonly restriction?: Restriction | undefined;
  readonly vehicleType?: VehicleType | undefined;
}

const riders: readonly DraftRiderDetail[] = [
  {
    riderId: 'RID-MOCK-1',
    name: '[목] 라이더 일',
    phone: '01011112222',
    phoneMasked: '010-****-2222',
    vehicleType: 'MOTORCYCLE',
    operating: 'ON',
    operatingMfcId: 'MFC-BSN-01',
    restriction: 'NORMAL',
    newDispatchOn: true,
    joinedAt: '2026-10-01T00:00:00Z',
    lastHeartbeatAt: '2026-11-15T01:00:00Z',
  },
  {
    riderId: 'RID-MOCK-2',
    name: '[목] 라이더 이',
    phone: '01033334444',
    phoneMasked: '010-****-4444',
    vehicleType: 'BICYCLE',
    operating: 'OFF',
    operatingMfcId: null,
    restriction: 'NORMAL',
    newDispatchOn: false,
    joinedAt: '2026-10-10T00:00:00Z',
    lastHeartbeatAt: null,
  },
];

const summary = (r: DraftRiderDetail): DraftRiderSummary => ({
  riderId: r.riderId,
  name: r.name,
  phoneMasked: r.phoneMasked,
  vehicleType: r.vehicleType,
  operating: r.operating,
  operatingMfcId: r.operatingMfcId,
  restriction: r.restriction,
});

export const riderDirectoryMock = {
  /** 전화번호는 숫자만 완전 일치(부분 검색 없음 — 제안 그대로). */
  search(filter: DraftRiderFilter): Promise<DraftRiderSummary[]> {
    const phone = filter.phone?.replace(/\D/g, '');
    return Promise.resolve(
      riders
      .filter((r) => (!phone || r.phone === phone) && (!filter.restriction || r.restriction === filter.restriction) && (!filter.vehicleType || r.vehicleType === filter.vehicleType))
      .map(summary),
    );
  },
  get(riderId: string): Promise<DraftRiderDetail | null> {
    return Promise.resolve(riders.find((r) => r.riderId === riderId) ?? null);
  },
};
