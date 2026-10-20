import { GalleryComment } from '../model/GalleryModels';
import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';
import { parseGalleryDetail } from './GalleryDetailParser';

export interface CommentPostResult {
  ok: boolean;
  statusCode: number;
  message: string;
  comments: GalleryComment[];
}

export const COMMENT_POST_UNCONFIRMED: string =
  'Comment submission could not be confirmed. Check the comments before sending again.';

export function parseCommentPostResponse(body: string, gid: number, token: string): CommentPostResult {
  // E-H returns validation/rate-limit errors immediately after the comment heading,
  // even with HTTP 200. Never treat the existing comments alone as a successful POST.
  const error = /<div\b[^>]*\bid=["']chd["'][^>]*>[\s\S]*?<\/div>\s*<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(body);
  if (error !== null) {
    const message = decodeHtmlEntities(error[1].replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
    return { ok: false, statusCode: 200, message: message || COMMENT_POST_UNCONFIRMED, comments: [] };
  }
  const detail = parseGalleryDetail(body).detail;
  const hasCommentForm = /<textarea\b[^>]*\bname=["']commenttext_new["']/i.test(body);
  if (detail === null || detail.gid !== gid || detail.token !== token || detail.apiUid < 0 ||
    !hasCommentForm || detail.comments.length === 0) {
    return { ok: false, statusCode: 200, message: COMMENT_POST_UNCONFIRMED, comments: [] };
  }
  return { ok: true, statusCode: 200, message: 'Comment posted', comments: detail.comments };
}
