"""Retain APK runtime-effect geometry and placement, independent of the Metal port."""
import re
import sys


def attach(builder, tscn_path):
    if not tscn_path or not tscn_path.exists(): return
    c = sys.modules[builder.__class__.__module__]
    text = tscn_path.read_text()
    root = builder.root_nodes[0]
    climate = []
    charge_transform = None
    for header, body in re.findall(r'\[node ([^\]]+)\]([^\[]*)', text):
        name = re.search(r'name="([^"]+)"', header)
        if not name: continue
        name = name.group(1)
        transform = re.search(r'transform = Transform\( ([^)]*)\)', body)
        matrix = c.godot_transform_to_gltf_matrix([float(x) for x in transform.group(1).split(',')]) if transform else None
        if name.lower().startswith('airflow') and matrix:
            climate.append({'name':name,'matrix':matrix,'source':str(tscn_path.relative_to(c.EXTRACTED_ROOT))})
        if name == 'ChargePort' and matrix: charge_transform = matrix
        elif name == 'ChargeportMarker' and matrix and charge_transform is None: charge_transform = matrix
    from source_noise import airflow_noise
    noise_index = len(builder.source_textures)
    builder.source_textures.append({"source":"res://mobile/materials/noiseTexture.tres","width":512,"height":512,"encoding":"png","bufferView":builder._append_bytes(airflow_noise())})
    road = builder.add_source_texture('res://mobile/materials/dashed_lane.png')
    builder.runtime_effects = {'climate':climate,'noiseTexture':noise_index,'roadTexture':road if road is not None else -1,
                              'airflowShader':'res://mobile/materials/airflow_shader.tres',
                              'roadScript':'res://mobile/scripts/Road.gdc',
                              'airflowScript':'res://mobile/scripts/Airflow.gdc'}
    if not charge_transform: return
    source = c.resolve_res_path('res://mobile/geometry/Charging_Cable/Charging_Cable.tscn')
    if not source: return
    cable_info = c.parse_tscn_metadata(source)
    holder = len(builder.nodes)
    builder.nodes.append({'name':'APK_ChargeCable','matrix':charge_transform,'extras':{'effect':'charging'},'children':[]})
    builder.nodes[root].setdefault('children',[]).append(holder)
    by_path = {'.':holder}
    for header, body in re.findall(r'\[node ([^\]]+)\]([^\[]*)', source.read_text()):
        name = re.search(r'name="([^"]+)"',header).group(1)
        parent = re.search(r'parent="([^"]+)"',header)
        if not parent: continue
        if 'visible = false' in body: continue
        parent = parent.group(1); parent_id = by_path.get(parent,holder)
        node={'name':name}; transform=re.search(r'transform = Transform\( ([^)]*)\)',body)
        if transform: node['matrix']=c.godot_transform_to_gltf_matrix([float(x) for x in transform.group(1).split(',')])
        index=len(builder.nodes);builder.nodes.append(node);builder.nodes[parent_id].setdefault('children',[]).append(index)
        by_path[(parent+'/' if parent!='.' else '')+name]=index
        mesh_ref=re.search(r'^mesh = ExtResource\( (\d+) \)',body,re.M)
        if mesh_ref:
            path=c.resolve_res_path(cable_info['ext_res'][int(mesh_ref.group(1))][1])
            if path:
                material='res://mobile/geometry/Charging_Cable/Charging_Cable.material'
                overrides={'node_materials':{path.stem:{0:material}},'node_transforms':{},'hidden_nodes':set()}
                child=builder.add_scn_to_tree(path,overrides,parent_gltf_node=index)
                if name=='Charger_Cable':builder.nodes[child]['extras']={'effect':'chargeFlow'}
    builder.runtime_effects['chargingSource']='res://mobile/geometry/Charging_Cable/Charging_Cable.tscn'
