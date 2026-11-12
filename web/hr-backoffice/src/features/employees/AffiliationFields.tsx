// 소속 입력(본사 부서 / 센터 + 코드) — 등록·소속 변경이 같이 쓴다.
// 본사 부서 코드 목록을 주는 API 가 없어 직접 입력받는다(회신 Q1). 센터는 목록에서 고른다(못 불러오면 직접 입력).
import { AFFILIATION_TYPES, CODE_PATTERN, type Affiliation, type AffiliationType } from '../../api/models';
import { messages as m } from '../../shared/messages';
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
        <label className="flex flex-col gap-1 text-sm">
          {m.fields.departmentCode}
          <input
            className="input input-sm w-full max-w-xs"
            maxLength={64}
            value={value.code}
            onChange={(e) => onChange({ ...value, code: e.target.value.trim() })}
          />
        </label>
      )}
      {value.code !== '' && !CODE_PATTERN.test(value.code) && <p className="text-error text-xs">{m.register.codeInvalid}</p>}
    </div>
  );
}
