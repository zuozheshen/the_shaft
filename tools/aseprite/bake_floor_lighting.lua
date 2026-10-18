-- 离线固定光照合成：Surface、具名遮罩、光照参数分别输入，运行时只接收最终贴图。
local function read_json(path)
  local f=assert(io.open(path,"rb"),"Cannot read JSON: "..tostring(path));local v=json.decode(f:read("*a"));f:close();return v
end
local function write_json(path,v) local f=assert(io.open(path,"wb"));f:write(json.encode(v));f:close() end
local r=read_json(assert(app.params.request,"Missing request"))
local pc=app.pixelColor
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function run()
  assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API41 required")
  assert(r.source~=r.output and not app.fs.isFile(r.output),"Refusing existing output")
  assert(r.surface_gate==2 and r.palette.art_approved==false,"Approved Surface / unapproved candidate required")
  local recipe=read_json(r.recipe);local mask_data=read_json(r.masks)
  assert(recipe.schema_version==1 and mask_data.schema_version==1,"Unsupported lighting schema")
  assert(recipe.density==r.density and finite(r.density) and r.density>0,"Density mismatch")
  local masks=assert(mask_data.masks);local colors,allowed,cache={},{},{}
  assert(#r.palette.colors>=2 and #r.palette.colors<=256,"Indexed output palette size")
  for _,c in ipairs(r.palette.colors) do
    assert(#c==4,"RGBA entry required")
    for _,n in ipairs(c) do assert(finite(n) and n%1==0 and n>=0 and n<=255,"Invalid RGBA component") end
    assert(c[4]==0 or c[4]==255,"Binary alpha required")
    local p=pc.rgba(c[1],c[2],c[3],c[4]);assert(not allowed[p],"Duplicate palette color");allowed[p]=true
    if c[4]==255 then colors[#colors+1]={p=p,r=c[1],g=c[2],b=c[3]} end
  end
  assert(pc.rgba(table.unpack(r.palette.colors[1]))==0 and #colors>0,"Transparent index zero required")
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
  local function check_mask(name)
    assert(type(name)=="string" and name:match("^[%w_%-]+$"),"Unsafe mask name")
    local m=assert(masks[name],"Unknown mask: "..name)
    if m.kind=="rect_union" then
      assert(m.space=="pixel" and #m.rects>0,"Pixel rectangles required")
      for _,rect in ipairs(m.rects) do
        assert(#rect==4,"Invalid mask rectangle")
        for _,n in ipairs(rect) do assert(finite(n) and n%1==0,"Integer rectangle required") end
        assert(rect[1]<=rect[3] and rect[2]<=rect[4],"Reversed rectangle")
      end
    elseif m.kind=="ellipse" then
      assert(m.space=="world" and #m.center==2 and #m.radius==2,"World ellipse required")
      for i=1,2 do assert(finite(m.center[i]) and finite(m.radius[i]) and m.radius[i]>0,"Invalid ellipse") end
    elseif m.kind=="line_second" then
      assert(m.space=="world" and finite(m.center) and finite(m.radius) and m.radius>0,"Invalid line mask")
    else
      assert(m.kind=="x_squared" and m.space=="world" and finite(m.radius) and m.radius>0,"Unknown mask kind")
    end
  end
  local function check_model(model)
    assert(finite(model.base),"Finite base required")
    if model.height then
      local h=model.height;assert(finite(h.origin) and finite(h.range) and h.range>0 and finite(h.gain),"Invalid height gradient")
    end
    for _,field in ipairs(model.fields or {}) do check_mask(field.mask);assert(finite(field.gain),"Invalid field gain") end
  end
  -- 全部引用先过门：无效配置不能产生一半完成的候选。
  local seen={}
  assert(#r.layers>0,"Geometry required")
  for _,g in ipairs(r.layers) do
    assert(type(g.id)=="string" and g.id:match("^[%w_%-]+$") and not seen[g.id],"Invalid/duplicate layer")
    seen[g.id]=true
    assert(finite(g.width) and finite(g.height) and g.width%1==0 and g.height%1==0 and g.width>0 and g.height>0,"Invalid dimensions")
    for i=1,2 do assert(finite(g.size[i]) and g.size[i]>0,"Invalid plane size") end
    for i=1,3 do assert(finite(g.origin[i]),"Invalid plane origin") end
    local layer=assert(recipe.layers[g.id],"Missing layer recipe: "..g.id)
    assert(layer.coordinates=="vertical" or layer.coordinates=="ground" or layer.coordinates=="ceiling","Unknown coordinates")
    for _,name in ipairs(layer.protect or {}) do check_mask(name);assert(masks[name].kind=="rect_union","Protection must be binary") end
    if not layer.passthrough then
      check_model(layer.model)
      assert(finite(layer.clamp[1]) and finite(layer.clamp[2]) and layer.clamp[1]>=0 and layer.clamp[1]<=layer.clamp[2],"Invalid factor clamp")
      for _,region in ipairs(layer.regions or {}) do
        check_mask(region.mask);assert(masks[region.mask].kind=="rect_union","Region must be binary");check_model(region.model)
      end
    end
  end
  for id in pairs(recipe.layers) do assert(seen[id],"Recipe layer missing geometry: "..id) end
  local function coverage(name,x,y,wx,second)
    local m=masks[name]
    if m.kind=="rect_union" then
      for _,rect in ipairs(m.rects) do if x>=rect[1] and y>=rect[2] and x<=rect[3] and y<=rect[4] then return 1 end end
      return 0
    elseif m.kind=="ellipse" then return math.exp(-(((wx-m.center[1])/m.radius[1])^2+((second-m.center[2])/m.radius[2])^2))
    elseif m.kind=="line_second" then return math.exp(-((second-m.center)/m.radius)^2)
    else return (math.abs(wx)/m.radius)^2 end
  end
  local function evaluate(model,x,y,wx,second)
    local v=model.base
    if model.height then local h=model.height;v=v+h.gain*clamp((second-h.origin)/h.range,0,1) end
    for _,field in ipairs(model.fields or {}) do v=v+field.gain*coverage(field.mask,x,y,wx,second) end
    return v
  end
  local source=assert(app.open(r.source))
  assert(source.width==r.canvas[1] and source.height==r.canvas[2] and #source.frames==1,"Source canvas/frame mismatch")
  local sprite=Sprite(source);source:close();app.sprite=sprite
  local stats={}
  for _,g in ipairs(r.layers) do
    assert(g.width<=sprite.width and g.height<=sprite.height,"Layer rectangle exceeds source")
    local node
    for _,item in ipairs(sprite.layers) do if item.name==g.id then node=item end end
    assert(node and not node.isReference and not node.isGroup,"Missing paint layer")
    local original=Image(g.width,g.height,ColorMode.RGB);original:clear()
    for _,cel in ipairs(node.cels) do original:drawImage(cel.image,cel.position) end
    local out=Image(original);local layer=recipe.layers[g.id];local used={}
    for _,name in ipairs(layer.protect or {}) do used[name]=true end
    if not layer.passthrough then
      for _,f in ipairs(layer.model.fields or {}) do used[f.mask]=true end
      for _,region in ipairs(layer.regions or {}) do used[region.mask]=true;for _,f in ipairs(region.model.fields or {}) do used[f.mask]=true end end
    end
    local previews={}
    if r.mask_preview_directory then for name in pairs(used) do previews[name]=Image(g.width,g.height,ColorMode.RGB) end end
    local changed,alpha_changes,protected,min_factor,max_factor=0,0,0,1,1
    for it in out:pixels() do
      local x,y,old=it.x,it.y,original:getPixel(it.x,it.y)
      local wx=g.origin[1]+((x+0.5)/g.width-0.5)*g.size[1]
      local second=g.origin[2]+(0.5-(y+0.5)/g.height)*g.size[2]
      if layer.coordinates=="ground" then second=g.origin[3]+((y+0.5)/g.height-0.5)*g.size[2]
      elseif layer.coordinates=="ceiling" then second=g.origin[3]-((y+0.5)/g.height-0.5)*g.size[2] end
      for name,img in pairs(previews) do local gray=math.floor(clamp(coverage(name,x,y,wx,second),0,1)*255+0.5);img:drawPixel(x,y,pc.rgba(gray,gray,gray,255)) end
      if pc.rgbaA(old)==255 then
        local keep=false
        for _,name in ipairs(layer.protect or {}) do if coverage(name,x,y,wx,second)>0 then keep=true end end
        local factor=1
        if keep then protected=protected+1
        elseif not layer.passthrough then
          local model=layer.model
          for _,region in ipairs(layer.regions or {}) do if coverage(region.mask,x,y,wx,second)>0 then model=region.model end end
          factor=clamp(evaluate(model,x,y,wx,second),layer.clamp[1],layer.clamp[2])
        end
        min_factor=math.min(min_factor,factor);max_factor=math.max(max_factor,factor)
        if math.abs(factor-1)>0.000001 then it(nearest(pc.rgbaR(old)*factor,pc.rgbaG(old)*factor,pc.rgbaB(old)*factor)) end
        if keep then assert(it()==old,"Protected pixels changed") end
      end
      assert(allowed[it()],"Pixel outside supplied palette")
      if pc.rgbaA(it())~=pc.rgbaA(old) then alpha_changes=alpha_changes+1 end
      if it()~=old then changed=changed+1 end
    end
    assert(alpha_changes==0 and (not layer.passthrough or changed==0),"Silhouette/passthrough changed")
    for name,img in pairs(previews) do
      local path=app.fs.joinPath(r.mask_preview_directory,g.id.."-"..name..".png")
      assert(not app.fs.isFile(path) and img:saveAs(path),"Mask preview must be a new file")
    end
    node.isEditable=true
    if node:cel(1) then sprite:deleteCel(node,1) end
    sprite:newCel(node,1,out,Point(0,0))
    stats[#stats+1]={id=g.id,changed_pixels=changed,alpha_changes=alpha_changes,protected_pixels=protected,min_factor=min_factor,max_factor=max_factor}
  end
  sprite.data="Offline lighting candidate | "..recipe.id.." | human review pending"
  sprite:saveCopyAs(r.output);sprite:close()
  return {ok=true,recipe=recipe.id,masks=mask_data.id,source=r.source,output=r.output,palette_entries=#r.palette.colors,art_approved=false,layers=stats}
end
local ok,result=pcall(run)
if not ok then result={ok=false,error=tostring(result)} end
write_json(assert(r.report),result)
if not ok then io.stderr:write("FLOOR LIGHTING BAKE FAIL | "..result.error.."\n");error(result.error) end
print("FLOOR LIGHTING BAKE PASS")
