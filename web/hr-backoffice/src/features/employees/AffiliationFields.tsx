// 소속 입력(본사 부서 / 센터 + 코드) — 등록·소속 변경이 같이 쓴다.
// 본사 부서는 `GET /hr/departments`(hr 0.3.0) 목록에서 고르거나 새 코드를 친다. 센터는 목록에서 고른다(둘 다 못 불러오면 직접 입력).
import { AFFILIATION_TYPES, CODE_PATTERN, type Affiliation, type AffiliationType } from '../../api/models';
import { messages as m } from '../../shared/messages';
import { DepartmentInput } from '../departments/departments';
import { CenterSelect, type useCenters } from './centers';

export interface AffiliationDraft {
  readonly type: AffiliationType;
  readonly code: string;
}

/** 계약 모양으로. 코드가 비었거나 형식이 아니면 null */
export const toAffiliation = (d: AffiliationDraft): Affiliation | null => (CODE_PATTERN.test(d.code) ? { type: d.type, code: d.code } : null);

export function AffiliationFields({
  name,
  centers,
  value,
  onChange,
}: {
  /** 라디오 묶음 이름(한 화면에 둘 이상 있을 때 구분) */
  readonly name: string;
  readonly centers: ReturnType<typeof useCenters>;
  readonly value: AffiliationDraft;
  readonly onChange: (next: AffiliationDraft) => void;
}) {
  return (
    <div className="space-y-2">
      <fieldset className="flex items-center gap-4 text-sm">
        <legend className="mb-1">{m.fields.affiliationType}</legend>
        {AFFILIATION_TYPES.map((t) => (
          <label key={t} className="flex items-center gap-1">
            <input
              type="radio"
              className="radio radio-sm"
              name={name}
              checked={value.type === t}
              onChange={() => onChange({ type: t, code: '' })} // 구분을 바꾸면 코드를 비운다(부서 코드가 센터 코드로 남지 않게)
            />
            {m.affiliationType[t]}
          </label>
        ))}
      </fieldset>
      {value.type === 'CENTER' ? (
        <CenterSelect centers={centers} label={m.fields.center} value={value.code} onChange={(code) => onChange({ ...value, code })} />
      ) : (
        <DepartmentInput value={value.code} onChange={(code) => onChange({ ...value, code })} />
      )}
      {value.code !== '' && !CODE_PATTERN.test(value.code) && <p className="text-error text-xs">{m.register.codeInvalid}</p>}
    </div>
  );
}
