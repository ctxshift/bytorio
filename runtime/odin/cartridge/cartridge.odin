package cartridge

import "core:hash"
import "core:unicode/utf8"
import abi "../abi"

// PNG container v1 for the implemented 2D preview profile. All returned views
// borrow the input; callers retain it until they have copied/compiled the code.
MAX_BYTES :: 2 * 1024 * 1024
HEADER_BYTES :: 32
SDK_VERSION :: u32(256)
LUAU :: u32(1)
ODIN :: u32(2)
Cartridge :: struct { language, display: u32, title: string, code: []u8 }

be32 :: proc(b: []u8) -> u32 {return u32(b[0])<<24 | u32(b[1])<<16 | u32(b[2])<<8 | u32(b[3])}
le32 :: proc(b: []u8) -> u32 {return u32(b[0]) | u32(b[1])<<8 | u32(b[2])<<16 | u32(b[3])<<24}
le16 :: proc(b: []u8) -> u32 {return u32(b[0]) | u32(b[1])<<8}
is_png :: proc(b: []u8) -> bool {return len(b)>=8 && string(b[:8])=="\x89PNG\r\n\x1a\n"}

parse_payload :: proc(b: []u8) -> (cart: Cartridge, error: string) {
    if len(b)<HEADER_BYTES || string(b[:4])!="CART" {return {},"invalid cartridge header"}
    if le16(b[4:])!=1 || b[7]!=1 || le32(b[8:])!=SDK_VERSION || le32(b[12:])!=abi.VERSION || le32(b[28:])!=0 {
        return {},"unsupported cartridge version, SDK, ABI or profile"
    }
    cart.language=u32(b[6]); cart.display=le16(b[16:])<<16 | le16(b[18:])
    if !abi.valid_display(cart.display) {return {},"unsupported cartridge display"}
    if cart.language!=LUAU && cart.language!=ODIN {return {},"unsupported cartridge language"}
    title_size,code_size:=u64(le32(b[20:])),u64(le32(b[24:]))
    limit:=u64(abi.MAX_GAME_BYTES)
    if cart.language==LUAU {limit=256*1024}
    if title_size<1 || title_size>128 || code_size<1 || code_size>limit || u64(HEADER_BYTES)+title_size+code_size!=u64(len(b)) {
        return {},"invalid cartridge title or code length"
    }
    cart.title=string(b[HEADER_BYTES:HEADER_BYTES+int(title_size)])
    if !utf8.valid_string(cart.title) {return {},"invalid cartridge title encoding"}
    for c in transmute([]u8)cart.title {if c<32 || c==127 {return {},"invalid cartridge title"}}
    cart.code=b[HEADER_BYTES+int(title_size):]
    if cart.language==LUAU && !utf8.valid_string(string(cart.code)) {return {},"invalid Luau source encoding"}
    if cart.language==ODIN && (len(cart.code)<8 || string(cart.code[:8])!="\x00asm\x01\x00\x00\x00") {return {},"invalid cartridge Wasm module"}
    return
}

parse :: proc(b: []u8) -> (cart: Cartridge, error: string) {
    if len(b)>MAX_BYTES || !is_png(b) {return {},"invalid PNG cartridge signature or size"}
    offset:=8
    header,palette,idat,idat_ended,found:=false,false,false,false,false
    color,depth:u8
    image_bytes:u64
    for count:=0; offset<len(b) && count<4096; count+=1 {
        if len(b)-offset<12 {return {},"truncated PNG chunk"}
        size:=u64(be32(b[offset:])); end:=u64(offset)+12+size
        if end>u64(len(b)) {return {},"PNG chunk outside file"}
        kind:=string(b[offset+4:offset+8]); data:=b[offset+8:int(end)-4]
        for c in b[offset+4:offset+8] {if !(c>='A'&&c<='Z') && !(c>='a'&&c<='z') {return {},"invalid PNG chunk type"}}
        if b[offset+6]>='a' {return {},"invalid PNG reserved chunk bit"}
        if hash.crc32(b[offset+4:int(end)-4])!=be32(b[int(end)-4:]) {return {},"PNG chunk checksum mismatch"}
        if !header && kind!="IHDR" {return {},"PNG must start with IHDR"}
        if idat && kind!="IDAT" {idat_ended=true}
        switch kind {
        case "IHDR":
            if header || size!=13 {return {},"invalid PNG image header"}
            w,h:=be32(data),be32(data[4:]); depth,color=data[8],data[9]
            valid_depth:=false
            switch color {
            case 0: valid_depth=depth==1||depth==2||depth==4||depth==8||depth==16
            case 2,4,6: valid_depth=depth==8||depth==16
            case 3: valid_depth=depth==1||depth==2||depth==4||depth==8
            }
            if w==0||h==0||w>1024||h>1024||!valid_depth||data[10]!=0||data[11]!=0||data[12]>1 {return {},"unsupported PNG cover dimensions or encoding"}
            header=true
        case "PLTE":
            if palette||idat||size==0||size>768||size%3!=0||color==0||color==4 {return {},"invalid PNG palette"}
            if color==3 && size/3>u64(1<<depth) {return {},"PNG palette exceeds bit depth"}
            palette=true
        case "IDAT":
            if idat_ended || (color==3&&!palette) {return {},"invalid PNG image data order"}
            idat=true; image_bytes+=size
        case "caRt":
            if found||!idat {return {},"duplicate or misplaced cartridge chunk"}
            cart,error=parse_payload(data)
            if error!="" {return {},error}
            found=true
        case "IEND":
            if size!=0||!idat||image_bytes==0||int(end)!=len(b) {return {},"invalid PNG end chunk"}
            if !found {return {},"PNG has no cartridge payload"}
            return cart,""
        case "acTL","fcTL","fdAT": return {},"animated PNG covers are unsupported"
        case:
            if b[offset+4]>='A' && b[offset+4]<='Z' {return {},"unknown critical PNG chunk"}
        }
        offset=int(end)
    }
    return {},"missing PNG end chunk or too many chunks"
}
