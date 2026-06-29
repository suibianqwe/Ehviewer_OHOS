import { GalleryRoute } from '../model/GalleryModels';
import { GalleryListScene } from './GalleryScenes';

@Component
export struct HomeGalleryScene {
  resetVersion: number = 0;
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Homepage',
      listMode: 'Search',
      sourceRoute: GalleryRoute.Home,
      resetVersion: this.resetVersion,
      onMenu: this.onMenu
    })
  }
}

