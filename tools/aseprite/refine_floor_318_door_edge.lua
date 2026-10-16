-- Gate 2 人工反馈：只整理既有门框外沿，不改门板、门洞位置或其他表面。
local function read_json(path)
  local f=assert(io.open(path,"rb"));local value=json.decode(f:read("*a"));f:close();return value
end
local r=read_json(assert(app.params.request))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API41 required")
assert(r.source~=r.output and not app.fs.isFile(r.output),"Refusing existing output")
assert(r.palette.art_approved==false,"Gate 2 still pending")
local pc=app.pixelColor
local colors,allowed={},{}
for _,c in ipairs(r.palette.colors) do
  local p=pc.rgba(c[1],c[2],c[3],c[4]);allowed[p]=true
  if c[4]==255 then colors[#colors+1]={p=p,r=c[1],g=c[2],b=c[3]} end
end
local function nearest(red,green,blue)
  local best,distance
  for _,c in ipairs(colors) do
    local d=(c.r-red)^2+(c.g-green)^2+(c.b-blue)^2
    if not distance or d<distance then best,distance=c.p,d end
  end
  return assert(best)
end
local source=assert(app.open(r.source));local sprite=Sprite(source);source:close();app.sprite=sprite
local main
for _,layer in ipairs(sprite.layers) do if layer.name=="main" then main=layer end end
assert(main and sprite.width==541 and sprite.height==272 and #sprite.layers==10,"Surface source mismatch")
local original=Image(532,272,ColorMode.RGB);original:clear()
for _,cel in ipairs(main.cels) do original:drawImage(cel.image,cel.position) end
local output=Image(original)
-- 采用原门框的名义边界；外围两三像素只去掉散乱灰白毛边，不扩大门洞。
local left,right,top,bottom=210,287,140,270
local function wall_pixel(x,y)
  local red,green,blue,count=0,0,0,0
  local sx=x<left and left-7 or (x>right and right+7 or x)
  local sy=y<top and top-6 or y
  for yy=math.max(0,sy-1),math.min(original.height-1,sy+1) do
    for xx=math.max(0,sx-1),math.min(original.width-1,sx+1) do
      local p=original:getPixel(xx,yy)
      red=red+pc.rgbaR(p);green=green+pc.rgbaG(p);blue=blue+pc.rgbaB(p);count=count+1
    end
  end
  return nearest(red/count,green/count,blue/count)
end
for y=top-3,bottom do for x=left-3,right+3 do
  if x<left or x>right or y<top then output:drawPixel(x,y,wall_pixel(x,y)) end
end end
-- 连续的深灰外缘、窄金属面和内侧暗缝，避免用模糊/抗锯齿隐藏像素。
local rim=nearest(54,57,59)
local face=nearest(69,73,76)
local reveal=nearest(24,27,29)
local join=nearest(35,38,40)
for y=top,bottom do for x=left,right do
  local d=math.min(x-left,right-x,y-top)
  if d==0 then output:drawPixel(x,y,rim)
  elseif d<=3 then output:drawPixel(x,y,face)
  elseif d==4 then output:drawPixel(x,y,rim)
  elseif d==5 then output:drawPixel(x,y,reveal)
  elseif d==6 then output:drawPixel(x,y,join) end
end end
-- 同时整理原门槛的三像素边带，避免只修两侧而留下底缘的碎亮点。
for x=left+6,right-6 do
  output:drawPixel(x,bottom-3,reveal)
  output:drawPixel(x,bottom-2,face)
  output:drawPixel(x,bottom-1,face)
end
for x=left,right do output:drawPixel(x,bottom,rim) end
local changed,alpha_changes,outside_changes=0,0,0
for it in output:pixels() do
  local old=original:getPixel(it.x,it.y);local value=it()
  assert(allowed[value],"Palette changed")
  if value~=old then
    changed=changed+1
    if it.x<left-3 or it.x>right+3 or it.y<top-3 or it.y>bottom then outside_changes=outside_changes+1 end
  end
  if pc.rgbaA(old)~=pc.rgbaA(value) then alpha_changes=alpha_changes+1 end
  -- 门扇主体与把手逐像素保留；最后三行属于上述已有门槛边带。
  if it.x>=217 and it.x<=280 and it.y>=147 and it.y<=266 then assert(value==old,"Door leaf/handle changed") end
end
assert(alpha_changes==0 and outside_changes==0,"Door-only boundary violated")
main.isEditable=true
if main:cel(1) then sprite:deleteCel(main,1) end
sprite:newCel(main,1,output,Point(0,0))
sprite.data="ART09 Surface V1 / door-edge R1 | Gate 2 pending | only main door perimeter"
sprite:saveCopyAs(r.output);sprite:close()
local f=assert(io.open(r.report,"wb"))
f:write(json.encode({ok=true,changed_layer="main",changed_pixels=changed,alpha_changes=alpha_changes,
  outside_region_changes=outside_changes,door_leaf_and_handle_unchanged=true,roi={left-3,top-3,right+3,bottom},
  edge_colors={rim=string.format("%08x",rim),face=string.format("%08x",face),reveal=string.format("%08x",reveal),join=string.format("%08x",join)}}));f:close()
print("ART09 DOOR EDGE PASS")
