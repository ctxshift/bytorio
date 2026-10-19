--!strict
local console=require("@console")
local gfx,data=console.gfx,console.data
local scene:console.Target
local indexed:console.Target
local tex:console.Texture
local full:console.Texture
local palette:console.Palette
local bands:console.RowTable
local mask:console.Pipeline
local overlay:console.Pipeline
local additive:console.Pipeline
local tablePipe:console.Pipeline
local ticket:console.Readback?=nil
local rows:{{palette:console.Palette,x:number,y:number}}={}
local framePixels:console.PixelBuffer
local bench=false
return {
    init=function()
        console.display(320,180)
        local stencil=gfx.target({format="stencil8",width=320,height=180})
        scene=gfx.target({format="rgba8",width=320,height=180,stencil=stencil})
        indexed=gfx.target({format="index8",width=320,height=180})
        local pixels=data.pixels("index8",2,2)
        for i,value in {1,2,3,0} do buffer.writeu8(pixels.bytes,i-1,value) end
        tex=gfx.texture({format="index8",width=2,height=2})
        gfx.upload(tex,{x=0,y=0,width=2,height=2},pixels)
        framePixels=data.pixels("rgba8",640,360)
        buffer.fill(framePixels.bytes,0,255)
        full=gfx.texture({format="rgba8",width=640,height=360})
        gfx.upload(full,{x=0,y=0,width=640,height=360},framePixels)
        local colors=buffer.create(1024)
        buffer.writeu32(colors,4,gfx.rgba(255,0,0,255));buffer.writeu32(colors,8,gfx.rgba(0,255,0,255));buffer.writeu32(colors,12,gfx.rgba(0,0,255,255))
        palette=gfx.palette(colors)
        buffer.writeu32(colors,12,gfx.rgba(255,255,0,255))
        local alternate=gfx.palette(colors)
        local lut=buffer.create(65536)
        for src=0,255 do for dst=0,255 do buffer.writeu8(lut,src*256+dst,(src+dst)%256) end end
        local table=gfx.color_table(lut)
        tablePipe=gfx.pipeline({format="index8",blend="table",color_table=table,write_mask=15})
        mask=gfx.pipeline({format="rgba8",write_mask=0,stencil={reference=1,replace_pass=true}})
        overlay=gfx.pipeline({format="rgba8",blend="over",stencil={compare="equal",reference=1,write_mask=0}})
        additive=gfx.pipeline({format="rgba8",blend="add"})
        bands=gfx.row_table(180)
        for y=0,179 do rows[y+1]={palette=if y%2==0 then palette else alternate,x=y%3,y=0} end
        gfx.write_rows(bands,0,rows)
    end,
    update=function(_dt:number)
        if ticket then
            local result=gfx.poll(ticket)
            if result then assert(data.get_pixel(result,0,0)==gfx.rgba(133,10,15,255),"readback lost submission version");ticket=nil end
        end
        bench=console.button("down")
        if bench then
            console.display(640,360)
            buffer.fill(framePixels.bytes,0,console.ticks()%256)
            gfx.upload(full,{x=0,y=0,width=640,height=360},framePixels)
            return
        end
        console.display(if console.ticks()>=10 then 640 else 320,if console.ticks()>=10 then 360 else 180)
        if console.ticks()==10 then local active=console.pointer();assert(not active,"mode switch changed the sampled pointer") end
        local color=buffer.create(4);buffer.writeu32(color,0,gfx.rgba(0,0,(console.ticks()*13)%256,255));gfx.write(palette,12,color)
        for y=0,179 do rows[y+1].x=(y+console.ticks())%3 end
        gfx.write_rows(bands,0,rows)
    end,
    draw=function()
        if bench then gfx.present(full);return end
        local p=gfx.begin_pass(indexed,{clear=true,color=1})
        gfx.bind(p,tablePipe);gfx.rect(p,0,0,16,16,2)
        gfx.bind(p,gfx.default_pipeline("index8"))
        gfx.draw(p,tex,{x=-1,y=-1,width=4,height=4},{x=16,y=0,width=8,height=8},{flip_x=true,repeat_image=true})
        gfx.end_pass(p)
        p=gfx.begin_pass(scene,{clear=true,color=gfx.rgba(10,20,30,255),clear_stencil=true})
        gfx.bind(p,mask);gfx.rect(p,10,10,40,40,gfx.rgba(255,255,255,255))
        gfx.bind(p,overlay);gfx.rect(p,0,0,80,80,gfx.rgba(255,0,0,128))
        gfx.bind(p,gfx.default_pipeline("rgba8"));gfx.clip(p,20,20,2,2);gfx.rect(p,0,0,80,80,gfx.rgba(0,255,0,255))
        gfx.clip(p,0,0,320,180);gfx.transform(p,{0,1,-1,0,60,0});gfx.rect(p,0,0,10,10,gfx.rgba(0,0,255,255))
        gfx.transform(p,{1,0,0,1,0,0});gfx.draw(p,indexed,{x=0,y=0,width=24,height=24},{x=120,y=0,width=48,height=48},{palette=palette})
        gfx.bind(p,additive);gfx.rect(p,80,0,8,8,gfx.rgba(0,0,255,64))
        gfx.bind(p,gfx.default_pipeline("rgba8"))
        console.sprite(0,180,20);console.text("PASS",180,45,console.rgb(255,255,255))
        if console.button("up") then gfx.draw(p,scene,{x=0,y=0,width=1,height=1},{x=0,y=0,width=1,height=1}) end
        gfx.end_pass(p)
        if not ticket then ticket=gfx.readback(scene,{x=10,y=10,width=2,height=2}) end
        p=gfx.begin_pass(scene);gfx.rect(p,10,10,2,2,gfx.rgba(0,255,0,255));gfx.end_pass(p)
        if console.ticks()%8>=4 and console.ticks()<10 then gfx.present(indexed,{rows=bands,repeat_image=true})
        elseif console.ticks()>=10 then
            local screen=gfx.screen();p=gfx.begin_pass(screen,{clear=true,color=console.rgb(0,0,0)})
            gfx.draw(p,scene,{x=0,y=0,width=320,height=180},{x=0,y=0,width=640,height=360});gfx.end_pass(p);gfx.present(screen)
        else gfx.present(scene) end
    end,
}
