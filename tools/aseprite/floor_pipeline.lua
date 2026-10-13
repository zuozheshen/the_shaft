-- The Shaft floor pipeline V1. Batch only; existing source files are never saved.
local IDS = {"far","main","mid_left","mid_right","ground","front_left","front_right"}
local EXPECTED = {REFERENCE=true, GUIDES=true}
for _, id in ipairs(IDS) do EXPECTED[id] = true end

local function read_json(path)
  local f = assert(io.open(path, "rb"), "Cannot read request")
  local value = json.decode(f:read("*a")); f:close(); return value
end
local function write_json(path, value)
  local f = assert(io.open(path, "wb"), "Cannot write report")
  f:write(json.encode(value)); f:close()
end
local request = read_json(assert(app.params["request"], "Missing request"))
local pc = app.pixelColor
local function rgba(c) return pc.rgba(c[1],c[2],c[3],c[4]) end
local function components(p) return {pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p),pc.rgbaA(p)} end
local function pixel_key(p) return string.format("%02x%02x%02x%02x",pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p),pc.rgbaA(p)) end

local function palette()
  local p = Palette(#request.palette.colors)
  for i, c in ipairs(request.palette.colors) do p:setColor(i-1, Color{r=c[1],g=c[2],b=c[3],a=c[4]}) end
  return p
end
local allowed = {}
for i, c in ipairs(request.palette.colors) do
  local value = rgba(c)
  assert(not allowed[value], "Duplicate palette color")
  allowed[value] = i -- One-based; indexed zero is transparent.
end
assert(rgba(request.palette.colors[1]) == 0, "Palette index 0 must be transparent black")

local function describe(sprite)
  local layers = {}
  for _, layer in ipairs(sprite.layers) do
    layers[#layers+1] = {name=layer.name,visible=layer.isVisible,editable=layer.isEditable,
      reference=layer.isReference,group=layer.isGroup,opacity=layer.opacity,cels=#layer.cels}
  end
  return {canvas={sprite.width,sprite.height},frames=#sprite.frames,color_mode=tostring(sprite.colorMode),
    palette_size=#sprite.palettes[1],layers=layers}
end

local function extract(sprite, id, geometry)
  local layer
  for _, candidate in ipairs(sprite.layers) do if candidate.name == id then layer = candidate end end
  assert(layer, "Missing layer "..id)
  local image = Image(geometry.width, geometry.height, ColorMode.RGB)
  image:clear()
  for _, cel in ipairs(layer.cels) do
    assert(cel.frame.frameNumber == 1 and cel.opacity == 255, "Cel frame/opacity invalid: "..id)
    for it in cel.image:pixels() do
      local value = it()
      local x, y = it.x + cel.position.x, it.y + cel.position.y
      local a = pc.rgbaA(value)
      assert(a == 0 or a == 255, "Non-binary alpha in "..id.." at "..x..","..y)
      if a == 0 then
        assert(value == 0, "Transparent pixel must be RGBA(0,0,0,0): "..id)
      else
        assert(x >= 0 and y >= 0 and x < geometry.width and y < geometry.height,
          "Content outside fixed rectangle: "..id.." at "..x..","..y)
        assert(allowed[value], "Off-palette pixel in "..id.." at "..x..","..y.." = "..pixel_key(value))
        image:drawPixel(x,y,value)
      end
    end
  end
  local transparent, opaque, colors = 0, 0, {}
  for it in image:pixels() do
    local p = it()
    if pc.rgbaA(p) == 0 then transparent = transparent + 1 else opaque = opaque + 1 end
    colors[pixel_key(p)] = true
  end
  if id == "far" or id == "ground" then assert(transparent == 0, id.." must be continuous opaque fallback") end
  local count = 0; for _ in pairs(colors) do count = count + 1 end
  return image, {id=id,width=image.width,height=image.height,opaque=opaque,transparent=transparent,color_count=count}
end

local function validate(sprite)
  assert(sprite.colorMode == ColorMode.RGB, "Master source must be RGB")
  assert(#sprite.frames == 1, "Only one frame is allowed")
  assert(sprite.width == request.canvas[1] and sprite.height == request.canvas[2], "Wrong Sprite canvas")
  assert(#sprite.layers == 9, "Exactly nine top-level layers required")
  assert(#sprite.palettes == 1 and #sprite.palettes[1] == #request.palette.colors, "Wrong source palette")
  for i, c in ipairs(request.palette.colors) do
    assert(sprite.palettes[1]:getColor(i-1).rgbaPixel == rgba(c), "Wrong palette entry "..(i-1))
  end
  local names = {}
  for _, layer in ipairs(sprite.layers) do
    assert(EXPECTED[layer.name] and not names[layer.name], "Unexpected/duplicate layer: "..layer.name)
    assert(not layer.isGroup and not layer.isTilemap and layer.isImage, "Only image layers supported")
    names[layer.name] = true
    if layer.name == "REFERENCE" then
      assert(layer.isReference, "REFERENCE must be a native reference layer")
    elseif layer.name ~= "GUIDES" then
      assert(not layer.isReference and not layer.isBackground, "Formal layer must support alpha")
      assert(layer.opacity == 255 and layer.blendMode == BlendMode.NORMAL, "Layer opacity/blend invalid")
    end
  end
  local images, stats = {}, {}
  for _, id in ipairs(IDS) do
    images[id], stats[#stats+1] = extract(sprite,id,request.layers[id])
  end
  return images, stats
end

-- World-sized calibration rectangles, re-rasterized for every density; no scaled master.
local function rect(image, g, x0, y0, x1, y1, color_index)
  local left = g.origin[1] - g.size[1]/2
  local top = g.origin[2] + g.size[2]/2
  local px0 = math.floor((x0-left)/g.size[1]*image.width)
  local px1 = math.ceil((x1-left)/g.size[1]*image.width)-1
  local py0, py1
  if g.id == "ground" then
    local back = g.origin[3] - g.size[2]/2
    py0 = math.floor((y0-back)/g.size[2]*image.height)
    py1 = math.ceil((y1-back)/g.size[2]*image.height)-1
  else
    py0 = math.floor((top-y1)/g.size[2]*image.height)
    py1 = math.ceil((top-y0)/g.size[2]*image.height)-1
  end
  local p = rgba(request.palette.colors[color_index])
  for y=math.max(0,py0),math.min(image.height-1,py1) do
    for x=math.max(0,px0),math.min(image.width-1,px1) do image:drawPixel(x,y,p) end
  end
end

local function structure(id, g)
  local image = Image(g.width,g.height,ColorMode.RGB); image:clear()
  local function r(x0,y0,x1,y1,c) rect(image,g,x0,y0,x1,y1,c) end
  if id == "far" then
    image:clear(rgba(request.palette.colors[3]))
    r(-4.225,0,4.225,0.22,2)
    for x=-4,4,1 do r(x,0.22,x+0.035,4.145,4) end
  elseif id == "main" then
    image:clear(rgba(request.palette.colors[5]))
    -- Alpha test opening exposes the opaque far layer, not an invented 3D room.
    r(-1.32,0.2,1.32,1.68,1)
    r(-3.1,1.25,-2.5,2.25,1); r(2.5,1.25,3.1,2.25,1)
    r(-1.4,0.1,-1.32,1.7,3); r(1.32,0.1,1.4,1.7,3)
    r(-1.4,1.68,1.4,1.76,3)
    -- Blank carrier only: FLOOR 318 remains the shared runtime Label3D.
    r(-0.975,1.76,0.975,2.41,2)
    for y=0,4,0.5 do r(-4.15,y,4.15,y+0.018,4) end
    for x=-4,4,0.5 do r(x,0,x+0.018,4.2,4) end
    r(-0.94,1.795,0.94,2.375,3)
  elseif id == "mid_left" or id == "mid_right" then
    local side = id == "mid_left" and -1 or 1
    local lo, hi = side == -1 and -3.4 or 1.45, side == -1 and -1.45 or 3.48
    r(lo,0,hi,2.5,3); r(lo,2.5,hi,2.57,4)
    local inner = side == -1 and -1.45 or 1.37
    r(inner,0,inner+0.08,2.57,7)
    -- Small calibrated marker and narrow stripes reveal density/minification.
    local x = side == -1 and -1.58 or 1.51
    r(x,1.2,x+0.12,1.36,8)
    for y=0.4,2.2,0.12 do r(lo,y,lo+0.25,y+0.018,5) end
  elseif id == "ground" then
    image:clear(rgba(request.palette.colors[3]))
    for z=-3.5,0,0.5 do r(-4.225,z,4.225,z+0.035,4) end
    for x=-4,4,0.5 do r(x,-3.7,x+0.025,0.05,4) end
    r(-1.02,-0.25,1.02,-0.19,8)
  else
    local lo = g.origin[1]-g.size[1]/2
    local hi = g.origin[1]+g.size[1]/2
    r(lo,0,hi,2.4,2)
    -- Real binary cutouts and a stepped edge, for Alpha Scissor inspection.
    r(lo+0.1,0.5,hi-0.1,1.0,1)
    r(lo+0.08,1.05,hi-0.08,1.18,1)
    r(lo,1.85,lo+0.12,2.1,1)
    r(hi-0.04,0,hi,2.4,7)
  end
  return image
end

local function create_template()
  assert(not app.fs.isFile(request.output_source), "Refusing existing source")
  local sprite = Sprite(request.canvas[1],request.canvas[2],ColorMode.RGB)
  sprite.useLayerUuids = false
  sprite:setPalette(palette())
  sprite.data = "STRUCTURE TEST ONLY; pixel density and residential art palette are not approved."
  for i,id in ipairs(IDS) do
    local layer = i == 1 and sprite.layers[1] or sprite:newLayer()
    layer.name = id
    if layer:cel(1) then sprite:deleteCel(layer,1) end
    sprite:newCel(layer,1,structure(id,request.layers[id]),Point(0,0))
    local slice = sprite:newSlice(Rectangle(0,0,request.layers[id].width,request.layers[id].height))
    slice.name = id
  end
  local guides = sprite:newLayer(); guides.name = "GUIDES"
  local guide_image = Image(sprite.width,sprite.height,ColorMode.RGB); guide_image:clear()
  for _,id in ipairs(IDS) do
    local g = request.layers[id]
    for x=0,g.width-1 do guide_image:drawPixel(x,0,rgba(request.palette.colors[8])); guide_image:drawPixel(x,g.height-1,rgba(request.palette.colors[8])) end
    for y=0,g.height-1 do guide_image:drawPixel(0,y,rgba(request.palette.colors[8])); guide_image:drawPixel(g.width-1,y,rgba(request.palette.colors[8])) end
  end
  sprite:newCel(guides,1,guide_image,Point(0,0)); guides.isVisible=false; guides.isEditable=false
  app.sprite = sprite
  app.command.NewLayer{ name="REFERENCE",reference=true,ask=false,top=true }
  local reference = app.layer
  assert(reference.isReference, "Native reference creation failed")
  reference.isVisible=false; reference.isEditable=false
  validate(sprite)
  sprite:saveAs(request.output_source)
  local result = describe(sprite); sprite:close(); return result
end

local function run()
  assert(app.apiVersion >= 41 and not app.isUIAvailable, "Batch Lua API 41 required")
  if request.action == "CreateTemplate" then
    return {ok=true,template=create_template()}
  end
  local sprite = assert(app.open(request.source), "Cannot open saved source")
  if request.action == "Inspect" then
    local info = describe(sprite); sprite:close(); return {ok=true,inspection=info}
  end
  if request.action == "PrepareReferenceCopy" then
    assert(not app.fs.isFile(request.output_source), "Refusing existing copy")
    validate(sprite)
    local ref
    for _,layer in ipairs(sprite.layers) do if layer.name=="REFERENCE" then ref=layer end end
    local reference_image = Image{fromFile=request.reference}
    assert(reference_image, "Cannot read reference")
    ref.isEditable=true
    if ref:cel(1) then sprite:deleteCel(ref,1) end
    sprite:newCel(ref,1,reference_image,Point(0,0))
    ref.isVisible=false; ref.isEditable=false
    sprite:saveCopyAs(request.output_source)
    local info = describe(sprite); sprite:close(); return {ok=true,reference_copy=info}
  end
  local images, stats = validate(sprite)
  if request.action == "Export" then
    for _,id in ipairs(IDS) do
      local original = images[id]
      -- Exact RGB -> index lookup -> RGBA. No nearest color or lossy quantization.
      local indexed = Image(original.width,original.height,ColorMode.INDEXED)
      for it in indexed:pixels() do it(allowed[original:getPixel(it.x,it.y)]-1) end
      local output = Image(original.width,original.height,ColorMode.RGB)
      for it in output:pixels() do it(rgba(request.palette.colors[indexed:getPixel(it.x,it.y)+1])) end
      local filename = app.fs.joinPath(request.output_directory,id..".png")
      assert(output:saveAs(filename), "PNG save failed: "..id)
      local roundtrip = Image{fromFile=filename}
      assert(roundtrip and roundtrip.width==output.width and roundtrip.height==output.height and roundtrip.colorMode==ColorMode.RGB,"PNG roundtrip dimensions/mode")
      for it in roundtrip:pixels() do assert(it()==original:getPixel(it.x,it.y),"Lossy PNG/index roundtrip in "..id) end
    end
    -- Asset inspection preview only; this does not reproduce Godot camera perspective.
    for _,layer in ipairs(sprite.layers) do layer.isVisible = layer.name~="REFERENCE" and layer.name~="GUIDES" end
    local preview = Image(sprite); assert(preview:saveAs(request.preview), "Preview save failed")
  else
    assert(request.action == "Validate", "Unsupported action")
  end
  local info = describe(sprite); sprite:close()
  return {ok=true,inspection=info,pngs=stats,exact_indexed_rgba_roundtrip=request.action=="Export"}
end

local ok, report = pcall(run)
if not ok then report={ok=false,error=tostring(report)} end
report.request_id = request.request_id
write_json(request.report,report)
if ok then print("FLOOR_PIPELINE_OK "..request.request_id)
else io.stderr:write("FLOOR_PIPELINE_FAIL | "..report.error.."\n"); error(report.error) end
