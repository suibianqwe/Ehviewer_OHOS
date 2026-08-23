export const FLOATING_ACTION_SIZE: number = 44;
export const FLOATING_ACTION_GAP: number = 8;
export const FLOATING_ACTION_PRIMARY_SIZE: number = 54;
export const FLOATING_ACTION_PRIMARY_GAP: number = 10;
export const FLOATING_ACTION_DEFAULT_MAX_HEIGHT: number = 360;

export function floatingActionAvailableHeight(viewportHeight: number, reservedTop: number,
  reservedBottom: number = 24): number {
  if (viewportHeight <= 0 || Number.isNaN(viewportHeight)) {
    return FLOATING_ACTION_DEFAULT_MAX_HEIGHT;
  }
  return Math.max(FLOATING_ACTION_SIZE,
    viewportHeight - Math.max(0, reservedTop) - Math.max(0, reservedBottom) -
    FLOATING_ACTION_PRIMARY_SIZE - FLOATING_ACTION_PRIMARY_GAP);
}

export function floatingActionMaxRows(maxExpandedHeight: number): number {
  return Math.max(1, Math.floor((Math.max(FLOATING_ACTION_SIZE, maxExpandedHeight) +
    FLOATING_ACTION_GAP) / (FLOATING_ACTION_SIZE + FLOATING_ACTION_GAP)));
}

export function floatingActionColumnCount(actionCount: number, maxExpandedHeight: number): number {
  if (actionCount <= 0) {
    return 0;
  }
  return Math.ceil(actionCount / floatingActionMaxRows(maxExpandedHeight));
}

export function floatingActionRowCount(actionCount: number, maxExpandedHeight: number): number {
  return Math.min(Math.max(0, actionCount), floatingActionMaxRows(maxExpandedHeight));
}

export function floatingActionGridHeight(actionCount: number, maxExpandedHeight: number): number {
  const rows = floatingActionRowCount(actionCount, maxExpandedHeight);
  if (rows <= 0) {
    return 0;
  }
  return rows * FLOATING_ACTION_SIZE + (rows - 1) * FLOATING_ACTION_GAP;
}

export function floatingActionGridWidth(actionCount: number, maxExpandedHeight: number): number {
  const columns = floatingActionColumnCount(actionCount, maxExpandedHeight);
  if (columns <= 0) {
    return 0;
  }
  return columns * FLOATING_ACTION_SIZE + (columns - 1) * FLOATING_ACTION_GAP;
}

export function floatingActionToolbarWidth(actionCount: number, maxExpandedHeight: number): number {
  return Math.max(FLOATING_ACTION_PRIMARY_SIZE, floatingActionGridWidth(actionCount, maxExpandedHeight));
}

export function floatingActionVisualColumns(actionCount: number, maxExpandedHeight: number): number[] {
  const columns: number[] = [];
  for (let column = floatingActionColumnCount(actionCount, maxExpandedHeight) - 1; column >= 0; column--) {
    columns.push(column);
  }
  return columns;
}

export function floatingActionIndexesForColumn(column: number, actionCount: number,
  maxExpandedHeight: number): number[] {
  const indexes: number[] = [];
  const maxRows = floatingActionMaxRows(maxExpandedHeight);
  const start = column * maxRows;
  const end = Math.min(actionCount, start + maxRows);
  for (let index = start; index < end; index++) {
    indexes.push(index);
  }
  return indexes;
}

export function floatingActionHitIndex(x: number, y: number, actionCount: number,
  maxExpandedHeight: number): number {
  if (actionCount > 0) {
    const actionsHeight = floatingActionGridHeight(actionCount, maxExpandedHeight);
    const actionsWidth = floatingActionGridWidth(actionCount, maxExpandedHeight);
    const toolbarWidth = floatingActionToolbarWidth(actionCount, maxExpandedHeight);
    const actionsLeft = toolbarWidth - actionsWidth;
    if (x >= actionsLeft && x <= toolbarWidth && y >= 0 && y <= actionsHeight) {
      const relativeX = x - actionsLeft;
      const visualColumn = Math.floor(relativeX / (FLOATING_ACTION_SIZE + FLOATING_ACTION_GAP));
      const columnLeft = visualColumn * (FLOATING_ACTION_SIZE + FLOATING_ACTION_GAP);
      const row = Math.floor(y / (FLOATING_ACTION_SIZE + FLOATING_ACTION_GAP));
      const rowTop = row * (FLOATING_ACTION_SIZE + FLOATING_ACTION_GAP);
      const columnCount = floatingActionColumnCount(actionCount, maxExpandedHeight);
      const maxRows = floatingActionMaxRows(maxExpandedHeight);
      if (visualColumn >= 0 && visualColumn < columnCount &&
        relativeX <= columnLeft + FLOATING_ACTION_SIZE &&
        row >= 0 && row < maxRows && y >= rowTop && y <= rowTop + FLOATING_ACTION_SIZE) {
        const logicalColumn = columnCount - visualColumn - 1;
        const index = logicalColumn * maxRows + row;
        return index < actionCount ? index : -1;
      }
    }
    const primaryTop = actionsHeight + FLOATING_ACTION_PRIMARY_GAP;
    const primaryLeft = toolbarWidth - FLOATING_ACTION_PRIMARY_SIZE;
    if (x >= primaryLeft && x <= toolbarWidth &&
      y >= primaryTop && y <= primaryTop + FLOATING_ACTION_PRIMARY_SIZE) {
      return actionCount;
    }
    return -1;
  }
  if (x >= 0 && x <= FLOATING_ACTION_PRIMARY_SIZE && y >= 0 && y <= FLOATING_ACTION_PRIMARY_SIZE) {
    return 0;
  }
  return -1;
}
