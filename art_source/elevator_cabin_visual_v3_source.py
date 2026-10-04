"""#66 V3 rework: continuous, unworn smoky-blue paint and clean assembly.
Rebuild native resources with --godot and external --scratch-dir.
Original models, V1 maps and gameplay stay untouched.
"""
from pathlib import Path
import argparse
import re
import subprocess
ROOT=Path(__file__).resolve().parents[1]
MAT="assets/art/materials/elevator_cabin_v3"
TEX="assets/art/textures/elevator_cabin_v3"

def write(path,text):
    path=ROOT/path
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding="utf-8",newline="\n")

def material(name,color,rough=.75,metal=0,texture=None):
    ext=""
    if texture: ext+=f'[ext_resource type="Texture2D" path="res://{texture}" id="1_albedo"]\n'
    t=f'[gd_resource type="StandardMaterial3D" format=3]\n\n{ext}\n[resource]\nresource_name = "ART03_V3_{name}"\nalbedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\nroughness = {rough}\nmetallic = {metal}\ntexture_filter = 5\n'
    if texture: t+='albedo_texture = ExtResource("1_albedo")\n'
    write(MAT+"/"+name+".tres",t)

class Scene:
    def __init__(self,name):
        self.ext={};self.sub=[];self.nodes=[f'[node name="{name}" type="Node3D"]\n'];self.seq=0
    def resource(self,name,kind="Material"):
        self.ext[name]=f'[ext_resource type="{kind}" path="res://{MAT}/{name}.tres" id="{name}"]'
        return f'ExtResource("{name}")'
    def group(self,name,pos=(0,0,0),rot=(0,0,0)):
        self.nodes.append(f'[node name="{name}" type="Node3D" parent="."]\nposition = Vector3{pos}\nrotation = Vector3{rot}\n')
        return name
    def mesh(self,name,parent,pos,size,mat,quad=False,rot=(0,0,0),layer=1):
        self.seq+=1;sid=f"mesh_{self.seq}"
        v=f'Vector2({size[0]}, {size[1]})' if quad else f'Vector3{size}'
        self.sub.append(f'[sub_resource type="{"QuadMesh" if quad else "BoxMesh"}" id="{sid}"]\nsize = {v}\nmaterial = {self.resource(mat)}\n')
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = Vector3{pos}\nrotation = Vector3{rot}\nlayers = {layer}\nmesh = SubResource("{sid}")\n')
    def native(self,name,parent,pos,mesh,rot=(0,0,0),layer=1):
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = Vector3{pos}\nrotation = Vector3{rot}\nlayers = {layer}\nmesh = {self.resource(mesh,"ArrayMesh")}\n')
    def bolt(self,name,parent,pos):
        if not any('id="bolt"' in item for item in self.sub):
            self.sub.append('[sub_resource type="CylinderMesh" id="bolt"]\ntop_radius = 0.007\nbottom_radius = 0.007\nheight = 0.004\nradial_segments = 6\nrings = 1\nmaterial = '+self.resource("steel")+'\n')
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = Vector3{pos}\nrotation = Vector3(1.570796327, 0, 0)\nmesh = SubResource("bolt")\n')
    def save(self,path):
        write(path,"[gd_scene format=3]\n\n"+"\n".join(self.ext.values())+"\n\n"+"\n".join(self.sub)+"\n"+"\n".join(self.nodes))

def cabinet():
    s=Scene("舱体装配视觉V3")
    walls=[("前壁",(0,0,-1.694),0,"wall"),("左壁",(-1.694,0,0),1.570796327,"wall"),("后壁",(0,0,1.694),3.141592654,"wall"),("右壁",(1.694,0,0),-1.570796327,"wall")]
    for wall,pos,yaw,mat in walls:
        p=s.group(wall,pos=pos,rot=(0,yaw,0))
        # 连续纯色喷漆不切格，不连接磨损或重复分板贴图。
        s.mesh("连续喷漆墙面",p,(0,1.25,.001),(3.38,2.40),mat,quad=True)
        s.mesh("顶部窄折边",p,(0,2.477,.008),(3.33,.033,.016),"trim")
        s.mesh("地脚防护",p,(0,.033,.011),(3.33,.055,.021),"joint")
        for x in (-1.678,1.678): s.mesh("转角折边"+str(x),p,(x,1.253,.009),(.026,2.38,.017),"trim")
        if wall=="后壁":
            # 只在后墙设检修门；整个盖板与把手在正式后方视角可见。
            s.mesh("检修门安装薄框",p,(-.57,1.48,.010),(.817,1.017,.015),"joint")
            s.native("检修门盖板",p,(-.57,1.48,.024),"hatch_bevel")
            for i,(x,y) in enumerate(((-.35,-.44),(.35,-.44),(-.35,.44),(.35,.44))): s.bolt("检修固定件"+str(i),p,(-.57+x,1.48+y,.034))
            for y in (1.535,1.415): s.mesh("把手座"+str(y),p,(-.84,y,.037),(.028,.027,.018),"steel")
            s.mesh("检修折手",p,(-.84,1.475,.054),(.015,.14,.021),"steel")
            s.mesh("点检记录夹板",p,(.76,1.79,.019),(.51,.53,.014),"trim")
            s.mesh("点检记录",p,(.76,1.79,.028),(.475,.485),"record",quad=True)
            s.mesh("记录夹",p,(.76,2.04,.033),(.15,.023,.01),"steel")
    p=s.group("天花检修",pos=(.74,2.497,1.56),rot=(1.570796327,0,0))
    s.mesh("盖板垫边",p,(0,0,.002),(.572,.272,.012),"joint")
    s.native("维修盖板",p,(0,0,.010),"ceiling_hatch_bevel")
    for i,(x,y) in enumerate(((-.245,-.10),(.245,-.10),(-.245,.10),(.245,.10))): s.bolt("维修紧固"+str(i),p,(x,y,.019))
    s.save("scenes/visuals/cabin_assembly_v3_visual.tscn")
    s=Scene("乘客舱装配视觉V3")
    for x in (-1.017,1.017): s.mesh("门框内折边"+str(x),".",(x,1.25,.106),(.025,2.43,.016),"steel",layer=2)
    for z in (-.06,.06): s.mesh("门槛导向槽"+str(z),".",(0,.053,z),(2.035,.006,.017),"joint",layer=2)
    s.mesh("门槛前沿收边",".",(0,.055,.142),(2.03,.010,.018),"steel",layer=2)
    s.save("scenes/visuals/passenger_cabin_assembly_v3_visual.tscn")

def native_meshes(godot,scratch):
    # 只制作干净的折边盖板；不生成任何磨耗覆盖层。
    code='''extends SceneTree
func _initialize() -> void:
	for spec in [["hatch_bevel",.80,1.0,.008],["ceiling_hatch_bevel",.56,.26,.004]]:
		var w=spec[1]/2.0
		var h=spec[2]/2.0
		var b=spec[3]
		var outer=[Vector3(-w,-h,0),Vector3(w,-h,0),Vector3(w,h,0),Vector3(-w,h,0)]
		var inner=[Vector3(-w+b,-h+b,.008),Vector3(w-b,-h+b,.008),Vector3(w-b,h-b,.008),Vector3(-w+b,h-b,.008)]
		var st=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(load("res://MAT/hatch.tres"))
		face(st,inner,Vector3(0,0,1))
		for i in range(4):
			var j=(i+1)%4
			var middle=(outer[i]+outer[j])/2
			face(st,[outer[i],outer[j],inner[j],inner[i]],Vector3(middle.x/w,middle.y/h,1).normalized())
			face(st,[outer[i]-Vector3(0,0,.007),outer[j]-Vector3(0,0,.007),outer[j],outer[i]],Vector3(middle.x/w,middle.y/h,0).normalized())
		face(st,[outer[3]-Vector3(0,0,.007),outer[2]-Vector3(0,0,.007),outer[1]-Vector3(0,0,.007),outer[0]-Vector3(0,0,.007)],Vector3(0,0,-1))
		st.generate_tangents()
		if ResourceSaver.save(st.commit(),"res://MAT/"+str(spec[0])+".tres")!=OK: quit(1);return
	print("NATIVE MAINTENANCE MESH PASS")
	quit(0)
func face(st:SurfaceTool,p:Array,n:Vector3) -> void:
	var order=[0,1,2,0,2,3]
	if (p[1]-p[0]).cross(p[2]-p[0]).dot(n)>0: order=[0,2,1,0,3,2]
	var uv=[Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
	for index in order:
		st.set_normal(n)
		st.set_uv(uv[index])
		st.add_vertex(p[index])
'''.replace("MAT",MAT)
    scratch.mkdir(parents=True,exist_ok=True);gd=scratch/"native-mesh-build.gd";gd.write_text(code,encoding="utf-8")
    run=subprocess.run([str(godot),"--headless","--path",str(ROOT),"--script",str(gd)],capture_output=True,text=True,encoding="utf-8",timeout=90)
    if run.returncode or "ERROR" in run.stderr or "NATIVE MAINTENANCE MESH PASS" not in run.stdout: raise RuntimeError(run.stdout+run.stderr)
    for name in ["hatch_bevel","ceiling_hatch_bevel"]:
        path=ROOT/MAT/(name+".tres")
        path.write_text(re.sub(r' uid="uid://[^"]+"',"",path.read_text(encoding="utf-8")),encoding="utf-8",newline="\n")
    print(run.stdout.strip())

def hookup():
    p=ROOT/"scenes/elevator/elevator_cabin_3d.tscn";t=p.read_text(encoding="utf-8")
    t=re.sub(r'\[ext_resource type="Material"[^\n]+ id="66_ceiling"\]',f'[ext_resource type="Material" path="res://{MAT}/ceiling.tres" id="66_ceiling"]',t)
    p.write_text(t,encoding="utf-8",newline="\n")
    # 只覆盖机身材料，原导入节点的 Transform/Mesh/模块材质不动。
    names=[(10,"上柜右侧壁"),(11,"上柜右面板"),(12,"上柜后壳"),(13,"上柜左侧壁"),(14,"上柜左面板"),(15,"上柜顶盖"),(16,"下部柜座"),(17,"前缘水平托台"),(18,"操作楔体"),(19,"状态窗下框")]
    t=f'[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://assets/art/models/main_console_shell.glb" id="1_shell"]\n[ext_resource type="Material" path="res://{MAT}/shell.tres" id="66_shell"]\n\n[node name="主操作台外壳" type="Node3D"]\n\n[node name="外壳模型" parent="." instance=ExtResource("1_shell")]\n\n'
    for index,name in names: t+=f'[node name="{name}" parent="外壳模型/主操作台外壳" index="{index}"]\nmaterial_override = ExtResource("66_shell")\n\n'
    t+='[editable path="外壳模型"]\n'
    write("scenes/visuals/main_console_shell_visual.tscn",t)
    p=ROOT/"scenes/presentation/elevator_door_visual_3d.tscn";t=p.read_text(encoding="utf-8")
    t=re.sub(r'^\[(?:node|sub_resource|ext_resource)[^\n]*(?:66_rework|V3接触|V3中央|V3折边)[^\n]*\]\n.*?(?=^\[|\Z)',"",t,flags=re.M|re.S)
    ext="";sub="";nodes=""
    for side,chinese,sign in (("left","左",1),("right","右",-1)):
        parent=f"门扇根/{chinese}门扇动画根"
        for suffix,x,width,mat in (("中央",.511,.018,"joint"),("折边",.483,.016,"steel")):
            token="center" if suffix=="中央" else "fold"
            ident=f"66_rework_{side}_{token}";ext+=f'[ext_resource type="Material" path="res://{MAT}/{mat}.tres" id="{ident}_mat"]\n'
            sub+=f'[sub_resource type="QuadMesh" id="{ident}"]\nsize = Vector2({width}, 2.34)\nmaterial = ExtResource("{ident}_mat")\n\n'
            nodes+=f'[node name="V3{suffix}" type="MeshInstance3D" parent="{parent}"]\nposition = Vector3({x*sign}, 0, 0.0419)\nlayers = 2\nmesh = SubResource("{ident}")\n\n'
    i=t.index('[sub_resource');t=t[:i]+ext+'\n'+t[i:]
    i=t.index('[node');t=t[:i]+sub+t[i:]+"\n"+nodes
    p.write_text(t.rstrip()+"\n",encoding="utf-8",newline="\n")

def build(godot,scratch):
    # 全部大面为未磨损材质：颜色与统一粗糙度表达涂层，不连接旧化贴图。
    material("wall",(.52,.60,.65),rough=.72)
    material("ceiling",(.70,.73,.74),rough=.77)
    material("hatch",(.62,.67,.70),rough=.66)
    material("shell",(.72,.74,.735),rough=.65)
    material("frame",(.24,.28,.30),rough=.62,metal=.12)
    for side in ("left","right"): material("door_"+side,(.69,.73,.75),rough=.40,metal=.22)
    material("joint",(.12,.14,.15),rough=.90)
    material("trim",(.38,.42,.44),rough=.65)
    material("steel",(.67,.69,.70),rough=.43,metal=.24)
    material("record",(1,1,1),rough=.95,texture=TEX+"/inspection_record.png")
    native_meshes(godot,scratch);cabinet();hookup()
    for path in (ROOT/TEX).glob("*.png.import"):
        t=path.read_text(encoding="utf-8")
        for key,value in {"compress/mode":"0","mipmaps/generate":"true","detect_3d/compress_to":"0"}.items(): t=re.sub(r'^'+re.escape(key)+r'=.*$',key+'='+value,t,flags=re.M)
        path.write_text(t,encoding="utf-8",newline="\n")
    print("CLEAN CONTINUOUS BLUE VISUAL PASS")

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--godot",type=Path,required=True)
    parser.add_argument("--scratch-dir",type=Path,required=True)
    args=parser.parse_args()
    build(args.godot,args.scratch_dir)
