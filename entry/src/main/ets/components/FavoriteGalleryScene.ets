import { GalleryRoute } from '../model/GalleryModels';
import { GalleryListScene } from './GalleryScenes';

@Component
export struct FavoriteGalleryScene {
  resetVersion: number = 0;
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Favourite',
      listMode: 'Favorites',
      sourceRoute: GalleryRoute.Favorites,
      resetVersion: this.resetVersion,
      onMenu: this.onMenu
    })
  }
}


