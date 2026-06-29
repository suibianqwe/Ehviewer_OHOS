import { GalleryRoute } from '../model/GalleryModels';
import { GalleryListScene } from './GalleryScenes';

@Component
export struct HotGalleryScene {
  resetVersion: number = 0;
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'What\'s Hot',
      listMode: 'Popular',
      sourceRoute: GalleryRoute.WhatsHot,
      resetVersion: this.resetVersion,
      onMenu: this.onMenu
    })
  }
}

