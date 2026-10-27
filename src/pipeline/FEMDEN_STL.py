#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""COMSOL FEM displacement export -> six closed, deformed steel/Zn STL volumes.
Uses actual u,v,w sampled on the physical front of the two-sheet reflector.
Interpolation is 2-D inverse-distance weighting; method and support diagnostics saved.
No synthetic deformation fallback is permitted.
"""
import argparse, csv, json, math, pathlib, struct, re
from collections import defaultdict

W=2000.0; H=2000.0; GAP=2.0; CORE=1.2; ZN=.01926
LEFT=(-1000.,-1.); RIGHT=(1.,1000.)

def parse_data(path):
    sample=[]; head=[]
    with open(path,encoding='utf-8-sig',errors='replace') as f:
        for ln in f:
            t=ln.strip()
            if not t or t.startswith(('%','#')):
                if len(head)<35:head.append(t)
                continue
            # COMSOL spreadsheet, e.g. x y z u v w solid.disp
            p=re.split(r'[;\s,]+',t)
            if len(p)<6:continue
            try: a=[float(q) for q in p[:6]]
            except ValueError:continue
            if all(math.isfinite(v) for v in a):sample.append(a)
    if len(sample)<100:
        raise RuntimeError(f'Not enough COMSOL numeric coordinate/displacement rows in {path}: {len(sample)}; header: {head[:8]}')
    max_coord=max(max(abs(x[0]),abs(x[1])) for x in sample)
    # Default COMSOL model/export coordinates are metres. Millimetres must be detected.
    if 0.8<max_coord<3.5: coord_to_mm=1000.0
    elif 800.<max_coord<3500.: coord_to_mm=1.0
    else:raise RuntimeError(f'Unexpected x/y coordinate extent {max_coord}; expected 2m panel')
    # COMSOL displacement expressions u,v,w default to SI meters, even if geometry display unit changes.
    # Explicit header units required if displacement units are not SI.
    headers='\n'.join(head).lower()
    if re.search(r'\bu\s*\(mm\)',headers) or re.search(r'\bu\s*\[mm\]',headers): disp_to_mm=1.0
    elif re.search(r'\bu\s*\(m\)',headers) or re.search(r'\bu\s*\[m\]',headers):disp_to_mm=1000.0
    else:disp_to_mm=1000.0 # COMSOL default SI; validated against expected FEM displacement below
    out=[]
    for a in sample:
        x,y,z=(q*coord_to_mm for q in a[:3]); u,v,w=(q*disp_to_mm for q in a[3:6])
        if -1002<x<1002 and -1002<y<1002 and abs(z)<0.08 and (x<-1.1 or x>1.1):
            out.append((x,y,u,v,w))
    if len(out)<80:
        raise RuntimeError(f'Only {len(out)} upper-sheet samples (z near 0mm). Check COMSOL export includes coordinates and front-face field.')
    max_d=max(math.sqrt(u*u+v*v+w*w) for x,y,u,v,w in out)
    if not 0.<max_d<20.:
        raise RuntimeError(f'Displacement magnitude {max_d}mm implausible; check unit format and front-surface selection')
    return out,{'total_numeric_rows':len(sample),'front_surface_rows':len(out),'xy_coord_to_mm':coord_to_mm,'uvw_to_mm':disp_to_mm,'max_front_displacement_mm':max_d,'header_preview':head[:12]}

class Field:
    def __init__(self,points,cell=45.):
        self.cell=cell;self.cells=defaultdict(list)
        for p in points:self.cells[(math.floor(p[0]/cell),math.floor(p[1]/cell))].append(p)
        self.max_support=0.;self.ninterpolated=0
    def get(self,x,y):
        ix=math.floor(x/self.cell);iy=math.floor(y/self.cell)
        found=[]
        for ring in range(0,5):
            for i in range(ix-ring,ix+ring+1):
                for j in range(iy-ring,iy+ring+1):
                    if ring and max(abs(i-ix),abs(j-iy))!=ring:continue
                    for p in self.cells.get((i,j),()):
                        d2=(p[0]-x)**2+(p[1]-y)**2
                        found.append((d2,p))
            if len(found)>=8:break
        if len(found)<3:raise RuntimeError(f'Insufficient FEM support points near x={x:.1f},y={y:.1f}mm')
        found.sort(key=lambda z:z[0]);sel=found[:8];dd=math.sqrt(sel[0][0]);self.max_support=max(self.max_support,dd)
        if dd>110.:raise RuntimeError(f'FEM point gap {dd:.1f}mm near x={x:.1f},y={y:.1f}; cannot reliably interpolate')
        if sel[0][0]<1e-14:return tuple(sel[0][1][i] for i in (2,3,4))
        weights=[1/(d2+1.e-4) for d2,p in sel];den=sum(weights)
        self.ninterpolated+=1
        return tuple(sum(we*p[idx] for we,(d2,p) in zip(weights,sel))/den for idx in (2,3,4))

def vunit(v):
    l=math.sqrt(sum(x*x for x in v))
    if l<1.e-9:raise RuntimeError('Degenerate normal')
    return tuple(x/l for x in v)

def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])

def face(a,b,c):
    ab=tuple(b[i]-a[i] for i in range(3));ac=tuple(c[i]-a[i] for i in range(3))
    n=vunit(cross(ab,ac)); vol=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6
    return struct.pack('<12fH',*n,*a,*b,*c,0),vol

def stl(path,base,normals,top_offset,bot_offset):
    Nx=len(base);Ny=len(base[0]);top=[];bot=[]
    for i in range(Nx):
        top.append([]);bot.append([])
        for j in range(Ny):
            p=base[i][j];n=normals[i][j]
            top[i].append(tuple(p[k]+top_offset*n[k] for k in range(3)))
            bot[i].append(tuple(p[k]+bot_offset*n[k] for k in range(3)))
    triangles=0;vol=0.
    with open(path,'wb') as f:
        f.write(b'PASSBRIDGE COMSOL FEM REAL displacement STL'.ljust(80,b' '));f.write(struct.pack('<I',0))
        def t(a,b,c):
            nonlocal triangles,vol
            raw,v=face(a,b,c);f.write(raw);triangles+=1;vol+=v
        for i in range(Nx-1):
            for j in range(Ny-1):
                a,b,c,d=top[i][j],top[i+1][j],top[i+1][j+1],top[i][j+1]
                t(a,b,c);t(a,c,d)
                a,b,c,d=bot[i][j],bot[i+1][j],bot[i+1][j+1],bot[i][j+1]
                t(a,d,c);t(a,c,b)
            t(top[i][0],bot[i][0],bot[i+1][0]);t(top[i][0],bot[i+1][0],top[i+1][0]);j=Ny-1
            t(top[i][j],top[i+1][j],bot[i+1][j]);t(top[i][j],bot[i+1][j],bot[i][j])
        for j in range(Ny-1):
            t(top[0][j],top[0][j+1],bot[0][j+1]);t(top[0][j],bot[0][j+1],bot[0][j]);i=Nx-1
            t(top[i][j],bot[i][j],bot[i][j+1]);t(top[i][j],bot[i][j+1],top[i][j+1])
        f.seek(80);f.write(struct.pack('<I',triangles))
    if not (vol>0):raise RuntimeError(f'Invalid/negative volume for {path}: {vol}')
    return {'triangles':triangles,'volume_mm3':vol,'file':str(path)}

def make(input_file,dest,wind,grid):
    pts,info=parse_data(input_file);field=Field(pts)
    dest.mkdir(parents=True,exist_ok=True)
    produced=[]; minmaxz=[]
    for side,(xa,xb) in [('Left',LEFT),('Right',RIGHT)]:
        xs=[xa+(xb-xa)*i/(grid-1) for i in range(grid)]
        ys=[-1000.+2000.*j/(grid-1) for j in range(grid)]
        base=[]
        for x in xs:
            row=[]
            for y in ys:
                ux,uy,uz=field.get(x,y)
                row.append((x+ux,y+uy,uz)); minmaxz.append(uz)
            base.append(row)
        normals=[]
        for i in range(grid):
            normals.append([])
            for j in range(grid):
                ai=max(0,i-1);bi=min(grid-1,i+1);aj=max(0,j-1);bj=min(grid-1,j+1)
                p=base[bi][j];q=base[ai][j];r=base[i][bj];s=base[i][aj]
                dx=tuple(p[k]-q[k] for k in range(3));dy=tuple(r[k]-s[k] for k in range(3))
                n=vunit(cross(dx,dy));
                if n[2]<=0:raise RuntimeError('Inverted surface normals')
                normals[-1].append(n)
        for layer,t,b in [('Core',0.,-CORE),('ZincFront',ZN,0.),('ZincBack',-CORE,-CORE-ZN)]:
            name=f'FEM_W{wind}_{layer}_{side}.stl'
            rec=stl(dest/name,base,normals,t,b);rec.update({'layer':layer,'side':side})
            expect=(xb-xa)*H*(t-b)
            if abs(rec['volume_mm3']/expect-1.)>.04:raise RuntimeError(f'STL volume differs >4%: {name}')
            produced.append(rec)
    info.update({'wind_m_s':wind,'source_FEM_file':str(input_file),'geometry_type':'ACTUAL_COMSOL_FEM_UVW_IDW_INTERPOLATION','interpolation':'8-point 2D inverse distance weighting of COMSOL front surface; no synthetic bending field','grid_nodes_per_axis':grid,'max_nearest_support_mm':field.max_support,'front_z_min_mm':min(minmaxz),'front_z_max_mm':max(minmaxz),'layers':produced})
    (dest/'FEM_GEOMETRY_MANIFEST.json').write_text(json.dumps(info,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'wind':wind,'samples':info['front_surface_rows'],'nearest_fem_support_mm':info['max_nearest_support_mm'],'z_range_mm':[info['front_z_min_mm'],info['front_z_max_mm']],'stls':len(produced)}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--input',required=True,type=pathlib.Path);p.add_argument('--out',required=True,type=pathlib.Path);p.add_argument('--wind',type=int,required=True,choices=[15,25,35]);p.add_argument('--grid',type=int,default=41)
    q=p.parse_args();assert 15<=q.grid<=101
    make(q.input,q.out,q.wind,q.grid)
