#!/usr/bin/env python3
"""Local render-free preview of a canon ply: orthographic point-cloud from N yaws,
colored by SH-DC color, to FIND which yaw faces the camera. Camera convention matches
the app: looking down -Z by default (yaw 0), up=+Y; yaw φ orbits horizontally."""
import numpy as np, math
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

PROPS=['x','y','z','nx','ny','nz','f_dc_0','f_dc_1','f_dc_2','opacity','scale_0','scale_1','scale_2','rot_0','rot_1','rot_2','rot_3']
def read(path):
    f=open(path,'rb');h=b''
    while b'end_header\n' not in h:h+=f.read(1)
    n=[int(l.split()[-1]) for l in h.decode('latin1').splitlines() if l.startswith('element vertex')][0]
    return np.fromfile(f,dtype=np.dtype([(p,'<f4') for p in PROPS]),count=n)

d=read('/tmp/van_canon_fixed.ply')
xyz=np.column_stack([d['x'],d['y'],d['z']]).astype(float)
C0=0.28209479
col=np.clip(0.5+C0*np.column_stack([d['f_dc_0'],d['f_dc_1'],d['f_dc_2']]),0,1)
op=1/(1+np.exp(-d['opacity']))
m=op>0.4
xyz,col=xyz[m],col[m]
# subsample for speed
if len(xyz)>120000:
    s=np.random.default_rng(0).choice(len(xyz),120000,replace=False); xyz,col=xyz[s],col[s]

yaws=[0,45,90,135,180,225,270,315]
fig,axes=plt.subplots(2,4,figsize=(16,9),facecolor='black')
for ax,phi in zip(axes.ravel(),yaws):
    p=math.radians(phi)
    sx= xyz[:,0]*math.cos(p)-xyz[:,2]*math.sin(p)   # screen right
    sy= xyz[:,1]                                     # screen up (+Y)
    depth= xyz[:,0]*math.sin(p)+xyz[:,2]*math.cos(p) # toward camera (larger=nearer)
    o=np.argsort(depth)                              # painter: far first
    ax.scatter(sx[o],sy[o],c=col[o],s=2,marker='.',linewidths=0)
    ax.set_title(f"yaw {phi}",color='white',fontsize=11)
    ax.set_facecolor('black'); ax.set_aspect('equal')
    ax.set_xlim(-0.7,0.7); ax.set_ylim(-0.7,0.7); ax.axis('off')
plt.tight_layout()
plt.savefig('/tmp/preview_grid.png',dpi=70,facecolor='black')
print("saved /tmp/preview_grid.png")
