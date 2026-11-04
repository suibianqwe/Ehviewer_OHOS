export function galleryRatingColor(rated: boolean): string {
  return rated ? '#3B82F6' : '#F4C43F';
}

export function hasPersonalRatingClass(markup: string): boolean {
  const classes = /(?:^|\s)class\s*=\s*["']([^"']*)["']/i.exec(markup);
  return classes !== null && /(?:^|\s)(?:irr|irg|irb)(?:\s|$)/i.test(classes[1]);
}

export function parseDetailRated(body: string): boolean {
  const image = /<[^>]+\sid\s*=\s*["']rating_image["'][^>]*>/i.exec(body);
  return image !== null && hasPersonalRatingClass(image[0]);
}
