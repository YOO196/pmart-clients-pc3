import type { Affiliation } from '../../api/models';
import { messages as m } from '../../shared/messages';

/** "센터 MFC-BSN-01" / "본사 부서 HR" — 코드는 서버 값 그대로 */
export const affiliationText = (a: Affiliation) => `${m.affiliationType[a.type]} ${a.code}`;

/** 기간 표시. 비어 있으면 "-" (0·무기한으로 바꾸지 않는다) */
export const periodText = (from: string | undefined, to: string | undefined) => `${from ?? m.none} ~ ${to ?? m.none}`;
