-- Gate 2 局部反馈：整理售货机右侧露出的壁灯边框和墙面毛边，不改售货机。
local function read_json(path)
  local f=assert(io.open(path,"rb"));local value=json.decode(f:read("*a"));f:close();return value
end
local r=read_json(assert(app.params.request))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API41 required")
assert(r.source~=r.output and not app.fs.isFile(r.output),"Refusing existing output")
assert(r.palette.art_approved==false,"Gate 2 still pending")
local pc=app.pixelColor
local allowed={}
for _,c in ipairs(r.palette.colors) do allowed[pc.rgba(c[1],c[2],c[3],c[4])]=true end
-- 直接使用候选色板已有的中性灰，收掉原边带中断续的褐色/亮灰杂点。
local edge={pc.rgba(40,41,42,255),pc.rgba(77,80,79,255)}
for _,p in ipairs(edge) do assert(allowed[p],"Missing existing edge color") end
local source=assert(app.open(r.source));local sprite=Sprite(source);source:close();app.sprite=sprite
local layer
for _,item in ipairs(sprite.layers) do if item.name=="main" then layer=item end end
assert(layer and sprite.width==541 and sprite.height==272 and #sprite.layers==10,"Surface source mismatch")
local original=Image(532,272,ColorMode.RGB);original:clear()
for _,cel in ipairs(layer.cels) do original:drawImage(cel.image,cel.position) end
local output=Image(original)
local left,right,top,bottom=185,193,142,181
local colors={}
for _,c in ipairs(r.palette.colors) do if c[4]==255 then colors[#colors+1]=c end end
local function wall_pixel(y)
  local red,green,blue=0,0,0
  for yy=y-1,y+1 do for xx=195,197 do
    local p=original:getPixel(xx,yy)
    red=red+pc.rgbaR(p);green=green+pc.rgbaG(p);blue=blue+pc.rgbaB(p)
  end end
  local best,distance
  for _,c in ipairs(colors) do
    local d=(c[1]-red/9)^2+(c[2]-green/9)^2+(c[3]-blue/9)^2
    if not distance or d<distance then best,distance=pc.rgba(c[1],c[2],c[3],255),d end
  end
  return assert(best)
end
for y=top,bottom do for x=left,right do
  -- 保持原灯体名义右边界，外侧碎亮点恢复为紧邻墙面；不烘焙新灯光。
  local value=wall_pixel(y)
  if y>=146 and y<=175 and x<=186 then value=edge[x-left+1] end
  output:drawPixel(x,y,value)
end end
local changed,alpha_changes,outside_changes=0,0,0
for it in output:pixels() do
  local old=original:getPixel(it.x,it.y);local value=it()
  assert(allowed[value],"Palette changed")
  if value~=old then
    changed=changed+1
    if it.x<left or it.x>right or it.y<top or it.y>bottom then outside_changes=outside_changes+1 end
  end
  if pc.rgbaA(value)~=pc.rgbaA(old) then alpha_changes=alpha_changes+1 end
  if it.x<185 then assert(value==old,"Lamp body/emissive face changed") end
end
assert(changed>0 and alpha_changes==0 and outside_changes==0,"Vending edge boundary violated")
layer.isEditable=true
if layer:cel(1) then sprite:deleteCel(layer,1) end
sprite:newCel(layer,1,output,Point(0,0))
sprite.data="ART09 Surface V1 / door-edge R1 / vending-right lamp edge R1 | Gate 2 pending"
sprite:saveCopyAs(r.output);sprite:close()
local f=assert(io.open(r.report,"wb"))
f:write(json.encode({ok=true,changed_layer="main",changed_pixels=changed,alpha_changes=alpha_changes,
  outside_region_changes=outside_changes,lamp_body_and_emissive_face_unchanged=true,roi={left,top,right,bottom}}));f:close()
print("ART09 VENDING EDGE PASS")
