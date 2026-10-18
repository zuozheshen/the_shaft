-- #76 R3：仅归并售货机外框亮边，保留玻璃/商品/付款区、alpha和其他图层。
local function read_json(path)
  local f=assert(io.open(path,"rb"));local value=json.decode(f:read("*a"));f:close();return value
end
local r=read_json(assert(app.params.request))
local pc=app.pixelColor
local function run()
  assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API41 required")
  assert(r.source~=r.output and not app.fs.isFile(r.output),"Refusing existing output")
  assert(r.palette.art_approved==false,"Candidate approval must remain pending")
  local allowed={}
  for _,c in ipairs(r.palette.colors) do allowed[pc.rgba(table.unpack(c))]=true end
  local dark=pc.rgba(40,41,42,255)
  local body=pc.rgba(53,54,56,255)
  local edge=pc.rgba(61,64,61,255)
  local top=pc.rgba(95,96,94,255)
  for _,p in ipairs({dark,body,edge,top}) do assert(allowed[p],"Existing gray required") end
  local source=assert(app.open(r.source));local sprite=Sprite(source);source:close();app.sprite=sprite
  assert(sprite.width==541 and sprite.height==272 and #sprite.layers==10 and #sprite.frames==1,"R3 native layout mismatch")
  local layer
  for _,node in ipairs(sprite.layers) do if node.name=="mid_left" then layer=node end end
  assert(layer and not layer.isReference,"Missing vending plane")
  local old=Image(164,230,ColorMode.RGB);old:clear()
  for _,cel in ipairs(layer.cels) do old:drawImage(cel.image,cel.position) end
  local out=Image(old)
  local function rim(x,y)
    return (x>=115 and x<=157 and y>=110 and y<=111)
      or (x>=114 and x<=116 and y>=113 and y<=225)
      or (x>=158 and x<=159 and y>=113 and y<=225)
  end
  -- 原外轮廓不扩张；长边采用少量一致灰阶，停止逐点碎高光。
  for it in out:pixels() do
    local x,y,p=it.x,it.y,it()
    if pc.rgbaA(p)==255 and rim(x,y) then
      local value=body
      if y==110 then value=top
      elseif y==111 or x==116 then value=edge
      elseif x==114 or x==159 then value=dark end
      it(value)
    end
  end
  local changed,alpha_changes,outside_changes,protected_changes=0,0,0,0
  local before_colors,after_colors={},{}
  for it in out:pixels() do
    local x,y,value=it.x,it.y,it();local previous=old:getPixel(x,y)
    assert(allowed[value],"Pixel outside approved color set")
    if rim(x,y) and pc.rgbaA(previous)==255 then before_colors[previous]=true;after_colors[value]=true end
    if value~=previous then
      changed=changed+1
      if not rim(x,y) then outside_changes=outside_changes+1 end
      if x>=120 and x<=153 and y>=117 and y<=195 then protected_changes=protected_changes+1 end
    end
    if pc.rgbaA(value)~=pc.rgbaA(previous) then alpha_changes=alpha_changes+1 end
  end
  local function count(values) local n=0;for _ in pairs(values) do n=n+1 end;return n end
  assert(changed>0 and alpha_changes==0 and outside_changes==0 and protected_changes==0,"Vending boundary violated")
  assert(count(after_colors)<=4 and count(after_colors)<count(before_colors),"Rim not simplified")
  layer.isEditable=true
  if layer:cel(1) then sprite:deleteCel(layer,1) end
  sprite:newCel(layer,1,out,Point(0,0));sprite.data="ART09 Darker R3 / simplified vending rim | Gate 3 pending"
  sprite:saveCopyAs(r.output);sprite:close()
  return {ok=true,layer="mid_left",changed_pixels=changed,alpha_changes=alpha_changes,
    outside_roi_changes=outside_changes,protected_changes=protected_changes,
    rim_colors_before=count(before_colors),rim_colors_after=count(after_colors),
    rectangles={{115,110,157,111},{114,113,116,225},{158,113,159,225}}}
end
local ok,result=pcall(run)
if not ok then result={ok=false,error=tostring(result)} end
local f=assert(io.open(r.report,"wb"));f:write(json.encode(result));f:close()
if not ok then io.stderr:write("ART09 R3 RIM FAIL | "..result.error.."\n");error(result.error) end
print("ART09 R3 RIM PASS")
