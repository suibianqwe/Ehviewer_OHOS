export class ArrayDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: T[]) {
    this.items = items;
  }

  setItems(items: T[]): void {
    this.items = items;
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

  private notifyReloaded(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
