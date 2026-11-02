// 콘텐츠 이미지 고르기(Eum 백오피스 상품 폼 참고). 역할별 영역: 대표(1장) · 상세설명(여러 장, 순서) · 상세정보 표.
// 고른 파일은 미리보기와 함께 목록에 두고(제거 가능), 올리는 시점은 부모가 정한다:
//  - 새 초안: "만들기" 뒤 초안 ID 가 생기면 차례로 올린다(계약상 이미지는 초안에 붙는다).
//  - 기존 초안: 고르는 즉시 올린다.
import { useEffect, useRef } from 'react';

import { IMAGE_ROLES, type ContentImage, type ImageRole } from '../../api/models';
import { messages as m } from '../../shared/messages';
import { AuthedImage } from './AuthedImage';

export interface PendingImage {
  readonly id: string;
  readonly file: File;
  readonly role: ImageRole;
  /** 미리보기 URL(jsdom 처럼 못 만들면 빈 문자열) */
  readonly preview: string;
}

const ACCEPT = 'image/jpeg,image/png,image/webp';
let seq = 0;

// 미리보기는 있으면 좋은 것이다. 못 만들어도(jsdom 등) 파일 선택은 그대로 된다.
const objectUrl = (file: File) => {
  try {
    return typeof URL.createObjectURL === 'function' ? URL.createObjectURL(file) : '';
  } catch {
    return '';
  }
};
const revoke = (url: string) => {
  if (url && typeof URL.revokeObjectURL === 'function') URL.revokeObjectURL(url);
};

export function toPending(files: Iterable<File>, role: ImageRole): PendingImage[] {
  return [...files].map((file) => ({ id: `pending-${++seq}`, file, role, preview: objectUrl(file) }));
}

export function ImagePicker({
  pending,
  onChange,
  existing = [],
  disabled = false,
}: {
  readonly pending: readonly PendingImage[];
  readonly onChange: (next: readonly PendingImage[]) => void;
  /** 이미 올라간 이미지(기존 초안). 역할별로 함께 보인다. */
  readonly existing?: readonly ContentImage[];
  readonly disabled?: boolean;
}) {
  // 화면을 떠나면 미리보기 URL 을 놓아 준다.
  const latest = useRef<readonly PendingImage[]>([]);
  useEffect(() => {
    latest.current = pending;
  }, [pending]);
  useEffect(() => () => latest.current.forEach((p) => revoke(p.preview)), []);

  const add = (files: FileList | null, role: ImageRole) => {
    if (!files || files.length === 0) return;
    const added = toPending(files, role);
    if (role === 'MAIN') {
      // 대표는 1장. 이미 고른 대표는 새것으로 바꾼다.
      pending.filter((p) => p.role === 'MAIN').forEach((p) => revoke(p.preview));
      onChange([...pending.filter((p) => p.role !== 'MAIN'), added[0]!]);
      return;
    }
    onChange([...pending, ...added]);
  };
  const remove = (id: string) => {
    pending.filter((p) => p.id === id).forEach((p) => revoke(p.preview));
    onChange(pending.filter((p) => p.id !== id));
  };

  return (
    <div className="grid gap-3 md:grid-cols-3">
      {IMAGE_ROLES.map((role) => (
        <RoleSection
          key={role}
          role={role}
          existing={existing.filter((i) => i.role === role).sort((a, b) => a.sortOrder - b.sortOrder)}
          pending={pending.filter((p) => p.role === role)}
          disabled={disabled}
          onAdd={(files) => add(files, role)}
          onRemove={remove}
        />
      ))}
    </div>
  );
}

function RoleSection({
  role,
  existing,
  pending,
  disabled,
  onAdd,
  onRemove,
}: {
  readonly role: ImageRole;
  readonly existing: readonly ContentImage[];
  readonly pending: readonly PendingImage[];
  readonly disabled: boolean;
  readonly onAdd: (files: FileList | null) => void;
  readonly onRemove: (id: string) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const label = m.contents.imageRole[role];
  const hint = m.contents.imageRoleHint[role];
  const addLabel = m.contents.addImage(label);
  const empty = existing.length === 0 && pending.length === 0;
  const open = () => {
    if (!disabled) input.current?.click();
  };

  return (
    <section className="space-y-2 rounded-box border border-base-300 p-3" aria-label={label}>
      <div className="flex items-start justify-between gap-2">
        <div>
          <h3 className="text-sm font-bold">{label}</h3>
          <p className="text-xs opacity-70">{hint}</p>
        </div>
        <button type="button" className="btn btn-outline btn-xs" disabled={disabled} onClick={open}>
          {m.contents.addImageButton}
        </button>
      </div>
      <input
        ref={input}
        type="file"
        accept={ACCEPT}
        multiple={role !== 'MAIN'}
        aria-label={addLabel}
        className="hidden"
        disabled={disabled}
        onChange={(e) => {
          onAdd(e.target.files);
          e.target.value = '';
        }}
      />
      {empty ? (
        <button
          type="button"
          className="flex w-full flex-col items-center justify-center gap-1 rounded-box border-2 border-dashed border-base-300 py-6 text-xs opacity-70 hover:border-base-content"
          disabled={disabled}
          onClick={open}
        >
          <span aria-hidden="true" className="text-2xl">
            🖼
          </span>
          {m.contents.imageEmpty}
        </button>
      ) : (
        <ul className="grid grid-cols-3 gap-2" aria-label={m.contents.imageListOf(label)}>
          {existing.map((img) => (
            <li key={img.imageId} className="relative aspect-square overflow-hidden rounded-box border border-base-300 bg-base-200">
              <AuthedImage imageId={img.imageId} alt={`${label} ${img.sortOrder}`} className="h-full w-full object-contain" />
              <span className="badge badge-neutral badge-xs absolute top-1 left-1">{img.sortOrder}</span>
            </li>
          ))}
          {pending.map((p, i) => (
            <li
              key={p.id}
              className="relative aspect-square overflow-hidden rounded-box border border-dashed border-primary bg-base-200"
              aria-label={m.contents.pendingImage(p.file.name)}
            >
              {p.preview ? (
                <img src={p.preview} alt={p.file.name} className="h-full w-full object-contain" />
              ) : (
                <span className="flex h-full items-center justify-center p-1 text-center text-[10px] break-all">{p.file.name}</span>
              )}
              <span className="badge badge-primary badge-xs absolute top-1 left-1">{existing.length + i}</span>
              <button
                type="button"
                className="btn btn-circle btn-xs absolute top-1 right-1"
                aria-label={m.contents.removeImage(p.file.name)}
                title={m.contents.removeImage(p.file.name)}
                disabled={disabled}
                onClick={() => onRemove(p.id)}
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
