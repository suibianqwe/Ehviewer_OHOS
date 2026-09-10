import { uiAdaptiveColumnCount, uiTitleBarFadeHeight } from './EhUiStyle';

export function galleryListHorizontalPadding(_contentWidth: number): number {
  return 12;
}

export function galleryListViewportHeight(viewportHeight: number): number {
  return viewportHeight <= 0 ? 1 : Math.max(1, viewportHeight);
}

// This is scrollable content spacing, not the currently visible toolbar height.
// It must stay fixed while the toolbar moves, otherwise restoring the toolbar
// changes the viewport or inserts a strip above the currently visible cards.
export function galleryListTopInset(toolbarHeight: number): number {
  return toolbarHeight + uiTitleBarFadeHeight() * 0.68;
}

export function galleryListColumnCount(contentWidth: number, preferredWidth: number, gap: number): number {
  return uiAdaptiveColumnCount(contentWidth, preferredWidth, gap, galleryListHorizontalPadding(contentWidth));
}

export function galleryListColumnsTemplate(columns: number): string {
  let template = '';
  for (let index = 0; index < Math.max(1, columns); index++) {
    template += '1fr ';
  }
  return template.trim();
}
