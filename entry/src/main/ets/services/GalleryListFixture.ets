export interface GalleryListFixtureCase {
  name: string;
  html: string;
  expectedCount: number;
}

export const minimalListFixture: string = `
<html>
  <body>
    <div class="searchtext">Showing 48,197 results</div>
    <table class="ptt"><tr><td>1</td><td><a href="/?page=1">2</a></td></tr></table>
    <table class="itg gltm">
      <tr data-new="1">
        <td class="gl1m glcat"><div class="cs ct9">Non-H</div></td>
        <td class="gl2m">
          <div class="glthumb" style="height:140px;width:100px">
            <img data-src="https://ehgt.org/a/b/minimal_250.jpg" />
          </div>
          <div id="posted_1392268">2026-06-11 12:00</div>
        </td>
        <td class="gl3m glname">
          <a href="https://e-hentai.org/g/1392268/7ff56437fa/"><div class="glink">Minimal Fixture Gallery</div></a>
        </td>
        <td class="gl5m glhide">
          <div><a href="https://e-hentai.org/uploader/demo">demo</a></div>
          <div>26 pages</div>
          <div class="ir" title="4.5"></div>
          <div class="gt" title="language:chinese">chinese</div>
        </td>
      </tr>
    </table>
  </body>
</html>`;

export const extendedListFixture: string = `
<html>
  <body>
    <div class="searchtext">Found 1 results</div>
    <table class="itg glte">
      <tr data-new="1">
        <td class="gl1e">
          <a href="/g/2392268/8ff56437fb/">
            <img src="https://ehgt.org/a/b/extended_250.jpg" style="height:150px;width:110px" />
          </a>
        </td>
        <td class="gl2e">
          <div>
            <div class="gl3e">
              <div class="cn ct9">Manga</div>
              <div id="posted_2392268">2026-06-10 20:00</div>
              <div class="ir" title="3.0"></div>
              <div><a href="https://e-hentai.org/uploader/other">other</a></div>
              <div>16 pages</div>
            </div>
            <a href="/g/2392268/8ff56437fb/">
              <div class="gl4e glname"><div class="glink">Extended Fixture Gallery</div></div>
            </a>
            <div class="gtl" title="artist:fixture">fixture</div>
          </div>
        </td>
      </tr>
    </table>
  </body>
</html>`;

export const thumbnailListFixture: string = `
<html>
  <body>
    <div class="itg gld">
      <div class="gl1t" style="height:260px;width:220px">
        <a href="https://e-hentai.org/g/3392268/9ff56437fc/"><div class="gl4t glname">Thumbnail Fixture Gallery</div></a>
        <div class="gl3t">
          <a href="https://e-hentai.org/g/3392268/9ff56437fc/">
            <img src="https://ehgt.org/a/b/thumb_250.jpg" style="height:180px;width:130px" />
          </a>
        </div>
        <div class="gl5t">
          <div class="cn ct2">Doujinshi</div>
          <div id="posted_3392268">2026-06-09 08:30</div>
          <div class="ir" title="4.0"></div>
          <div>42 pages</div>
        </div>
      </div>
    </div>
    <table class="ptb"><tr><td>1</td></tr></table>
  </body>
</html>`;

export const favoritesListFixture: string = `
<html>
  <body>
    <div class="ido">
      <div class="fp"><div>1</div><div></div><div>Fav 0</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 1</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 2</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 3</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 4</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 5</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 6</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 7</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 8</div></div>
      <div class="fp"><div>0</div><div></div><div>Fav 9</div></div>
      <div class="fp fps"></div>
    </div>
    <table class="itg gltm">
      <tr>
        <td class="gl1m glcat"><div>Artist CG</div></td>
        <td class="gl2m">
          <div class="glthumb" id="it1">
            <div><img data-src="https://ehgt.org/fav/thumb.jpg" style="height:120px;width:90px" /></div>
            <div>
              <div><div>2026-06-08</div><div>favorite-user</div></div>
              <div><div class="ir irg" style="background-position:-16px -21px"></div><div>31 pages</div></div>
            </div>
          </div>
          <div class="glcut" id="ic1"></div>
          <div id="posted_4392268" style="background-color:rgba(240,160,0,0.25)">2026-06-08 07:15</div>
        </td>
        <td class="gl3m glname">
          <a href="https://e-hentai.org/g/4392268/aff56437fd/"><div class="glink">Favorite Fixture Gallery</div></a>
        </td>
        <td class="gl4m"><div class="ir irg" style="background-position:-16px -21px"></div></td>
        <td class="gl5m">
          <div><a href="https://e-hentai.org/uploader/favorite-user">favorite-user</a></div>
          <div>31 pages</div>
        </td>
        <td class="gl6m"><div></div></td>
      </tr>
    </table>
  </body>
</html>`;

export const galleryListFixtures: GalleryListFixtureCase[] = [
  { name: 'minimal', html: minimalListFixture, expectedCount: 1 },
  { name: 'extended', html: extendedListFixture, expectedCount: 1 },
  { name: 'thumbnail', html: thumbnailListFixture, expectedCount: 1 },
  { name: 'favorites', html: favoritesListFixture, expectedCount: 1 }
];

export const galleryListFixture: string = minimalListFixture;
