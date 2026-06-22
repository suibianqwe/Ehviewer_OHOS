import { IDataSourcePrefetching } from '@kit.ArkUI';

export class ArrayDataSource<T> implements IDataSource, IDataSourcePrefetching {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];
  private prefetchCb: ((item: T) => void) | undefined = undefined;

  constructor(items: T[]) {
    this.items = items;
  }

  setItems(items: T[]): void {
    this.items = items;
    this.notifyReloaded();
  }

  replaceItems(items: T[]): void {
    this.items = items;
  }

  // 末尾追加单条并精确通知，避免 notifyReload 触发全量重建
  appendAndNotify(item: T): void {
    this.items.push(item);
    const index = this.items.length - 1;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  notifyChange(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  notifyReload(): void {
    this.notifyReloaded();
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const next: DataChangeListener[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  setPrefetchCallback(cb: (item: T) => void): void {
    this.prefetchCb = cb;
  }

  prefetch(index: number): void {
    if (this.prefetchCb !== undefined && index >= 0 && index < this.items.length) {
      this.prefetchCb(this.items[index]);
    }
  }

  cancel(_index: number): void {
    // Downloads are small and always useful to cache; cancellation is a no-op.
  }

  private notifyReloaded(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
