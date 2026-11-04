import { GalleryComment } from '../model/GalleryModels';

export interface CommentListItem {
  identity: string;
  revision: number;
  key: string;
  comment: GalleryComment;
}

function sameComment(left: GalleryComment, right: GalleryComment): boolean {
  return left.id === right.id && left.user === right.user && left.posted === right.posted &&
    left.content === right.content && left.score === right.score && left.voteUpAble === right.voteUpAble &&
    left.voteUpEd === right.voteUpEd && left.voteDownAble === right.voteDownAble &&
    left.voteDownEd === right.voteDownEd && left.voteState === right.voteState;
}

function copyComment(comment: GalleryComment): GalleryComment {
  // Keep a snapshot: callers may mutate a vote in place before notifying us.
  return {
    id: comment.id,
    user: comment.user,
    posted: comment.posted,
    content: comment.content,
    score: comment.score,
    voteUpAble: comment.voteUpAble,
    voteUpEd: comment.voteUpEd,
    voteDownAble: comment.voteDownAble,
    voteDownEd: comment.voteDownEd,
    voteState: comment.voteState
  };
}

// Called only when comments/blacklist change, never by a scroll callback.
// Stable IDs preserve unchanged rows after deletion; revisions rebuild only
// changed rows because LazyForEach reload does not refresh an unchanged key.
export function buildCommentListItems(comments: GalleryComment[], previous: CommentListItem[]): CommentListItem[] {
  const oldItems: Map<string, CommentListItem> = new Map<string, CommentListItem>();
  for (let i = 0; i < previous.length; i++) {
    oldItems.set(previous[i].identity, previous[i]);
  }
  const occurrences: Map<string, number> = new Map<string, number>();
  const result: CommentListItem[] = [];
  for (let index = 0; index < comments.length; index++) {
    const comment = comments[index];
    const occurrence = occurrences.get(comment.id) ?? 0;
    occurrences.set(comment.id, occurrence + 1);
    const identity = comment.id.length.toString() + ':' + comment.id + ':' + occurrence.toString();
    const old = oldItems.get(identity);
    const unchanged = old !== undefined && sameComment(old.comment, comment);
    const revision = old === undefined ? 0 : old.revision + (unchanged ? 0 : 1);
    result.push({
      identity: identity,
      revision: revision,
      key: identity + ':' + revision.toString(),
      comment: unchanged && old !== undefined ? old.comment : copyComment(comment)
    });
  }
  return result;
}
