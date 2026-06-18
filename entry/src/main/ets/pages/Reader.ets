import { ReaderHostScene } from '../components/ReaderHostScene';
import { runReaderActiveBackHandler } from '../shared/EhShared';

@Entry
@Component
struct ReaderPage {
  onBackPress(): boolean {
    return runReaderActiveBackHandler();
  }

  build() {
    Column() {
      ReaderHostScene()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
  }
}
