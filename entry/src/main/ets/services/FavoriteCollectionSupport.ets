import { FavoriteCategoryInfo } from './GalleryListParser';

export interface FavoriteSlotOption {
  slot: number;
  label: string;
}

export function favoriteSlotOptions(categories: FavoriteCategoryInfo[]): FavoriteSlotOption[] {
  const options: FavoriteSlotOption[] = [{ slot: -1, label: 'Local Favorites' }];
  for (let slot = 0; slot < 10; slot++) {
    const category = categories.find((item: FavoriteCategoryInfo) => item.favCat === slot);
    options.push({ slot: slot, label: category !== undefined && category.name.length > 0
      ? category.name : 'Favorites ' + slot.toString() });
  }
  return options;
}
