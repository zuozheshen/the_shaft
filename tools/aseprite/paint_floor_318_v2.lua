-- 318 residential V2 native-pixel reconstruction. Reference is never sampled.
-- Approved 64 px/m and 20 colors; existing source is read-only, output must be new.
local function read_json(path)
  local f=assert(io.open(path,"rb")); local value=json.decode(f:read("*a")); f:close(); return value
end
local r=read_json(assert(app.params["request"]))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API 41 required")
assert(not app.fs.isFile(r.output),"Refusing existing authored source")
assert(r.palette.art_approved and #r.palette.colors==20 and r.density==64,"Approval mismatch")
local pc=app.pixelColor
local colors={}
for i,c in ipairs(r.palette.colors) do colors[i-1]=pc.rgba(c[1],c[2],c[3],c[4]) end
local I={CLEAR=0,INK=1,SHADOW=2,DARK_STEEL=3,STEEL=4,MID_STEEL=5,
  CONCRETE_DARK=6,CONCRETE_SHADOW=7,CONCRETE=8,CONCRETE_LIGHT=9,
  OFF_WHITE=10,CHALK=11,GREY_GREEN_DARK=12,GREY_GREEN_LIGHT=13,
  GLASS_DARK=14,GLASS_LIGHT=15,STENCIL=16,SLATE=17,WARM_GREY=18,LAMP=19}
local function px(g,x,y)
  local u=(x-(g.origin[1]-g.size[1]/2))/g.size[1]*g.width
  local v
  if g.id=="ground" then
    v=(y-(g.origin[3]-g.size[2]/2))/g.size[2]*g.height
  else v=(g.origin[2]+g.size[2]/2-y)/g.size[2]*g.height end
  return math.floor(u+0.5),math.floor(v+0.5)
end
local function put(im,x,y,index)
  if x>=0 and y>=0 and x<im.width and y<im.height then im:drawPixel(x,y,colors[index]) end
end
local function pixel_rect(im,x0,y0,x1,y1,index)
  x0=math.max(0,math.floor(x0));x1=math.min(im.width-1,math.floor(x1))
  y0=math.max(0,math.floor(y0));y1=math.min(im.height-1,math.floor(y1))
  for y=y0,y1 do for x=x0,x1 do put(im,x,y,index) end end
end
local function rect(im,g,x0,y0,x1,y1,index)
  local a,b=px(g,x0,y0); local c,d=px(g,x1,y1)
  pixel_rect(im,math.min(a,c),math.min(b,d),math.max(a,c)-1,math.max(b,d)-1,index)
end
local function line(im,g,x0,y0,x1,y1,index)
  local a,b=px(g,x0,y0); local c,d=px(g,x1,y1)
  local dx=math.abs(c-a);local sx=a<c and 1 or -1
  local dy=-math.abs(d-b);local sy=b<d and 1 or -1;local err=dx+dy
  while true do
    put(im,a,b,index);if a==c and b==d then break end
    local e=2*err;if e>=dy then err=err+dy;a=a+sx end
    if e<=dx then err=err+dx;b=b+sy end
  end
end
local function ellipse(im,g,x,y,rx,ry,index)
  local a,b=px(g,x-rx,y-ry);local c,d=px(g,x+rx,y+ry)
  local left,right=math.min(a,c),math.max(a,c);local top,bottom=math.min(b,d),math.max(b,d)
  local cx=(left+right)/2;local cy=(top+bottom)/2;local wx=math.max(1,(right-left)/2);local wy=math.max(1,(bottom-top)/2)
  for py=top,bottom do for q=left,right do if ((q-cx)/wx)^2+((py-cy)/wy)^2<=1 then put(im,q,py,index) end end end
end
local function polygon(im,g,points,index)
  local pp={};local miny,maxy=100000,-100000
  for _,p in ipairs(points) do local a,b=px(g,p[1],p[2]);pp[#pp+1]={a,b};miny=math.min(miny,b);maxy=math.max(maxy,b) end
  for y=math.max(0,miny),math.min(im.height-1,maxy) do
    local hits={}
    for i=1,#pp do local a=pp[i];local b=pp[i%#pp+1]
      if (a[2]<=y and b[2]>y) or (b[2]<=y and a[2]>y) then hits[#hits+1]=a[1]+(y-a[2])*(b[1]-a[1])/(b[2]-a[2]) end
    end
    table.sort(hits)
    for i=1,#hits-1,2 do pixel_rect(im,math.ceil(hits[i]),y,math.floor(hits[i+1]),y,index) end
  end
end
-- All surfaces are deliberate solid regions. No random wear/patch generator.
local function concrete(im,g)
  im:clear(colors[I.CONCRETE])
  rect(im,g,-5,0.02,5,0.15,I.CONCRETE_DARK)
  -- Broad beam face/underside: texture shading only, no geometry or lighting change.
  rect(im,g,-5,2.30,5,2.58,I.CONCRETE_DARK)
  rect(im,g,-5,2.30,5,2.37,I.MID_STEEL)
  rect(im,g,-5,2.58,5,4.3,I.CONCRETE_SHADOW)
  -- A few casting seams, using the adjacent concrete shade. No bolt-hole dots.
  line(im,g,-0.30,0.16,-0.30,2.28,I.CONCRETE_SHADOW)
  line(im,g,1.10,0.16,1.10,2.28,I.CONCRETE_SHADOW)
  line(im,g,-4,2.24,4,2.24,I.CONCRETE_SHADOW)
end
local function door(im,g)
  local x0,x1=-1.24,-0.35
  rect(im,g,x0-0.07,0.01,x1+0.07,2.04,I.CONCRETE_DARK)
  rect(im,g,x0-0.04,0.03,x1+0.045,2.025,I.SHADOW)
  rect(im,g,x0,0.035,x1,1.99,I.DARK_STEEL)
  rect(im,g,x0+0.035,0.07,x1-0.025,1.965,I.DARK_STEEL)
  line(im,g,x0-0.04,0.03,x0-0.04,2.025,I.STEEL)
  line(im,g,x0,1.99,x1,1.99,I.STEEL)
  -- Narrow real alpha at the recessed jamb exposes the far fallback.
  rect(im,g,x1+0.005,0.07,x1+0.025,1.98,I.CLEAR)
  ellipse(im,g,(x0+x1)/2,1.42,0.020,0.020,I.INK)
  rect(im,g,x1-0.105,0.82,x1-0.065,1.00,I.SHADOW)
  rect(im,g,x1-0.165,0.915,x1-0.055,0.95,I.CONCRETE_LIGHT)
  rect(im,g,x1+0.10,1.04,x1+0.20,1.30,I.DARK_STEEL)
  rect(im,g,x1+0.125,1.23,x1+0.175,1.25,I.STEEL)
  rect(im,g,x1+0.13,1.095,x1+0.17,1.13,I.CONCRETE_LIGHT)
end
local function vending(im,g)
  local x0,x1=-1.61,-0.91
  -- One compact freestanding box; all visible pixels stay outside central +/-0.85.
  polygon(im,g,{{x0,0.045},{x0+0.095,0.02},{x1,0.02},{x1,1.80},
    {x0+0.095,1.80},{x0,1.85}},I.DARK_STEEL)
  polygon(im,g,{{x0,0.045},{x0+0.095,0.02},{x0+0.095,1.80},{x0,1.85}},I.SHADOW)
  polygon(im,g,{{x0,1.85},{x0+0.095,1.80},{x1,1.80},{x1-0.095,1.85}},I.STEEL)
  line(im,g,x0+0.095,0.02,x0+0.095,1.80,I.STEEL)
  rect(im,g,-1.475,0.45,-1.065,1.71,I.GLASS_DARK)
  rect(im,g,-1.45,0.48,-1.09,1.685,I.GLASS_DARK)
  line(im,g,-1.45,0.49,-1.45,1.68,I.GLASS_LIGHT)
  -- Four quiet product shelves: three coherent bottle silhouettes each.
  local tones={I.GREY_GREEN_DARK,I.WARM_GREY,I.SLATE}
  for row=0,3 do
    local y=0.55+row*0.27
    rect(im,g,-1.455,y-0.035,-1.085,y-0.015,I.STEEL)
    for col=0,2 do
      local x=-1.425+col*0.11
      local tone=tones[(row+col)%3+1]
      rect(im,g,x,y,x+0.067,y+0.13,tone)
      rect(im,g,x+0.018,y+0.13,x+0.052,y+0.17,tone)
      rect(im,g,x+0.013,y+0.065,x+0.057,y+0.082,I.MID_STEEL)
    end
  end
  rect(im,g,-1.035,1.33,-0.945,1.46,I.INK)
  rect(im,g,-1.02,1.35,-0.96,1.43,I.GLASS_LIGHT)
  for row=0,3 do for col=0,2 do
    local x=-1.03+col*0.026
    local y=1.09-row*0.045
    rect(im,g,x,y,x+0.014,y+0.022,I.STEEL)
  end end
  rect(im,g,-1.01,0.79,-0.967,0.86,I.SHADOW)
  line(im,g,-0.99,0.80,-0.99,0.85,I.STEEL)
  rect(im,g,-1.415,0.18,-1.12,0.33,I.SHADOW)
  line(im,g,-1.39,0.22,-1.15,0.22,I.STEEL)
  rect(im,g,x0+0.05,0.00,x1,0.035,I.INK)
end
local function bin(im,g)
  local x0,x1=1.20,1.65
  polygon(im,g,{{x0,0.025},{x1,0.025},{x1,0.76},{x0+0.065,0.79},{x0,0.735}},I.STEEL)
  polygon(im,g,{{x0,0.025},{x0+0.065,0.00},{x0+0.065,0.79},{x0,0.735}},I.DARK_STEEL)
  polygon(im,g,{{x0+0.065,0.79},{x1,0.76},{x1-0.06,0.81},{x0+0.01,0.82}},I.MID_STEEL)
  rect(im,g,x0+0.11,0.57,x1-0.065,0.69,I.SHADOW)
  line(im,g,x0+0.11,0.69,x1-0.065,0.69,I.CONCRETE_DARK)
  line(im,g,x0+0.075,0.04,x0+0.075,0.73,I.MID_STEEL)
  rect(im,g,x0+0.055,0.00,x1,0.035,I.SHADOW)
end
local function paint(im,g)
  if g.id=="far" then
    concrete(im,g)
    -- Single left door recess only; no second doorway hidden in the fallback.
    rect(im,g,-1.39,0.01,-0.24,2.08,I.SHADOW)
  elseif g.id=="main" then
    concrete(im,g)
    -- Quiet side wall returns, with large contiguous tonal regions.
    rect(im,g,-4.2,0.15,-2.18,2.30,I.CONCRETE_SHADOW)
    rect(im,g,2.18,0.15,4.2,2.30,I.CONCRETE_SHADOW)
    rect(im,g,-2.28,0.15,-2.18,2.30,I.CONCRETE_DARK)
    rect(im,g,2.18,0.15,2.28,2.30,I.CONCRETE_DARK)
    door(im,g)
    -- No plaque and no baked digits: the shared Label3D paints the number.
    -- A simple utilitarian light, with no radiating stripes or scattered light pixels.
    rect(im,g,-0.33,2.63,0.33,2.77,I.SHADOW)
    rect(im,g,-0.285,2.645,0.285,2.755,I.CHALK)
    rect(im,g,-0.22,2.66,-0.035,2.74,I.LAMP)
    rect(im,g,0.035,2.66,0.22,2.74,I.LAMP)
  elseif g.id=="mid_left" then
    vending(im,g)
  elseif g.id=="mid_right" then
    bin(im,g)
  elseif g.id=="ground" then
    -- Strictly one colour over the complete footprint: no grid, mats, wear or highlights.
    im:clear(colors[I.CONCRETE])
  elseif g.id=="front_left" or g.id=="front_right" then
    local left=g.origin[1]-g.size[1]/2
    local right=g.origin[1]+g.size[1]/2
    local lo=g.origin[2]-g.size[2]/2
    local hi=g.origin[2]+g.size[2]/2
    rect(im,g,left,lo,right,hi,I.CONCRETE_DARK)
    rect(im,g,left+0.025,lo,right-0.025,hi,I.CONCRETE_SHADOW)
    if g.id=="front_left" then
      rect(im,g,right-0.075,lo,right,hi,I.DARK_STEEL)
      rect(im,g,left,lo,left+0.06,lo+0.12,I.CLEAR)
    else
      rect(im,g,left,lo,left+0.075,hi,I.DARK_STEEL)
      rect(im,g,right-0.06,lo,right,lo+0.12,I.CLEAR)
    end
  end
end
local source=assert(app.open(r.template));local sprite=Sprite(source);source:close()
assert(sprite.width==541 and sprite.height==272 and #sprite.layers==9,"Template mismatch")
app.sprite=sprite
local palette=Palette(#r.palette.colors)
for i,c in ipairs(r.palette.colors) do palette:setColor(i-1,Color{r=c[1],g=c[2],b=c[3],a=c[4]}) end
sprite:setPalette(palette)
sprite.data="318_RESIDENTIAL_V2 | 64 px/m | approved 20 colors | left single door | grey raw concrete | no baked number"
local stats={}
for _,g in ipairs(r.layers) do
  local layer
  for _,candidate in ipairs(sprite.layers) do if candidate.name==g.id then layer=candidate end end
  assert(layer and not layer.isReference)
  layer.isEditable=true;layer.isVisible=true;layer.opacity=255;layer.blendMode=BlendMode.NORMAL
  if layer:cel(1) then sprite:deleteCel(layer,1) end
  local im=Image(g.width,g.height,ColorMode.RGB);im:clear()
  paint(im,g)
  sprite:newCel(layer,1,im,Point(0,0))
  local allowed={};for _,value in pairs(colors) do allowed[value]=true end
  local opaque,transparent=0,0
  for it in im:pixels() do
    assert(allowed[it()],"Painter emitted off-palette color")
    local a=pc.rgbaA(it());assert(a==0 or a==255)
    if a==0 then transparent=transparent+1 else opaque=opaque+1 end
  end
  if g.id=="far" or g.id=="ground" then assert(transparent==0,"Opaque fallback missing") end
  stats[#stats+1]={id=g.id,width=im.width,height=im.height,opaque=opaque,transparent=transparent}
end
for _,layer in ipairs(sprite.layers) do
  if layer.name=="REFERENCE" then
    assert(layer.isReference);layer.isEditable=true
    if layer:cel(1) then sprite:deleteCel(layer,1) end
    sprite:newCel(layer,1,Image{fromFile=r.reference},Point(0,0))
    layer.isVisible=false;layer.isEditable=false
  elseif layer.name=="GUIDES" then layer.isVisible=false;layer.isEditable=false end
end
sprite:saveCopyAs(r.output);sprite:close()
local f=assert(io.open(r.report,"wb"));f:write(json.encode({ok=true,palette=r.palette.id,density=r.density,layers=stats,source=r.output}));f:close()
print("RESIDENTIAL V2 PAINT PASS")
