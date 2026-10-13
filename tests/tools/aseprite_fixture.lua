-- CLI test fixtures operate only on new copies in the ignored test directory.
local source = assert(app.params["source"])
local target = assert(app.params["target"])
local mode = assert(app.params["mode"])
assert(not app.fs.isFile(target), "Fixture target already exists")
assert(string.find(target:gsub("\\","/"),"/art_source/floors/.staging/tests-",1,true), "Fixture target outside tests")
local loaded = assert(app.open(source))
local sprite = Sprite(loaded)
loaded:close()
local function layer(name)
  for _, value in ipairs(sprite.layers) do if value.name == name then return value end end
  error("Missing fixture layer")
end
if mode == "reference_guides" then
  local reference = layer("REFERENCE")
  reference.isEditable = true
  local image = Image(32,32,ColorMode.RGB)
  for it in image:pixels() do it(app.pixelColor.rgba(it.x*7,it.y*7,(it.x*13+it.y*11)%256,255)) end
  sprite:newCel(reference,1,image,Point(0,0))
  reference.isVisible = true
  layer("GUIDES").isVisible = true
  layer("main").isVisible = false
elseif mode == "hidden_bad" then
  layer("mid_left").isVisible = false
  layer("mid_left"):cel(1).image:drawPixel(0,0,app.pixelColor.rgba(1,2,3,255))
elseif mode == "alpha" then
  layer("mid_left"):cel(1).image:drawPixel(0,0,app.pixelColor.rgba(104,116,124,128))
elseif mode == "bounds" then
  layer("mid_left"):cel(1).position = Point(sprite.width+1,0)
elseif mode == "missing" then sprite:deleteLayer(layer("main"))
elseif mode == "duplicate" then layer("front_left").name = "main"
elseif mode == "group" then
  sprite:deleteLayer(layer("main"))
  sprite:newGroup().name = "main"
elseif mode == "frame" then sprite:newEmptyFrame(2)
elseif mode == "canvas" then sprite:resize(sprite.width+1,sprite.height)
elseif mode == "empty" then sprite:deleteCel(layer("mid_left"),1)
elseif mode == "reference_png" then
  local image = Image(32,32,ColorMode.RGB)
  for it in image:pixels() do it(app.pixelColor.rgba(it.x*7,it.y*7,(it.x*13+it.y*11)%256,255)) end
  assert(image:saveAs(target), "Reference PNG save")
  sprite:close(); print("FIXTURE PASS"); return
else error("Unknown fixture mode") end
sprite:saveAs(target)
sprite:close()
print("FIXTURE PASS")
