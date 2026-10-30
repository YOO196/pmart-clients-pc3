// 이미지 본문도 인증이 필요하다(<img src> 는 JWT 를 못 보냄). BR-25: 방식이 정해질 때까지 fetch + Bearer → blob URL.
// 같은 imageId 의 본문은 바뀌지 않아(내용 주소) blob URL 을 캐시에 두고 다시 쓴다(탭을 닫으면 해제된다).
import { useQuery } from '@tanstack/react-query';

import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { messages as m } from '../../shared/messages';

export function AuthedImage({ imageId, alt, className }: { readonly imageId: string; readonly alt: string; readonly className?: string }) {
  const api = useApi();
  const query = useQuery({
    queryKey: ['content', 'image', imageId],
    staleTime: Infinity,
    gcTime: Infinity,
    queryFn: async () => {
      const blob = await request(
        'GET',
        api.content.GET('/content-images/{imageId}', { params: { path: { imageId } }, parseAs: 'blob' }),
      );
      return URL.createObjectURL(blob);
    },
  });

  if (query.isPending) return <span className="loading loading-spinner loading-sm" />;
  if (query.isError) return <span className="text-error text-xs">{m.contents.imageUnavailable}</span>;
  return <img src={query.data} alt={alt} className={className} />;
}
