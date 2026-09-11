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
