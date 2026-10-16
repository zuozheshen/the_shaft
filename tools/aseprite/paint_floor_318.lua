-- 318 residential V1 native-pixel reconstruction. Reference is never sampled.
-- Approved 64 px/m and 26 colors; existing source is read-only, output must be new.
local function read_json(path)
  local f=assert(io.open(path,"rb")); local value=json.decode(f:read("*a")); f:close(); return value
end
local r=read_json(assert(app.params["request"]))
assert(not app.isUIAvailable and app.apiVersion>=41,"Batch Lua API 41 required")
assert(not app.fs.isFile(r.output),"Refusing existing authored source")
assert(r.palette.art_approved and #r.palette.colors==26 and r.density==64,"Approval mismatch")
local pc=app.pixelColor
local colors={}
for i,c in ipairs(r.palette.colors) do colors[i-1]=pc.rgba(c[1],c[2],c[3],c[4]) end
local I={CLEAR=0,INK=1,DARK=2,DOOR=3,DEEP_GREEN=4,GREEN=5,LIT_GREEN=6,SAGE=7,
  CHARCOAL=8,CONCRETE_DARK=9,CONCRETE=10,PLASTER=11,PLASTER_LIT=12,CHIP=13,
  PAPER=14,PAPER_LIT=15,LAMP=16,BROWN_DARK=17,CORK=18,CORK_LIT=19,CARD=20,
  LEAF_DARK=21,LEAF=22,LEAF_LIT=23,STEEL=24,STEEL_LIT=25}
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
-- Designed multi-pixel clusters: no random one-pixel noise, no generated-image resampling.
local function patches(im,g,x0,y0,x1,y1,count,index,seed)
  local state=seed
  local function rand() state=(state*48271)%2147483647;return state/2147483647 end
  for i=1,count do
    local x=x0+rand()*(x1-x0);local y=y0+rand()*(y1-y0)
    local w=0.04+rand()*0.12;local h=0.035+rand()*0.075
    rect(im,g,x,y,math.min(x1,x+w),math.min(y1,y+h),index)
    if i%4==0 then rect(im,g,x+w/3,y-h/3,math.min(x1,x+w*0.8),y,index) end
  end
end
local function wall(im,g,base,lower)
  im:clear(colors[base])
  rect(im,g,-5,-0.1,5,1.22,lower)
  rect(im,g,-5,0.02,5,0.16,I.CHARCOAL)
  rect(im,g,-5,1.20,5,1.235,I.LIT_GREEN)
  patches(im,g,-4.15,1.30,4.15,4.1,45,I.CONCRETE,173)
  patches(im,g,-4.15,1.30,4.15,4.1,16,I.PLASTER_LIT,919)
  patches(im,g,-4.15,0.2,4.15,1.17,24,I.DEEP_GREEN,411)
  patches(im,g,-4.15,0.2,4.15,0.55,17,I.CHIP,323)
end
local function door(im,g,x0,x1)
  rect(im,g,x0-0.09,0.01,x1+0.09,2.03,I.CONCRETE_DARK)
  rect(im,g,x0-0.05,0.04,x1+0.045,2.01,I.DARK)
  rect(im,g,x0-0.05,2.01,x1+0.045,2.055,I.LIT_GREEN)
  rect(im,g,x0-0.05,0.04,x0-0.02,2.01,I.STEEL)
  rect(im,g,x0,0.055,x1,1.995,I.DOOR)
  rect(im,g,x0+0.045,0.11,x1-0.035,1.95,I.DEEP_GREEN)
  rect(im,g,x0+0.075,0.18,x1-0.06,1.90,I.DOOR)
  line(im,g,x0+0.06,0.12,x0+0.06,1.94,I.LIT_GREEN)
  line(im,g,x0+0.08,1.935,x1-0.03,1.935,I.LIT_GREEN)
  patches(im,g,x0+0.12,0.25,x1-0.12,1.75,5,I.DEEP_GREEN,math.floor((x0+5)*931))
  -- Inset edge reveals the continuous far layer; the leaf itself stays closed.
  rect(im,g,x1-0.02,0.08,x1+0.005,1.98,I.CLEAR)
  rect(im,g,x0+0.09,0.42,x0+0.105,0.78,I.STEEL)
  local handle=x1-0.10
  rect(im,g,handle-0.015,0.82,handle+0.025,1.02,I.CHARCOAL)
  rect(im,g,handle-0.08,0.92,handle+0.035,0.95,I.STEEL_LIT)
  ellipse(im,g,(x0+x1)/2,1.42,0.023,0.023,I.INK)
  rect(im,g,x0-0.20,1.01,x0-0.11,1.27,I.DARK)
  rect(im,g,x0-0.18,1.035,x0-0.13,1.08,I.STEEL)
end
local function board(im,g,x0,y0,x1,y1)
  rect(im,g,x0-0.018,y0-0.025,x1+0.03,y1+0.01,I.INK)
  rect(im,g,x0,y0,x1,y1,I.BROWN_DARK)
  rect(im,g,x0+0.045,y0+0.04,x1-0.04,y1-0.04,I.CORK)
  rect(im,g,x0+0.014,y1-0.02,x1-0.01,y1,I.CARD)
  rect(im,g,x0,y0,x0+0.018,y1,I.CORK_LIT)
  patches(im,g,x0+0.05,y0+0.05,x1-0.045,y1-0.05,14,I.CORK_LIT,991)
  local papers={{0.07,0.24,0.16,0.39},{0.27,0.26,0.18,0.43},{0.09,0.05,0.19,0.16},{0.34,0.06,0.14,0.18}}
  for n,p in ipairs(papers) do
    local x=x0+p[1];local y=y0+p[2]
    rect(im,g,x+0.016,y-0.015,x+p[3]+0.016,y+p[4],I.BROWN_DARK)
    rect(im,g,x,y,x+p[3],y+p[4],n==2 and I.PAPER_LIT or I.PAPER)
    rect(im,g,x+0.022,y+p[4]-0.045,x+p[3]-0.02,y+p[4]-0.027,I.CONCRETE)
    for j=1,n==2 and 5 or 3 do
      local yy=y+p[4]-0.075-j*0.044
      rect(im,g,x+0.02,yy,x+p[3]-0.022,yy+0.017,I.PLASTER_LIT)
    end
    ellipse(im,g,x+p[3]/2,y+p[4]-0.016,0.012,0.012,I.STEEL_LIT)
  end
end
local function paint(im,g)
  if g.id=="far" then
    wall(im,g,I.CONCRETE_DARK,I.DEEP_GREEN)
    rect(im,g,-1.95,0.04,-0.25,2.12,I.DOOR)
    rect(im,g,0.25,0.04,1.95,2.12,I.DOOR)
    rect(im,g,-5,3.25,5,4.3,I.CHARCOAL)
  elseif g.id=="main" then
    wall(im,g,I.PLASTER,I.GREEN)
    -- Quiet concrete structure and controlled fluorescent pools.
    rect(im,g,-4.1,2.96,4.1,3.35,I.CONCRETE_DARK)
    rect(im,g,-4.1,3.24,4.1,3.30,I.PLASTER_LIT)
    rect(im,g,-4.1,2.96,4.1,3.01,I.CHARCOAL)
    rect(im,g,-3.00,0.15,-2.75,2.95,I.CONCRETE)
    rect(im,g,2.78,0.15,3.04,2.95,I.CONCRETE)
    line(im,g,-2.76,0.2,-2.76,2.93,I.PLASTER_LIT)
    door(im,g,-1.61,-0.70);door(im,g,0.72,1.63)
    -- Existing shared Label3D paints FLOOR 318; keep the carrier blank.
    rect(im,g,-1.005,1.71,1.015,2.43,I.CONCRETE_DARK)
    rect(im,g,-0.975,1.76,0.975,2.41,I.DARK)
    rect(im,g,-0.94,1.80,0.94,2.38,I.DOOR)
    line(im,g,-0.97,2.40,0.97,2.40,I.STEEL)
    line(im,g,-0.97,1.77,0.97,1.77,I.INK)
    -- Background ceiling light, visible in the wider camera.
    rect(im,g,-0.43,2.69,0.43,2.88,I.CHARCOAL)
    rect(im,g,-0.39,2.72,0.39,2.86,I.STEEL)
    rect(im,g,-0.33,2.74,0.33,2.82,I.LAMP)
    line(im,g,-0.31,2.75,0.31,2.75,I.PAPER)
    for x=-2.2,2.2,1.1 do rect(im,g,x,0.17,x+0.022,1.16,I.DEEP_GREEN) end
  elseif g.id=="mid_left" then
    board(im,g,-1.62,0.98,-1.01,1.82)
    -- Rail below the noticeboard, with visible metal brackets.
    rect(im,g,-3.1,0.765,-0.91,0.825,I.DARK)
    rect(im,g,-3.1,0.81,-0.91,0.84,I.STEEL)
    for _,x in ipairs({-2.7,-2.1,-1.55,-1.02}) do
      rect(im,g,x,0.69,x+0.055,0.80,I.DARK)
      rect(im,g,x+0.015,0.72,x+0.035,0.75,I.STEEL)
    end
    -- One small municipal bin; silhouette stays outside the central passage.
    rect(im,g,-1.45,0.03,-1.06,0.59,I.DARK)
    rect(im,g,-1.43,0.055,-1.10,0.58,I.CONCRETE)
    rect(im,g,-1.43,0.09,-1.17,0.51,I.CONCRETE_DARK)
    rect(im,g,-1.45,0.57,-1.04,0.62,I.STEEL)
    rect(im,g,-1.17,0.47,-1.09,0.55,I.INK)
    line(im,g,-1.10,0.10,-1.10,0.56,I.STEEL)
    rect(im,g,-1.36,0.07,-1.20,0.105,I.CHARCOAL)
    -- Tied bag built from coherent angular clusters.
    polygon(im,g,{{-1.03,0.04},{-0.88,0.045},{-0.86,0.25},{-0.91,0.40},{-0.96,0.43},{-1.03,0.29}},I.INK)
    polygon(im,g,{{-1.0,0.08},{-0.9,0.1},{-0.90,0.24},{-0.95,0.37},{-0.99,0.22}},I.DARK)
    line(im,g,-0.97,0.13,-0.95,0.32,I.STEEL)
    rect(im,g,-0.975,0.40,-0.93,0.47,I.DARK)
  elseif g.id=="mid_right" then
    -- Narrow utility pipe; no new Mesh or Light.
    rect(im,g,0.96,0.15,1.08,3.5,I.DARK)
    rect(im,g,0.975,0.15,1.035,3.5,I.CONCRETE)
    rect(im,g,0.985,0.15,1.015,3.5,I.STEEL)
    for _,y in ipairs({0.35,1.24,2.05,2.80}) do rect(im,g,0.95,y,1.095,y+0.065,I.DARK);rect(im,g,0.96,y+0.04,1.08,y+0.066,I.STEEL) end
    -- Sparse living detail: pot, leaves and one delivery parcel.
    polygon(im,g,{{1.24,0.045},{1.46,0.045},{1.49,0.27},{1.20,0.27}},I.BROWN_DARK)
    rect(im,g,1.20,0.24,1.49,0.29,I.CORK)
    rect(im,g,1.25,0.07,1.28,0.23,I.CORK_LIT)
    local stems={{1.15,0.52},{1.53,0.56},{1.28,0.66},{1.43,0.70},{1.12,0.72},{1.54,0.82}}
    for n,p in ipairs(stems) do
      line(im,g,1.34,0.25,p[1],p[2],I.LEAF_DARK)
      local dx=n%2==0 and 0.15 or -0.15
      polygon(im,g,{{p[1]-dx*0.5,p[2]-0.045},{p[1]+dx,p[2]+0.095},{p[1]+dx*0.3,p[2]+0.12},{p[1],p[2]+0.02}},n%2==0 and I.LEAF or I.LEAF_LIT)
    end
    ellipse(im,g,1.32,0.60,0.085,0.045,I.LEAF)
    ellipse(im,g,1.50,0.44,0.09,0.045,I.LEAF_DARK)
    ellipse(im,g,1.20,0.41,0.10,0.04,I.LEAF)
    rect(im,g,0.88,0.035,1.17,0.28,I.BROWN_DARK)
    rect(im,g,0.90,0.055,1.15,0.26,I.CARD)
    rect(im,g,0.91,0.23,1.15,0.275,I.CORK_LIT)
    rect(im,g,1.015,0.06,1.042,0.255,I.PAPER)
    rect(im,g,0.93,0.15,0.99,0.205,I.PAPER)
  elseif g.id=="ground" then
    im:clear(colors[I.CONCRETE])
    local tile=0.48
    for row=-9,1 do for col=-10,10 do
      local x=col*tile;local z=row*tile;local index=(row+col)%4==0 and I.CONCRETE_DARK or I.CONCRETE
      rect(im,g,x,z,x+tile,z+tile,index)
      rect(im,g,x,z,x+0.018,z+tile,I.CHARCOAL)
      rect(im,g,x,z,x+tile,z+0.018,I.CHARCOAL)
      rect(im,g,x+0.025,z+0.025,x+tile,z+0.040,I.PLASTER)
      rect(im,g,x+0.025,z+0.025,x+0.04,z+tile,I.PLASTER)
      patches(im,g,x+0.05,z+0.05,x+tile-0.06,z+tile-0.06,1,I.PLASTER,math.abs(row*487+col*71)+11)
    end end
    -- Broad low-contrast pool on tile interiors; seams remain uninterrupted.
    for y=0,im.height-1 do for x=0,im.width-1 do
      local wx=g.origin[1]-g.size[1]/2+(x+0.5)/im.width*g.size[1]
      local wz=g.origin[3]-g.size[2]/2+(y+0.5)/im.height*g.size[2]
      local e=((wx-0.12)/0.63)^2+((wz+2.08)/1.15)^2
      if e<1 and im:getPixel(x,y)==colors[I.CONCRETE] then put(im,x,y,I.PLASTER) end
    end end
    -- Two small doormats; empty center remains walkable.
    rect(im,g,-1.61,-3.62,-0.74,-3.20,I.BROWN_DARK)
    rect(im,g,-1.57,-3.59,-0.78,-3.24,I.CORK)
    rect(im,g,0.76,-3.62,1.62,-3.20,I.BROWN_DARK)
    rect(im,g,0.80,-3.59,1.58,-3.24,I.CORK)
    for x=-1.52,-0.83,0.08 do line(im,g,x,-3.55,x,-3.28,I.CORK_LIT) end
    for x=0.85,1.53,0.08 do line(im,g,x,-3.55,x,-3.28,I.CORK_LIT) end
  else
    local left=g.origin[1]-g.size[1]/2;local right=g.origin[1]+g.size[1]/2
    local lo=g.origin[2]-g.size[2]/2;local hi=g.origin[2]+g.size[2]/2
    -- Retained front slots are local near-door trims, with actual alpha cutouts.
    rect(im,g,left+0.02,lo+0.055,right-0.025,hi-0.025,I.DARK)
    rect(im,g,left+0.025,lo+0.08,left+0.06,hi-0.03,I.STEEL)
    rect(im,g,right-0.08,lo+0.08,right-0.04,hi-0.03,I.CONCRETE)
    rect(im,g,left+0.07,lo+0.10,right-0.09,hi-0.05,I.CHARCOAL)
    patches(im,g,left+0.09,lo+0.13,right-0.11,hi-0.12,12,I.CONCRETE_DARK,391)
    rect(im,g,left,lo,left+0.10,lo+0.17,I.CLEAR)
  end
end
local source=assert(app.open(r.template));local sprite=Sprite(source);source:close()
assert(sprite.width==541 and sprite.height==272 and #sprite.layers==9,"Template mismatch")
app.sprite=sprite
local palette=Palette(#r.palette.colors)
for i,c in ipairs(r.palette.colors) do palette:setColor(i-1,Color{r=c[1],g=c[2],b=c[3],a=c[4]}) end
sprite:setPalette(palette)
sprite.data="318_RESIDENTIAL_V1 | 64 px/m | user approved 26 color palette | blank dynamic floor label"
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
print("RESIDENTIAL PAINT PASS")
