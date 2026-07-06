export interface GalleryInfo {
  gid: number;
  token: string;
  title: string;
  titleJpn?: string;
  thumb?: string;
  category: number;
  posted?: string;
  uploader?: string;
  rating: number;
  rated: boolean;
  simpleLanguage?: string;
  simpleTags?: string[];
  pages: number;
  thumbWidth: number;
  thumbHeight: number;
  favoriteSlot: number;
  favoriteName?: string;
  tagList?: string[];
  detailTags?: GalleryTagGroup[];
  detailLanguage?: string;
}

export interface GalleryDetail extends GalleryInfo {
  apiUid: number;
  apiKey: string;
  tags: GalleryTagGroup[];
  comments: GalleryComment[];
  torrentCount: number;
  torrentUrl: string;
  archiveUrl: string;
  parent: string;
  visible: string;
  language: string;
  size: string;
  favoriteCount: number;
  isFavorited: boolean;
  ratingCount: number;
  previewPages: number;
  previewSet: GalleryPreview[];
}

export interface GalleryTagGroup {
  namespace: string;
  tags: string[];
  tagInfos?: GalleryTagInfo[];
}

export interface GalleryTagInfo {
  id: number;
  namespace: string;
  tag: string;
  fullTag: string;
  voteUpEd?: boolean;
  voteDownEd?: boolean;
}

export interface GalleryComment {
  id: string;
  user: string;
  posted: string;
  content: string;
  score: number;
  voteUpAble?: boolean;
  voteUpEd?: boolean;
  voteDownAble?: boolean;
  voteDownEd?: boolean;
  voteState?: string;
}

export interface GalleryPreview {
  index: number;
  pageUrl: string;
  imageUrl: string;
  width: number;
  height: number;
  xOffset: number;
  yOffset: number;
}

export interface GalleryPage {
  pageUrl: string;
  imageUrl: string;
  skipHathKey: string;
  originImageUrl: string;
  showKey: string;
  cachedImagePath?: string;
  cachedOriginImagePath?: string;
}

export interface ArchiveOption {
  value: string;
  label: string;
}

export interface HathArchiveList {
  formParamOr: string;
  options: ArchiveOption[];
}

export interface ArchiverOption {
  kind: string;
  label: string;
  cost: string;
  size: string;
  url: string;
  dlType: string;
  dlCheck: string;
}

export interface ArchiverInfo {
  funds: string;
  options: ArchiverOption[];
}

export interface TopListItem {
  href: string;
  gid: string;
  token: string;
  tag: string;
  value: string;
}

export interface TopListBucket {
  title: string;
  follow: string;
  items: TopListItem[];
}

export interface TopListInfo {
  kind: TopListKind;
  title: string;
  buckets: TopListBucket[];
}

export interface TopListDetail {
  title: string;
  lists: TopListInfo[];
}

export enum TopListKind {
  Gallery = 0,
  Uploader = 1,
  Tagging = 2,
  HentaiHome = 3,
  EhTracker = 4,
  Cleanup = 5,
  RatingAndReviewing = 6
}

export enum GalleryRoute {
  Home = 'home',
  Subscription = 'subscription',
  WhatsHot = 'whats_hot',
  TopLists = 'top_lists',
  Favorites = 'favorites',
  History = 'history',
  Downloads = 'downloads',
  Session = 'session',
  Migration = 'migration',
  Settings = 'settings'
}

export enum GallerySite {
  E = 0,
  Ex = 1
}

export enum GalleryCategory {
  None = -1,
  Misc = 0x1,
  Doujinshi = 0x2,
  Manga = 0x4,
  ArtistCg = 0x8,
  GameCg = 0x10,
  ImageSet = 0x20,
  Cosplay = 0x40,
  AsianPorn = 0x80,
  NonH = 0x100,
  Western = 0x200,
  Unknown = 0x400
}

export const ALL_CATEGORY: number = 0x3ff;
