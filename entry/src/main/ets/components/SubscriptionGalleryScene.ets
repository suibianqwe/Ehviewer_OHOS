import { GalleryRoute } from '../model/GalleryModels';
import { GalleryListScene } from './GalleryScenes';

@Component
export struct SubscriptionGalleryScene {
  resetVersion: number = 0;
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Subscription',
      listMode: 'Watched tags',
      sourceRoute: GalleryRoute.Subscription,
      resetVersion: this.resetVersion,
      onMenu: this.onMenu
    })
  }
}

