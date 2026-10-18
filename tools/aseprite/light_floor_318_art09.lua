-- ART-09 Pass C：在已批准 Surface 上烘焙固定基础光影；不改变轮廓或空间结构。
local function read_json(path)
  local f=assert(io.open(path,"rb"));local value=json.decode(f:read("*a"));f:close();return value
end
local r=read_json(assert(app.params.request,"Missing request"))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API41 required")
assert(r.pass=="lighting" and r.density==64 and r.surface_gate==2,"Approved Surface required")
assert(r.source~=r.output and not app.fs.isFile(r.output),"Refusing existing native output")
assert(r.palette.art_approved==false,"Gate 3 candidate cannot claim approval")
local pc=app.pixelColor
local colors,allowed,cache={},{},{}
for _,c in ipairs(r.palette.colors) do
  local p=pc.rgba(c[1],c[2],c[3],c[4]);assert(not allowed[p],"Duplicate color")
  allowed[p]=true
  if c[4]==255 then colors[#colors+1]={p=p,r=c[1],g=c[2],b=c[3]} end
end
assert(#r.palette.colors==127 and allowed[0],"Unchanged 127-color set required")
local function nearest(red,green,blue)
  red=math.floor(red+0.5);green=math.floor(green+0.5);blue=math.floor(blue+0.5)
  local key=red..","..green..","..blue
  if cache[key] then return cache[key] end
  local best,distance
  for _,c in ipairs(colors) do
    local d=(c.r-red)^2+(c.g-green)^2+(c.b-blue)^2
    if not distance or d<distance then best,distance=c.p,d end
  end
  cache[key]=assert(best);return best
end
local function clamp(value,low,high) return math.max(low,math.min(high,value)) end
local function inside(x,y,a,b,c,d) return x>=a and x<=c and y>=b and y<=d end
local function bell(x,y,rx,ry) return math.exp(-((x/rx)^2+(y/ry)^2)) end
local function world(geometry,x,y)
  local size,origin=geometry.size,geometry.origin
  local wx=origin[1]+((x+0.5)/geometry.width-0.5)*size[1]
  if geometry.id=="ground" then
    return wx,origin[3]+((y+0.5)/geometry.height-0.5)*size[2]
  elseif geometry.id=="ceiling" then
    return wx,origin[3]-( (y+0.5)/geometry.height-0.5)*size[2]
  end
  return wx,origin[2]+(0.5-(y+0.5)/geometry.height)*size[2]
end
local function lighting(geometry,x,y)
  local id=geometry.id
  local wx,wy=world(geometry,x,y)
  if id=="front_left" or id=="front_right" then return 1 end
  if id=="main" or id=="far" then
    local height=clamp(wy/2.6,0,1)
    local overhead=bell(wx+0.3,wy-2.6,2.7,1.8)
    local factor=0.86+0.14*height+0.035*overhead-0.045*(math.abs(wx)/4.2)^2
    factor=factor-0.055*math.exp(-(wy/0.15)^2)
    if id=="main" then
      -- 壁灯发光面与门把保留；受光渐变只描述原有面，不增添灯具或光斑道具。
      if inside(x,y,178,147,183,174) or inside(x,y,271,191,281,225) then return 1 end
      if inside(x,y,210,140,287,270) then
        factor=0.86+0.15*height
        -- 已有门洞内侧窄缝略沉，保持 Gate 2 收整的像素边界。
        if x==215 or x==282 or y==145 then factor=factor-0.10 end
      else
        factor=factor+0.025*bell(wx+1.32,wy-1.68,0.7,0.65)
      end
    end
    return clamp(factor,0.74,1.06)
  elseif id=="ground" then
    -- ground 是水平平面：在世界 X/Z 中计算宽受光和既有物件脚下的接触压暗。
    local z=wy
    local factor=0.84+0.17*bell(wx+0.3,z+1.5,3.0,2.5)
    factor=factor-0.085*math.exp(-((z+3.10)/0.14)^2)
    factor=factor-0.11*bell(wx+1.25,z+2.35,0.44,0.11)
    factor=factor-0.11*bell(wx-1.42,z+2.45,0.28,0.10)
    return clamp(factor,0.70,1.02)
  elseif id=="ceiling" then
    local z=wy
    return clamp(1.04+0.07*bell(wx+0.3,z+0.65,2.8,2.4)
      -0.07*math.exp(-((z+3.10)/0.16)^2)-0.04*(math.abs(wx)/4.2)^2,0.93,1.11)
  elseif id=="mid_left" then
    -- 商品玻璃和付款模块不改；顶缘/机身/右侧只接收同一宽缓基础明暗。
    if inside(x,y,120,117,153,195) then return 1 end
    local factor=0.88+0.15*clamp(wy/1.8,0,1)
    if x>=158 then factor=factor-0.10 end
    if y<=115 then factor=factor+0.025 end
    return clamp(factor,0.76,1.06)
  elseif id=="mid_right" then
    -- 垃圾桶开口保持深黑；上沿稍亮，右侧比正面略沉。
    if inside(x,y,28,187,47,196) then return 1 end
    local factor=0.88+0.14*clamp(wy/0.8,0,1)
    if x>=48 then factor=factor-0.07 end
    if y<=185 then factor=factor+0.06 end
    return clamp(factor,0.78,1.08)
  end
  error("Unexpected layer "..id)
end
local source=assert(app.open(r.source))
assert(source.width==541 and source.height==272 and #source.frames==1 and #source.layers==10,"Source identity mismatch")
local sprite=Sprite(source);source:close();app.sprite=sprite
local stats={}
for _,geometry in ipairs(r.layers) do
  local layer
  for _,item in ipairs(sprite.layers) do if item.name==geometry.id then layer=item end end
  assert(layer and not layer.isReference,"Missing environment layer")
  local original=Image(geometry.width,geometry.height,ColorMode.RGB);original:clear()
  for _,cel in ipairs(layer.cels) do original:drawImage(cel.image,cel.position) end
  local output=Image(original)
  local changed,alpha_changes,min_factor,max_factor=0,0,1,1
  for it in output:pixels() do
    local old=original:getPixel(it.x,it.y)
    if pc.rgbaA(old)==255 then
      local factor=lighting(geometry,it.x,it.y)
      min_factor=math.min(min_factor,factor);max_factor=math.max(max_factor,factor)
      if math.abs(factor-1)>0.000001 then
        it(nearest(pc.rgbaR(old)*factor,pc.rgbaG(old)*factor,pc.rgbaB(old)*factor))
      end
    end
    assert(allowed[it()],"Palette changed")
    if pc.rgbaA(it())~=pc.rgbaA(old) then alpha_changes=alpha_changes+1 end
    if it()~=old then changed=changed+1 end
  end
  assert(alpha_changes==0,"Alpha silhouette changed")
  if geometry.id=="front_left" or geometry.id=="front_right" then assert(changed==0,"Foreground changed") end
  layer.isEditable=true
  if layer:cel(1) then sprite:deleteCel(layer,1) end
  sprite:newCel(layer,1,output,Point(0,0))
  stats[#stats+1]={id=geometry.id,changed_pixels=changed,alpha_changes=alpha_changes,min_factor=min_factor,max_factor=max_factor}
end
sprite.data="ART09 Lighting V1 candidate | approved Surface 4b488a4 | baked fixed lighting | Gate 3 pending"
sprite:saveCopyAs(r.output);sprite:close()
local f=assert(io.open(r.report,"wb"))
f:write(json.encode({ok=true,pass="lighting",source=r.source,output=r.output,source_gate=2,
  palette_id=r.palette.id,palette_entries=#r.palette.colors,art_approved=false,runtime_tint="white",energy_multiplier=1,layers=stats}));f:close()
print("ART09 LIGHTING AUTHOR PASS")
