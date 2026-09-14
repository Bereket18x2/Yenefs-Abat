// One-off script: crop the wide source logo down to its circular badge,
// then export small, compressed, purpose-built sizes for the website.
// Run with: node scripts/optimize-logo.js
const sharp = require('sharp');
const path = require('path');

const SRC = path.join(__dirname, '..', 'public', 'logo.png');
const OUT = (name) => path.join(__dirname, '..', 'public', name);

async function main() {
  const src = sharp(SRC);
  const meta = await src.metadata();

  // The badge circle is centered vertically and nearly fills the height;
  // crop a centered square so nothing gets stretched when displayed at
  // 1:1 sizes (nav brand, mock topbar, favicon, apple-touch-icon, og:image).
  const size = meta.height;
  const left = Math.round((meta.width - size) / 2);

  const square = () => sharp(SRC).extract({ left, top: 0, width: size, height: size });

  const targets = [
    { name: 'logo-64.png', px: 64 },     // nav brand + mock topbar (2x of 32px CSS box)
    { name: 'logo-180.png', px: 180 },   // apple-touch-icon
    { name: 'logo-32.png', px: 32 },     // favicon
    { name: 'logo-og.png', px: 630 },    // social preview (og:image / twitter:image)
  ];

  for (const t of targets) {
    await square()
      .resize(t.px, t.px, { fit: 'cover' })
      .png({ compressionLevel: 9, palette: true, quality: 90 })
      .toFile(OUT(t.name));
    console.log('wrote', t.name);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
