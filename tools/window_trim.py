"""Isolate window-surround triangles using source surface bindings and glass boundaries.

This is viewer customization metadata, not an APK semantic component label.
Source meshes, UVs and material bindings remain untouched. No vehicle-specific
coordinate boxes are used; moving doors retain the mask in their local topology.
"""
import re
import numpy as np

def annotate(gltf, binary):
    nodes = gltf['nodes']; worlds = {}
    def visit(i, parent):
        n=nodes[i]; m=np.array(n.get('matrix',np.eye(4).flatten(order='F')),dtype=float).reshape(4,4,order='F')
        worlds[i]=parent@m
        for c in n.get('children',[]): visit(c,worlds[i])
    for i in gltf['scenes'][0]['nodes']: visit(i,np.eye(4))
    def read(i):
        a=gltf['accessors'][i];v=gltf['bufferViews'][a['bufferView']]
        dims={'VEC3':3,'SCALAR':1}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]
        return np.frombuffer(binary,dtype=dtype,count=a['count']*dims,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,dims)
    def positions(i,p):
        a=read(p['attributes']['POSITION']);return np.einsum('ij,kj->ki',worlds[i],np.c_[a,np.ones(len(a))])
    samples=[]
    for i,n in enumerate(nodes):
        name=n.get('name','').lower()
        if 'mesh' not in n or 'window' not in name or any(x in name for x in ['top','rear','front_window']): continue
        if not re.search(r'left|right|_l[f r]?\d*$|_r[f r]?\d*$|_side',name): continue
        for p in gltf['meshes'][n['mesh']]['primitives']:
            mat=gltf['materials'][p['material']]['extras']
            if mat.get('category') not in ('glass','glass_tinted'): continue
            xyz=positions(i,p)[:,:3];tri=read(p['indices']).reshape(-1,3)
            # Weld duplicated UV/normal vertices before finding the pane perimeter.
            _,weld=np.unique(np.round(xyz,4),axis=0,return_inverse=True)
            edges=np.concatenate([tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]]]); keys=np.sort(weld[edges],axis=1)
            _,first,count=np.unique(keys,axis=0,return_index=True,return_counts=True)
            for a,b in edges[first[count==1]]:
                steps=max(2,int(np.linalg.norm(xyz[a]-xyz[b])/0.01)+1)
                samples.extend(np.linspace(xyz[a],xyz[b],steps))
    if not samples: return 0
    samples=np.array(samples)
    # The chrome belt follows the outer window silhouette. Internal dividers
    # (B/C pillars) must remain black, even though they touch two pane edges.
    horizontal=samples[:,[0,2]]
    _,axes=np.linalg.eigh(np.cov(horizontal.T));longAxis=axes[:,-1]
    longitudinal=np.sum(horizontal*longAxis,axis=1)
    def outer_surround(points):
        result=[]
        for v in points:
            u=np.sum(v[[0,2]]*longAxis)
            column=samples[np.abs(longitudinal-u)<0.05,1]
            end=min(abs(u-longitudinal.min()),abs(u-longitudinal.max()))<0.055
            edge=len(column)>0 and min(abs(v[1]-column.min()),abs(v[1]-column.max()))<0.055
            result.append(end or edge)
        return np.array(result,dtype=bool)
    cell=0.07;grid={}
    for v in samples: grid.setdefault(tuple(np.floor(v/cell).astype(int)),[]).append(v)
    def near(points,limit):
        result=[]
        for v in points:
            c=np.floor(v/cell).astype(int);found=False
            for x in (-1,0,1):
                for y in (-1,0,1):
                    for z in (-1,0,1):
                        candidates=grid.get(tuple(c+[x,y,z]))
                        if candidates is not None and np.min(np.sum((np.array(candidates)-v)**2,axis=1))<=limit*limit:
                            found=True;break
                    if found:break
                if found:break
            result.append(found)
        return np.array(result,dtype=bool)
    total=0
    for i,n in enumerate(nodes):
        if 'mesh' not in n: continue
        for p in gltf['meshes'][n['mesh']]['primitives']:
            p.setdefault('extras',{}).pop('windowTrimTriangles',None)
            source=gltf['materials'][p['material']]['extras'].get('sourcePath','').lower().split('/')[-1].split('.')[0]
            if any(part in n.get('name','').lower() for part in ('interior','doorcard','lhd','rhd')): continue
            if source not in ('exterior','exterior_fade','trim','trim_fade','trim2','metal_dark_exterior','plastic_black_exterior'): continue
            xyz=positions(i,p)[:,:3];tri=read(p['indices']).reshape(-1,3)
            # Restrict work to the window neighborhood, then test whole triangles.
            centers=xyz[tri].mean(axis=1);lo=samples.min(axis=0)-cell;hi=samples.max(axis=0)+cell
            ids=np.flatnonzero(np.all((centers>=lo)&(centers<=hi),axis=1))
            ids=ids[near(centers[ids],0.04)]
            ids=ids[outer_surround(centers[ids])]
            if len(ids): ids=ids[near(xyz[tri[ids]].reshape(-1,3),0.065).reshape(-1,3).all(axis=1)]
            if len(ids): ids=ids[outer_surround(xyz[tri[ids]].reshape(-1,3)).reshape(-1,3).all(axis=1)]
            if len(ids): p['extras']['windowTrimTriangles']=ids.tolist();total+=len(ids)
    return total
