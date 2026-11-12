// 여러 개 고르는 드롭다운. 평소에는 닫힌 한 줄(고른 개수)로 보이고, 누르면 체크박스 목록이 펼쳐진다.
// 바깥을 누르거나 Esc 로 닫는다. 고른 값의 순서는 목록 순서를 따른다(목록에 없는 기존 값은 맨 앞에 그대로 둔다).
import { useEffect, useId, useRef, useState } from 'react';

export interface MultiSelectOption {
  readonly value: string;
  readonly label: string;
  readonly disabled?: boolean;
}

export function MultiSelectDropdown({
  label,
  options,
  value,
  onChange,
  placeholder,
  selectedText,
  disabled = false,
  className = '',
}: {
  readonly label: string;
  readonly options: readonly MultiSelectOption[];
  readonly value: readonly string[];
  readonly onChange: (next: string[]) => void;
  /** 아무것도 고르지 않았을 때 */
  readonly placeholder: string;
  /** 고른 개수 표시 */
  readonly selectedText: (count: number) => string;
  readonly disabled?: boolean;
  readonly className?: string;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const labelId = useId();
  const panelId = useId();

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (root.current && !root.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const chosen = new Set(value);
  const known = new Set(options.map((o) => o.value));
  const toggle = (v: string) => {
    const next = new Set(chosen);
    if (next.has(v)) next.delete(v);
    else next.add(v);
    onChange([...value.filter((x) => !known.has(x)), ...options.filter((o) => next.has(o.value)).map((o) => o.value)]);
  };

  return (
    <div ref={root} className={`relative flex flex-col gap-1 text-sm ${className}`}>
      <span id={labelId}>{label}</span>
      <button
        type="button"
        className="select select-sm w-full items-center text-left"
        aria-labelledby={labelId}
        aria-haspopup="true"
        aria-expanded={open}
        aria-controls={panelId}
        disabled={disabled}
        onClick={() => setOpen((o) => !o)}
      >
        <span className={value.length === 0 ? 'opacity-60' : ''}>{value.length === 0 ? placeholder : selectedText(value.length)}</span>
      </button>
      {open && (
        <ul
          id={panelId}
          role="group"
          aria-labelledby={labelId}
          className="absolute top-full z-20 mt-1 max-h-64 w-full overflow-auto rounded-box border border-base-300 bg-base-100 p-1 shadow"
        >
          {options.map((o) => (
            <li key={o.value}>
              <label className={`flex items-center gap-2 rounded px-2 py-1 ${o.disabled ? 'opacity-50' : 'cursor-pointer hover:bg-base-200'}`}>
                <input
                  type="checkbox"
                  className="checkbox checkbox-xs"
                  checked={chosen.has(o.value)}
                  disabled={o.disabled}
                  onChange={() => toggle(o.value)}
                />
                {o.label}
              </label>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
