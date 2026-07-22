import {
  COMMENT_BLACKLIST_REVISION_KEY,
  CommentBlacklistEntry,
  ehCommentBlacklistStore
} from '../services/EhCommentBlacklistStore';
import { getAbilityContext, uiText } from '../shared/EhShared';
import {
  themeDangerText,
  themeDividerColor,
  themeFieldBackground,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import { ConfirmActionOverlay } from './ConfirmActionOverlay';
import { SettingsSubToolbar } from './SessionSettingsScenes';

@Component
export struct CommentBlacklistPanel {
  onBack: () => void = () => {};
  @StorageProp(COMMENT_BLACKLIST_REVISION_KEY) @Watch('onRevisionChanged') revision: number = 0;
  @State entries: CommentBlacklistEntry[] = [];
  @State draftUser: string = '';
  @State draftReason: string = '';
  @State pendingDelete: CommentBlacklistEntry | null = null;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.refreshEntries();
      return;
    }
    ehCommentBlacklistStore.ensureLoaded(context).then(() => {
      this.refreshEntries();
    }).catch(() => {
      this.refreshEntries();
    });
  }

  onRevisionChanged(): void {
    this.refreshEntries();
  }

  private refreshEntries(): void {
    this.entries = ehCommentBlacklistStore.getEntries();
  }

  private addEntry(): void {
    const user = this.draftUser.trim();
    if (user.length === 0) {
      this.showToast('Enter a user name first');
      return;
    }
    if (!ehCommentBlacklistStore.addUser(user, this.draftReason)) {
      this.showToast('This user is already blocked');
      return;
    }
    this.draftUser = '';
    this.draftReason = '';
    this.refreshEntries();
    this.showToast('User added to comment blacklist');
  }

  private deletePendingEntry(): void {
    const entry = this.pendingDelete;
    this.pendingDelete = null;
    if (entry === null) {
      return;
    }
    if (ehCommentBlacklistStore.removeEntry(entry.id)) {
      this.refreshEntries();
      this.showToast('User removed from comment blacklist');
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiText(message) });
    } catch (error) {
    }
  }

  @Builder
  private editorCard() {
    Column({ space: 10 }) {
      Text(uiText('Block comments by user name'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryText())
        .width('100%')
      TextInput({ text: this.draftUser, placeholder: uiText('User name') })
        .height(44)
        .fontSize(15)
        .fontColor(themePrimaryText())
        .placeholderColor(themeTertiaryText())
        .backgroundColor(themeFieldBackground())
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.draftUser = value;
        })
      Row({ space: 10 }) {
        TextInput({ text: this.draftReason, placeholder: uiText('Reason (optional)') })
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontColor(themePrimaryText())
          .placeholderColor(themeTertiaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.draftReason = value;
          })
          .onSubmit(() => {
            this.addEntry();
          })
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .padding(0)
        .borderRadius(22)
        .backgroundColor(themePrimaryColor())
        .onClick(() => {
          this.addEntry();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .border({ width: 1, color: themeDividerColor() })
  }

  @Builder
  private informationCard() {
    Column({ space: 6 }) {
      Text(uiText('Blocked users are hidden from gallery comments.'))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .lineHeight(19)
        .width('100%')
      Text(uiText('App data import, export and Wi-Fi Direct transfer include this blacklist.'))
        .fontSize(12)
        .fontColor(themeTertiaryText())
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurfaceVariant())
    .borderRadius(8)
  }

  @Builder
  private entryCard(entry: CommentBlacklistEntry) {
    Row({ space: 10 }) {
      Column({ space: 5 }) {
        Text(entry.user)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (entry.reason.length > 0) {
          Text(entry.reason)
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else if (entry.sourceComment.length > 0) {
          Text(commentExcerpt(entry.sourceComment))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Text(formatEntryTime(entry.addedAt))
          .fontSize(11)
          .fontColor(themeTertiaryText())
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([themeDangerText()])
      }
      .width(40)
      .height(40)
      .padding(0)
      .borderRadius(20)
      .backgroundColor(themeSurfaceVariant())
      .onClick(() => {
        this.pendingDelete = entry;
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .border({ width: 1, color: themeDividerColor() })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Comment blacklist'),
          onBack: this.onBack
        })

        Scroll() {
          Column({ space: 10 }) {
            this.informationCard()
            this.editorCard()
            Row() {
              Text(uiText('Blocked users'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(themePrimaryText())
              Blank()
              Text(this.entries.length.toString())
                .fontSize(13)
                .fontColor(themePrimaryColor())
            }
            .width('100%')
            .margin({ top: 4 })

            if (this.entries.length === 0) {
              Column({ space: 8 }) {
                Text(uiText('No blocked users'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(themePrimaryText())
                Text(uiText('Add a user name here or block a user from the full comments page.'))
                  .fontSize(13)
                  .fontColor(themeSecondaryText())
                  .textAlign(TextAlign.Center)
                  .lineHeight(19)
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 28, bottom: 28 })
              .backgroundColor(themeSurface())
              .borderRadius(8)
              .border({ width: 1, color: themeDividerColor() })
            } else {
              ForEach(this.entries, (entry: CommentBlacklistEntry) => {
                this.entryCard(entry)
              }, (entry: CommentBlacklistEntry) => entry.id)
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .backgroundColor(themePageBackground())

      if (this.pendingDelete !== null) {
        ConfirmActionOverlay({
          title: 'Remove blocked user',
          message: 'Stop blocking comments from this user?',
          confirmLabel: 'Remove',
          onCancel: () => {
            this.pendingDelete = null;
          },
          onConfirm: () => {
            this.deletePendingEntry();
          }
        })
          .zIndex(20)
      }
    }
    .width('100%')
    .height('100%')
  }
}

function commentExcerpt(html: string): string {
  return html.replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#0*39;|&apos;/gi, "'")
    .replace(/&quot;/gi, '"')
    .replace(/\s+/g, ' ')
    .trim();
}

function formatEntryTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.getFullYear().toString() + '-' + padTwo(date.getMonth() + 1) + '-' + padTwo(date.getDate()) + ' ' +
    padTwo(date.getHours()) + ':' + padTwo(date.getMinutes());
}

function padTwo(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}
