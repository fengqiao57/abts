const { nativeImage, app } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const png = nativeImage.createFromPath(path.join(__dirname, '../assets/logo.png'))
  .resize({ width: 256, height: 256 }).toPNG();
const ico = Buffer.alloc(22);
ico.writeUInt16LE(1, 2); ico.writeUInt16LE(1, 4);
ico[6] = 0; ico[7] = 0;
ico.writeUInt16LE(1, 10); ico.writeUInt16LE(32, 12);
ico.writeUInt32LE(png.length, 14); ico.writeUInt32LE(22, 18);
fs.writeFileSync(path.join(__dirname, '../assets/app.ico'), Buffer.concat([ico, png]));
app.quit();
