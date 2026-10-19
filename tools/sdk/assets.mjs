import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

export function graphicsPacket(source) {
  assert.equal(source.palette?.length,16,'assets.palette must contain 16 #RRGGBB colors');
  const palette=source.palette.map(color=>{
    assert.match(color,/^#[\da-fA-F]{6}$/,'invalid palette color');
    return (0xff000000|parseInt(color.slice(5,7)+color.slice(3,5)+color.slice(1,3),16))>>>0;
  });
  assert.ok(Array.isArray(source.sprites)&&source.sprites.length>=1&&source.sprites.length<=256,'provide 1..256 sprites');
  const packet=Buffer.alloc(80+source.sprites.length*256+128*7);
  packet.writeUInt32LE(0x31584647,0);packet.writeUInt32LE(source.sprites.length,4);
  packet.writeUInt32LE(16,8);packet.writeUInt32LE(128,12);
  palette.forEach((c,i)=>packet.writeUInt32LE(c,16+i*4));
  source.sprites.forEach((rows,id)=>{
    assert.equal(rows.length,16,'sprite height must be 16');
    rows.forEach((row,y)=>{
      assert.equal(row.length,16,'sprite width must be 16');assert.match(row,/^[.\da-fA-F]+$/,'sprite pixels must be palette hex digits or .');
      for(let x=0;x<16;x++)packet[80+id*256+y*16+x]=row[x]==='.'?255:parseInt(row[x],16);
    });
  });
  for(const [char,rows] of Object.entries(source.font||{})) {
    assert.ok(char.length===1&&char.charCodeAt(0)<128,'font character must be ASCII');assert.equal(rows.length,7,'glyph height must be 7');
    rows.forEach((row,y)=>{assert.match(row,/^[01]{5}$/,'glyph row must be five binary digits');packet[80+source.sprites.length*256+char.charCodeAt(0)*7+y]=parseInt(row,2);});
  }
  return {packet,palette};
}
export async function readGraphics(path) {return graphicsPacket(JSON.parse(await readFile(path,'utf8')));}
