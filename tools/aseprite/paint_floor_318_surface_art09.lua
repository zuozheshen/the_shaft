-- ART-09 Pass B：只整理 V3 的既有表面，不创建构图或灯光。
-- 调用方传入只读源、新输出、候选色板及固定导出矩形；不覆盖任何已有源。
local function read_json(path)
  local file=assert(io.open(path,"rb"));local value=json.decode(file:read("*a"));file:close();return value
end
local function write_json(path,value)
  local file=assert(io.open(path,"wb"));file:write(json.encode(value));file:close()
end
local request=read_json(assert(app.params.request,"Missing request"))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API 41 required")
assert(request.density==64 and request.pass=="surface","Only approved 64 px/m Surface Pass")
assert(request.source~=request.output and not app.fs.isFile(request.output),"Output must be a new native source")
assert(request.palette.art_approved==false,"Candidate must not claim Gate 2 approval")
local pc=app.pixelColor
local palette_values,allowed={},{}
for _,c in ipairs(request.palette.colors) do
  local p=pc.rgba(c[1],c[2],c[3],c[4])
  assert(not allowed[p],"Duplicate candidate palette entry")
  allowed[p]=true;palette_values[#palette_values+1]={p=p,r=c[1],g=c[2],b=c[3],a=c[4]}
end
assert(palette_values[1].p==0,"Transparent black must remain index zero")
local cache={}
local function nearest(r,g,b)
  r=math.floor(r+0.5);g=math.floor(g+0.5);b=math.floor(b+0.5)
  local key=r..","..g..","..b
  if cache[key] then return cache[key] end
  local best,distance
  for _,c in ipairs(palette_values) do
    if c.a==255 then
      local d=(c.r-r)^2+(c.g-g)^2+(c.b-b)^2
      if not distance or d<distance then best,distance=c.p,d end
    end
  end
  cache[key]=assert(best);return best
end
local function channels(p) return pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p) end
local function inside(x,y,rect) return x>=rect[1] and x<=rect[3] and y>=rect[2] and y<=rect[4] end

-- 这些固定区域对应 V3 已有门框、门把和壁灯，禁止滤波跨过物件边缘。
local door={209,139,289,271}
local lamp={173,143,190,179}
local function wall(x,y) return not inside(x,y,door) and not inside(x,y,lamp) end
local function door_paint(x,y)
  return inside(x,y,{216,147,280,263}) and not inside(x,y,{271,191,281,225})
end
local function cabinet_paint(x,y)
  return inside(x,y,{117,112,158,226}) and not inside(x,y,{120,117,153,195})
end
local function bin_paint(x,y) return inside(x,y,{26,200,50,225}) end

-- 用源图的确定邻域保留成片材质变化；不使用 random、矩形补丁或比例生成器。
local function integral(image,accept)
  local width,height=image.width,image.height
  local stride=width+1
  local red,green,blue,count={},{},{},{}
  for x=0,width do red[x]=0;green[x]=0;blue[x]=0;count[x]=0 end
  for y=0,height-1 do
    local rr,gg,bb,nn=0,0,0,0
    local row=(y+1)*stride
    red[row]=0;green[row]=0;blue[row]=0;count[row]=0
    for x=0,width-1 do
      local p=image:getPixel(x,y)
      if pc.rgbaA(p)==255 and accept(x,y) then
        local r,g,b=channels(p);rr=rr+r;gg=gg+g;bb=bb+b;nn=nn+1
      end
      local i=row+x+1;local above=i-stride
      red[i]=red[above]+rr;green[i]=green[above]+gg;blue[i]=blue[above]+bb;count[i]=count[above]+nn
    end
  end
  return function(x,y,radius)
    local x0=math.max(0,x-radius);local x1=math.min(width-1,x+radius)+1
    local y0=math.max(0,y-radius);local y1=math.min(height-1,y+radius)+1
    local a=y0*stride+x0;local b=y0*stride+x1;local c=y1*stride+x0;local d=y1*stride+x1
    local n=count[d]-count[b]-count[c]+count[a]
    if n==0 then return channels(image:getPixel(x,y)) end
    return (red[d]-red[b]-red[c]+red[a])/n,
      (green[d]-green[b]-green[c]+green[a])/n,
      (blue[d]-blue[b]-blue[c]+blue[a])/n
  end
end
local function smooth(image,accept,mode)
  local output=Image(image)
  local mean=integral(image,accept)
  for it in image:pixels() do
    local x,y,p=it.x,it.y,it()
    if pc.rgbaA(p)==255 and accept(x,y) then
      local r,g,b=channels(p)
      local r3,g3,b3=mean(x,y,1)
      local r9,g9,b9=mean(x,y,4)
      local r31,g31,b31=mean(x,y,15)
      local nr,ng,nb
      if mode=="wall" then
        nr=r*0.04+r3*0.22+r9*0.49+r31*0.25
        ng=g*0.04+g3*0.22+g9*0.49+g31*0.25
        nb=b*0.04+b3*0.22+b9*0.49+b31*0.25
        -- 门旁和编号后方是日常清理的完整墙面，不生成编号底牌。
        local distance=((x-333)/43)^2+((y-131)/25)^2
        local buffer=math.max(0,1-distance)
        nr=nr*(1-buffer*0.65)+r31*buffer*0.65
        ng=ng*(1-buffer*0.65)+g31*buffer*0.65
        nb=nb*(1-buffer*0.65)+b31*buffer*0.65
        -- 沿已有竖向板区做低对比整理，不用随机色块制造“修补”。
        local panel=(x<178 and -1 or (x>338 and 1 or 0))
        nr=nr+panel;ng=ng+panel;nb=nb+panel
      elseif mode=="ceiling" then
        nr=r*0.02+r9*0.28+r31*0.70
        ng=g*0.02+g9*0.28+g31*0.70
        nb=b*0.02+b9*0.28+b31*0.70
        -- 两条稀疏长向施工缝只说明水平面方向，不画新灯槽或受光梯度。
        if x==162 or x==378 then nr=nr-4;ng=ng-4;nb=nb-4 end
      elseif mode=="ground" then
        nr=r*0.04+r3*0.16+r9*0.80
        ng=g*0.04+g3*0.16+g9*0.80
        nb=b*0.04+b3*0.16+b9*0.80
        -- 原 48px/0.75m 拼缝仍在原坐标；只压低缝线与砖面的对比。
        local seam=(x%48==0 or y%48==0 or x%48==47 or y%48==47)
        if seam then
          nr=r*0.25+r9*0.75;ng=g*0.25+g9*0.75;nb=b*0.25+b9*0.75
        end
      else
        -- 门板与设备仅整理原有漆面；玻璃、产品、轮廓和五金留在保护区。
        nr=r*0.30+r3*0.70;ng=g*0.30+g3*0.70;nb=b*0.30+b3*0.70
      end
      output:drawPixel(x,y,nearest(nr,ng,nb))
    end
  end
  return output
end
local function structural_edges(image)
  -- 墙顶边界来自冻结的 y=2.6m：main 像素 y≈103；只是已有结构的表面收口。
  for y=103,105 do
    for x=0,image.width-1 do
      if wall(x,y) then image:drawPixel(x,y,nearest(139,142,143)) end
    end
  end
  for y=106,107 do
    for x=0,image.width-1 do
      if wall(x,y) then image:drawPixel(x,y,nearest(165,168,168)) end
    end
  end
  for _,x in ipairs({178,338}) do
    for y=108,image.height-1 do
      local label_buffer=(x==338 and y>=114 and y<=151)
      if wall(x,y) and not label_buffer then
        local r,g,b=channels(image:getPixel(x,y))
        image:drawPixel(x,y,nearest(r-6,g-6,b-6))
      end
    end
  end
end
local function save_crop(image,path,rect,scale)
  local width,height=rect[3],rect[4]
  local crop=Image(width*scale,height*scale,ColorMode.RGB);crop:clear()
  for y=0,height-1 do for x=0,width-1 do
    local value=image:getPixel(rect[1]+x,rect[2]+y)
    for yy=0,scale-1 do for xx=0,scale-1 do crop:drawPixel(x*scale+xx,y*scale+yy,value) end end
  end end
  assert(crop:saveAs(path))
end
local function image_from_layer(layer,geometry)
  local image=Image(geometry.width,geometry.height,ColorMode.RGB);image:clear()
  for _,cel in ipairs(layer.cels) do image:drawImage(cel.image,cel.position) end
  return image
end
local source=assert(app.open(request.source))
assert(source.width==541 and source.height==272 and #source.frames==1 and #source.layers==10,"V3 source identity mismatch")
local sprite=Sprite(source);source:close();app.sprite=sprite
local palette=Palette(#palette_values)
for index,c in ipairs(palette_values) do palette:setColor(index-1,Color{r=c.r,g=c.g,b=c.b,a=c.a}) end
sprite:setPalette(palette)
local stats={}
local crops={main={296,110,88,104},ceiling={130,32,160,112},ground={144,24,192,144}}
for _,geometry in ipairs(request.layers) do
  local id=geometry.id
  local layer
  for _,candidate in ipairs(sprite.layers) do if candidate.name==id then layer=candidate end end
  assert(layer and not layer.isReference,"Missing environment layer "..id)
  local original=image_from_layer(layer,geometry)
  local result=Image(original)
  if id=="main" then
    result=smooth(original,wall,"wall")
    local door_result=smooth(original,door_paint,"metal")
    for y=147,263 do for x=216,280 do if door_paint(x,y) then result:drawPixel(x,y,door_result:getPixel(x,y)) end end end
    structural_edges(result)
  elseif id=="far" then result=smooth(original,function()return true end,"wall")
  elseif id=="ceiling" then result=smooth(original,function()return true end,"ceiling")
  elseif id=="ground" then result=smooth(original,function()return true end,"ground")
  elseif id=="mid_left" then result=smooth(original,cabinet_paint,"metal")
  elseif id=="mid_right" then result=smooth(original,bin_paint,"metal") end
  local changed,alpha_changes=0,0
  for it in result:pixels() do
    local old=original:getPixel(it.x,it.y);local new=it()
    assert(allowed[new],"Output outside unchanged V3 color set")
    assert(pc.rgbaA(new)==0 or pc.rgbaA(new)==255,"Non-binary alpha")
    if old~=new then changed=changed+1 end
    if pc.rgbaA(old)~=pc.rgbaA(new) then alpha_changes=alpha_changes+1 end
  end
  assert(alpha_changes==0,"Surface edit must preserve every alpha pixel")
  if id=="front_left" or id=="front_right" then assert(changed==0,"Front layers must remain byte-equivalent pixels") end
  layer.isEditable=true;layer.opacity=255;layer.blendMode=BlendMode.NORMAL
  if layer:cel(1) then sprite:deleteCel(layer,1) end
  sprite:newCel(layer,1,result,Point(0,0))
  if crops[id] then
    for _,scale in ipairs({1,4}) do
      save_crop(original,request.preview_directory.."/before-"..id.."-crop-"..scale.."x.png",crops[id],scale)
      save_crop(result,request.preview_directory.."/after-"..id.."-crop-"..scale.."x.png",crops[id],scale)
    end
  end
  stats[#stats+1]={id=id,width=result.width,height=result.height,changed_pixels=changed,alpha_changes=alpha_changes}
end
for _,layer in ipairs(sprite.layers) do
  if layer.name=="REFERENCE" or layer.name=="GUIDES" then layer.isVisible=false;layer.isEditable=false end
end
sprite.data="ART09 Surface candidate v1 | base V3 | 64 px/m | Gate 2 pending | no lighting"
sprite:saveCopyAs(request.output);sprite:close()
write_json(request.report,{ok=true,pass="surface",source=request.source,output=request.output,palette=request.palette.id,
  palette_entries=#palette_values,palette_approved=false,lighting_changed=false,layers=stats,crops=crops})
print("ART09 SURFACE AUTHOR PASS")
