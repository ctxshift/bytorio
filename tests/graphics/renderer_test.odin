package graphics_test

import "core:testing"
import r "../../runtime/odin/resources"
import t "../../sdk/odin/resource"
import gfx "../../sdk/odin/gfx"
import data "../../sdk/odin/data"
import abi "../../runtime/odin/abi"

submit :: proc(test:^testing.T,registry:^r.Registry) {
    t.end();testing.expect(test,t.commit()!=0,t.error)
    testing.expect(test,r.submit(registry,t.packet[:int(t.packet_size())],display=abi.DISPLAY_LOW),registry.error)
    testing.expect(test,t.ack(registry.sequence))
}

software_composition :: proc(test:^testing.T) {
    registry:r.Registry;defer r.close(&registry)
    testing.expect(test,r.reset(&registry,31));testing.expect(test,t.configure(31))
    t.begin(0)
    stencil:=gfx.target({format=.Stencil8,width=320,height=180})
    target:=gfx.target({format=.RGBA8,width=320,height=180,stencil=stencil})
    indexed:=gfx.target({format=.Index8,width=320,height=180})
    texture:=gfx.texture({.Index8,2,2})
    pixels:=data.pixels(.Index8,2,2);defer data.free_pixels(&pixels)
    pixels.bytes[0]=1;pixels.bytes[1]=2;pixels.bytes[2]=3;pixels.bytes[3]=0
    gfx.upload(texture,{0,0,2,2},pixels)
    colors:[256]u32;colors[1]=0xff0000ff;colors[2]=0xff00ff00;colors[3]=0xffff0000
    palette:=gfx.palette(colors[:]);colors[3]=0xff00ffff;alternate:=gfx.palette(colors[:])
    lut:[65536]u8
    for src in 0..<256 {for dst in 0..<256 {lut[src*256+dst]=u8((src+dst)&255)}}
    table:=gfx.color_table(lut[:])
    indexed_pipe:=gfx.pipeline({format=.Index8,blend=.Table,color_table=table,write_mask=u32(15)})
    mask:=gfx.pipeline({format=.RGBA8,write_mask=u32(0),stencil={reference=1,replace_pass=true}})
    overlay:=gfx.pipeline({format=.RGBA8,blend=.Over,stencil={compare=.Equal,reference=1,write_mask=u32(0)}})
    rows:=gfx.row_table(180);row_data:[180]gfx.Row
    for &row,y in row_data {row={palette if y%2==0 else alternate,i32(y%3),0}}
    gfx.write_rows(rows,0,row_data[:])
    submit(test,&registry)
    t.begin_draw(0)
    p:=gfx.begin_pass(indexed,{clear=true,color=1})
    gfx.bind(p,indexed_pipe);gfx.rect(p,0,0,16,16,2)
    gfx.bind(p,gfx.default_pipeline(.Index8))
    gfx.draw(p,texture,{-1,-1,4,4},{16,0,8,8},{flip_x=true,repeat_image=true})
    gfx.end_pass(p)
    p=gfx.begin_pass(target,{clear=true,color=gfx.rgba(10,20,30,255),clear_stencil=true})
    gfx.bind(p,mask);gfx.rect(p,10,10,40,40,0xffffffff)
    gfx.bind(p,overlay);gfx.rect(p,0,0,80,80,gfx.rgba(255,0,0,128))
    gfx.bind(p,gfx.default_pipeline(.RGBA8));gfx.clip(p,20,20,2,2);gfx.rect(p,0,0,80,80,0xff00ff00)
    gfx.clip(p,0,0,320,180);gfx.transform(p,{0,1,-1,0,60,0});gfx.rect(p,0,0,10,10,0xffff0000)
    gfx.transform(p,{1,0,0,1,0,0});gfx.draw(p,indexed,{0,0,16,16},{120,0,16,16},{palette=palette})
    gfx.end_pass(p)
    ticket:=gfx.readback(target,{10,10,2,2})
    p=gfx.begin_pass(target);gfx.rect(p,10,10,2,2,0xff00ff00);gfx.end_pass(p)
    gfx.present(target)
    submit(test,&registry)
    testing.expect_value(test,registry.output[0],u32(0xff1e140a))
    testing.expect_value(test,registry.output[22*320+22],u32(0xff0f0a85))
    testing.expect_value(test,registry.output[20*320+20],u32(0xff00ff00))
    testing.expect_value(test,registry.output[5*320+55],u32(0xffff0000))
    testing.expect_value(test,registry.output[5*320+49],u32(0xff1e140a))
    testing.expect_value(test,registry.output[5*320+60],u32(0xff1e140a))
    testing.expect_value(test,registry.output[5*320+125],u32(0xffff0000))
    testing.expect_value(test,registry.output[10*320+10],u32(0xff00ff00))
    testing.expect_value(test,registry.slots[(indexed.id&65535)-1].data[16],u8(3))
    t.mailbox_size=u32(r.mailbox(&registry,t.packet[:]))
    t.begin(1)
    result,ready:=gfx.poll(ticket)
    testing.expect(test,ready)
    testing.expect(test,r.u32le(result.bytes,0)==0xff0f0a85,"readback observes its submission, before later writes")
    data.free_pixels(&result)
    submit(test,&registry)
    t.begin_draw(1);gfx.present(indexed,{rows=rows,repeat_image=true});submit(test,&registry)
    testing.expect_value(test,registry.output[0],u32(0xffff0000))
    testing.expect_value(test,registry.output[320],u32(0xff00ffff))
    previous:=make([]u32,len(registry.output));defer delete(previous);copy(previous,registry.output)
    old:=r.u32le(registry.slots[(target.id&65535)-1].data,0)
    t.begin_draw(1);p=gfx.begin_pass(target);gfx.rect(p,0,0,10,10,0xffffffff)
    gfx.draw(p,target,{0,0,1,1},{0,0,1,1});gfx.end_pass(p);gfx.present(target);t.end();_=t.commit()
    args_at:=int(r.u32le(t.packet[:],44)+r.u32le(t.packet[:],64+12))
    r.put32(t.packet[:],args_at,indexed_pipe.id)
    testing.expect(test,!r.submit(&registry,t.packet[:int(t.packet_size())],display=abi.DISPLAY_LOW),"pipeline/target format mismatch is rejected")
    r.put32(t.packet[:],args_at,0)
    testing.expect(test,!r.submit(&registry,t.packet[:int(t.packet_size())],display=abi.DISPLAY_LOW),"feedback rejected after earlier mutations")
    testing.expect_value(test,r.u32le(registry.slots[(target.id&65535)-1].data,0),old)
    for pixel,i in previous {testing.expect_value(test,registry.output[i],pixel)}
    // Validate persistent attachment ownership independently from draw hazards.
    destroy_packet:[96]u8
    copy(destroy_packet[:64],t.packet[:64]);r.put32(destroy_packet[:],16,2);r.put32(destroy_packet[:],24,1)
    r.put32(destroy_packet[:],32,1);r.put32(destroy_packet[:],40,32);r.put32(destroy_packet[:],44,96);r.put32(destroy_packet[:],48,0)
    r.put32(destroy_packet[:],64,13|32<<16);r.put32(destroy_packet[:],72,stencil.id)
    testing.expect(test,!r.submit(&registry,destroy_packet[:]),"live target pins its stencil attachment")
    // A rejected cartridge is terminated; release its local sealed test packet.
    t.sealed=false
}


sampling_masks_and_copy :: proc(test:^testing.T) {
    registry:r.Registry;defer r.close(&registry)
    testing.expect(test,r.reset(&registry,32));testing.expect(test,t.configure(32));t.begin(0)
    target:=gfx.target({format=.RGBA8,width=320,height=180});destination:=gfx.target({format=.RGBA8,width=320,height=180})
    source:=gfx.texture({.RGBA8,2,2});pixels:=data.pixels(.RGBA8,2,2);defer data.free_pixels(&pixels)
    data.set_pixel(pixels,0,0,0xff0000ff);data.set_pixel(pixels,1,0,0xff00ff00);data.set_pixel(pixels,0,1,0xffff0000);data.set_pixel(pixels,1,1,0xffffffff)
    gfx.upload(source,{0,0,2,2},pixels)
    indexed:=gfx.texture({.Index8,2,1});indices:=data.pixels(.Index8,2,1);defer data.free_pixels(&indices)
    indices.bytes[1]=1;gfx.upload(indexed,{0,0,2,1},indices)
    colors:[256]u32;colors[0]=0xff00ffff;colors[1]=0xff0000ff;palette:=gfx.palette(colors[:])
    transparent:=gfx.pipeline({format=.RGBA8,blend=.Over,transparent_index=u32(0)})
    mask:=gfx.pipeline({format=.RGBA8,write_mask=u32(1)});add:=gfx.pipeline({format=.RGBA8,blend=.Add})
    submit(test,&registry);t.begin_draw(0)
    p:=gfx.begin_pass(target,{clear=true,color=0xff1e140a})
    gfx.rect(p,0.5,0.5,1,1,0xffffffff)
    gfx.transform(p,{-1,0,0,1,5,0});gfx.rect(p,0.5,0.5,1,1,0xff0000ff);gfx.transform(p,{1,0,0,1,0,0})
    gfx.draw(p,source,{0,0,2,2},{0,10,4,4},{flip_x=true})
    gfx.draw(p,source,{0,0,1,1},{20,10,1,1},{tint=gfx.rgba(255,255,255,128)})
    gfx.bind(p,mask);gfx.rect(p,80,0,1,1,0xff0000ff)
    gfx.bind(p,add);gfx.rect(p,90,0,1,1,gfx.rgba(0,0,255,64))
    gfx.bind(p,transparent);gfx.draw(p,indexed,{0,0,2,1},{10,0,2,1},{palette=palette})
    gfx.end_pass(p);gfx.copy(target,destination,{0,0,320,180},0,0);gfx.present(destination);submit(test,&registry)
    testing.expect_value(test,registry.output[0],u32(0xffffffff));testing.expect_value(test,registry.output[1],u32(0xff1e140a))
    testing.expect_value(test,registry.output[3],u32(0xff1e140a));testing.expect_value(test,registry.output[4],u32(0xff0000ff))
    testing.expect_value(test,registry.output[10],u32(0xff1e140a));testing.expect_value(test,registry.output[11],u32(0xff0000ff))
    testing.expect_value(test,registry.output[10*320],u32(0xff00ff00));testing.expect_value(test,registry.output[10*320+2],u32(0xff0000ff))
    testing.expect_value(test,registry.output[12*320],u32(0xffffffff));testing.expect_value(test,registry.output[12*320+2],u32(0xffff0000))
    testing.expect_value(test,registry.output[10*320+20],u32(0xff000080))
    testing.expect_value(test,registry.output[80],u32(0xff1e14ff));testing.expect_value(test,registry.output[90],u32(0xff5e140a))
    // Game-owned CPU copy must preserve overlapping rows as well as pixels.
    data.copy_pixels(pixels,0,1,pixels,0,0,2,1)
    testing.expect_value(test,data.get_pixel(pixels,0,1),u32(0xff0000ff))
    testing.expect_value(test,data.get_pixel(pixels,1,1),u32(0xff00ff00))
    before_bytes:=registry.bytes;before_packets:=registry.stats.packet_bytes;before_pixel:=registry.output[0]
    t.begin_draw(0);gfx.present(destination);gfx.present(destination);t.end();_=t.commit()
    packet:=t.packet[:int(t.packet_size())]
    testing.expect(test,!r.submit(&registry,packet,budget=registry.bytes+len(packet),display=abi.DISPLAY_LOW),"presentation allocation is charged before publication")
    testing.expect(test,!r.submit(&registry,packet,display=abi.DISPLAY_LOW),"failure after first presentation does not publish its private output")
    testing.expect_value(test,registry.bytes,before_bytes);testing.expect_value(test,registry.stats.packet_bytes,before_packets);testing.expect_value(test,registry.output[0],before_pixel)
    t.sealed=false
}


bounded_completion_delivery :: proc(test:^testing.T) {
    registry:r.Registry;defer r.close(&registry)
    testing.expect(test,r.reset(&registry,33));testing.expect(test,t.configure(33));t.begin(0)
    large:=gfx.target({format=.RGBA8,width=1024,height=256});small:=gfx.target({format=.RGBA8,width=320,height=180})
    submit(test,&registry);t.begin_draw(0)
    a:=gfx.readback(large,{0,0,1024,256});b:=gfx.readback(large,{0,0,1024,256});c:=gfx.readback(small,{0,0,2,2});gfx.present(small);submit(test,&registry)
    for tick in 1..=3 {
        t.mailbox_size=u32(r.mailbox(&registry,t.packet[:]))
        testing.expect_value(test,r.u32le(t.packet[:],4),u32(1))
        testing.expect(test,t.mailbox_size<=r.MAILBOX_CAPACITY)
        t.begin(u64(tick))
        pending:=b if tick==1 else (c if tick==2 else gfx.Readback{})
        if pending.id!=0 {_,ready:=gfx.poll(pending);testing.expect(test,!ready,"excess result stays pending")}
        result,ready:=gfx.poll(a if tick==1 else (b if tick==2 else c))
        testing.expect(test,ready);data.free_pixels(&result);submit(test,&registry)
    }
    t.begin_draw(3)
    for _ in 0..<5 {_=gfx.readback(small,{0,0,1,1})};gfx.present(small);t.end();_=t.commit()
    before:=registry.bytes
    testing.expect(test,!r.submit(&registry,t.packet[:int(t.packet_size())],display=abi.DISPLAY_LOW),"fifth outstanding readback is rejected atomically")
    testing.expect_value(test,registry.bytes,before)
    t.sealed=false
}

@(test)
graphics_conformance :: proc(test:^testing.T) {
    software_composition(test)
    sampling_masks_and_copy(test)
    bounded_completion_delivery(test)
    registry:r.Registry;defer r.close(&registry)
    testing.expect(test,r.reset(&registry,34,1));testing.expect(test,t.configure(34));t.begin(0)
    _=gfx.target({format=.RGBA8,width=1,height=1});t.end();_=t.commit()
    testing.expect(test,!r.submit(&registry,t.packet[:int(t.packet_size())]),"v1 negotiation does not silently enable v2 graphics")
    testing.expect_value(test,registry.bytes,0)
    t.sealed=false
}
