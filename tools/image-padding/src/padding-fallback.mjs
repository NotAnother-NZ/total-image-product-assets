import sharp from 'sharp';
import { inspect, W, H } from './image.mjs';

const colourDistance = (a, b) => Math.max(...a.map((value, index) => Math.abs(value - b[index])));
const position = (x, y, w, ch) => (y * w + x) * ch;
const rgbHex = color => '#' + color.map(value => value.toString(16).padStart(2, '0')).join('');

/**
 * Conservative fallback when white products sit within a clearly coloured
 * rectangular photographic background. The strict detector rejects those
 * photos when the white subject pushes interior fill density below 97%.
 *
 * This fallback does not mask the subject. It finds an axis-aligned inset only
 * if all four inset edges are independently verified as the same distinct,
 * uniform colour and all four outside corners belong to the border colour.
 * Failure means MANUAL REVIEW, not permission to modify extra pixels.
 */
export async function inspectPaddedPhoto(png) {
  try {
    return { ...await inspect(png), detector: 'strict' };
  } catch (error) {
    if (!/Unsafe interior detection/.test(error.message)) throw error;
  }

  const { data, info } = await sharp(png).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  if (info.width !== W || info.height !== H || info.channels !== 3) throw Error('Expected 1200x1600 RGB input');
  const px = (x, y) => Array.from(data.subarray(position(x, y, W, info.channels), position(x, y, W, info.channels) + 3));
  const outer = px(1, 1);
  for (const [x, y] of [[W - 2, 1], [1, H - 2], [W - 2, H - 2]]) {
    if (colourDistance(px(x, y), outer) > 5) throw Error('Fallback refused: four border corners do not match');
  }

  let l = W, t = H, r = -1, b = -1;
  const threshold = 12;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if (colourDistance(px(x, y), outer) > threshold) {
        l = Math.min(l, x); r = Math.max(r, x);
        t = Math.min(t, y); b = Math.max(b, y);
      }
    }
  }
  if (r < 0) throw Error('Fallback refused: no contrasting photograph detected');
  const rect = { left: l, top: t, width: r - l + 1, height: b - t + 1 };
  if (l < 16 || t < 16 || r > W - 17 || b > H - 17 ||
      rect.width < W * 0.3 || rect.height < H * 0.3) {
    throw Error('Fallback refused: no safely inset rectangle detected');
  }

  const dx = Math.min(12, Math.floor(rect.width * 0.03));
  const dy = Math.min(12, Math.floor(rect.height * 0.03));
  const midXs = [0.13, 0.28, 0.42, 0.58, 0.72, 0.87];
  const midYs = [0.13, 0.28, 0.42, 0.58, 0.72, 0.87];
  const sample = [];
  for (const frac of midXs) {
    const x = l + Math.round(frac * (rect.width - 1));
    sample.push(px(x, t + dy), px(x, b - dy));
  }
  for (const frac of midYs) {
    const y = t + Math.round(frac * (rect.height - 1));
    sample.push(px(l + dx, y), px(r - dx, y));
  }
  const median = channel => [...sample.map(s => s[channel])].sort((a, b) => a - b)[Math.floor(sample.length / 2)];
  const bg = [median(0), median(1), median(2)];
  if (colourDistance(bg, outer) < 14) {
    throw Error('Fallback refused: no distinct background colour; original may already be seamless');
  }
  const matches = sample.filter(s => colourDistance(s, bg) <= 10).length;
  if (matches < sample.length - 1) {
    throw Error('Fallback refused: inset edges are not a consistently uniform background (' + matches + '/' + sample.length + ')');
  }

  // Require contrasting rectangle at each corner, not merely a belt or other
  // free-standing product with a mostly white bounding box.
  const corners = [
    px(l + dx, t + dy), px(r - dx, t + dy),
    px(l + dx, b - dy), px(r - dx, b - dy)
  ];
  if (corners.some(s => colourDistance(s, bg) > 10)) {
    throw Error('Fallback refused: photograph corners do not match the background');
  }

  // Check outside-margin samples: the selected region must be surrounded by
  // original border, not some interior block embedded in a larger photograph.
  const external = [
    px(Math.floor(W / 2), Math.floor(t / 2)),
    px(Math.floor(W / 2), b + Math.floor((H - 1 - b) / 2)),
    px(Math.floor(l / 2), Math.floor(H / 2)),
    px(r + Math.floor((W - 1 - r) / 2), Math.floor(H / 2))
  ];
  if (external.some(s => colourDistance(s, outer) > 10)) {
    throw Error('Fallback refused: sampled outer margins are not consistently the border colour');
  }

  return { rect, bg, hex: rgbHex(bg), uniform: true, detector: 'uniform-edge-fallback', confidence: 'conservative' };
}
