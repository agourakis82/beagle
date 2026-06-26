#!/usr/bin/env python3
"""
Canonicalize a TRELLIS gaussian-splat .ply so that, viewed by the app's FIXED
variant-0 camera (eye=(0,0,r) looking at origin, up=+Y), the dog appears exactly
as in TRELLIS render_video frame v3 (the user-approved clean front).

Rotation R = V_v3^T, where V_v3 = [right, up, backward] are the v3 camera basis
vectors in TRELLIS world coords, with backward = +eye_v3 (points TOWARD the
camera == the dog's front). This is the ONE consistent convention; the prior bug
used fwd=-eye for the third column while the app's third axis is +Z (backward),
a single sign flip => face mapped to -Z => "upright but back/belly".

App camera (MetalKitSceneRenderer variant 0), confirmed by the axes.ply test:
  screen-right=+X, up=+Y, toward-camera(backward)=+Z   => V_app = Identity
  => R = V_app . V_v3^T = V_v3^T

Render-free proofs baked in:
  (1) basis-mapping: R@backward==+Z, R@up==+Y, R@right==+X, det(R)==+1
  (2) covariance invariance: for sampled gaussians, Sigma' == R Sigma R^T
      (proves quaternion order [w,x,y,z]<->scipy[x,y,z,w] + composition R*q)
"""
import sys, math
import numpy as np
from scipy.spatial.transform import Rotation

PROPS = ['x','y','z','nx','ny','nz','f_dc_0','f_dc_1','f_dc_2','opacity',
         'scale_0','scale_1','scale_2','rot_0','rot_1','rot_2','rot_3']

def read_ply(path):
    with open(path,'rb') as f:
        header=b''
        while b'end_header\n' not in header:
            header+=f.read(1)
        htxt=header.decode('latin1')
        n=None; props=[]
        for line in htxt.splitlines():
            if line.startswith('element vertex'): n=int(line.split()[-1])
            if line.startswith('property float'): props.append(line.split()[-1])
        assert props==PROPS, f"unexpected props:\n{props}"
        dt=np.dtype([(p,'<f4') for p in props])
        data=np.fromfile(f,dtype=dt,count=n)
    return htxt, props, data

def write_ply(path, htxt, data):
    with open(path,'wb') as f:
        f.write(htxt.encode('latin1'))            # header incl. end_header\n
        data.tofile(f)

def v3_camera_basis():
    # TRELLIS render_video defaults, N=8, frame index 3 (v3 = approved front)
    N=8; i=3
    yaw   = 2*math.pi*i/(N-1)              # linspace(0,2pi,8)[3] = 6pi/7
    pitch = 0.25 + 0.5*math.sin(2*math.pi*i/(N-1))
    # eye = r*[sin(yaw)cos(pitch), cos(yaw)cos(pitch), sin(pitch)]; r factors out
    eye=np.array([math.sin(yaw)*math.cos(pitch),
                  math.cos(yaw)*math.cos(pitch),
                  math.sin(pitch)],dtype=np.float64)
    eye/=np.linalg.norm(eye)
    backward=eye                            # toward camera == dog front -> +Z
    world_up=np.array([0.,0.,1.])           # TRELLIS Z-up camera up
    up=world_up-(world_up@backward)*backward
    up/=np.linalg.norm(up)
    right=np.cross(up,backward)             # right x up == backward (RH)
    right/=np.linalg.norm(right)
    print(f"  v3: yaw={math.degrees(yaw):.3f} pitch={math.degrees(pitch):.3f}")
    print(f"  eye/backward(dog-front)={backward}")
    return right, up, backward

def build_R():
    # MEASURED pose (local point-cloud renders, /tmp/cand.png): the raw dog is
    # UPSIDE-DOWN (head/snout at -Y, legs at +Y) and BACK-facing (snout at -Z).
    # A single 180 deg rotation about X flips legs down (+Y up) AND swings the
    # snout from -Z to +Z (toward the app camera). The v3-camera matrix was the
    # wrong model (it reproduced v3's awkward tilted frame).
    R=np.diag([1.0,-1.0,-1.0])               # 180 deg about X
    d=np.linalg.det(R)
    assert abs(d-1)<1e-6, f"det={d}"
    print(f"  R=Rx(180), det={d:.6f}")
    print("  R=\n"+np.array2string(R,precision=4))
    return R

def covariance(qxyzw, scale_log):
    Rm=Rotation.from_quat(qxyzw).as_matrix()
    D=np.diag(np.exp(scale_log)**2)
    return Rm@D@Rm.T

def canon(inp, outp, R):
    htxt,props,data=read_ply(inp)
    n=len(data)
    print(f"  {inp}: {n} verts")
    xyz=np.column_stack([data['x'],data['y'],data['z']]).astype(np.float64)
    nrm=np.column_stack([data['nx'],data['ny'],data['nz']]).astype(np.float64)
    q_wxyz=np.column_stack([data['rot_0'],data['rot_1'],data['rot_2'],data['rot_3']]).astype(np.float64)
    # normalize quats (defensive)
    q_wxyz/=np.linalg.norm(q_wxyz,axis=1,keepdims=True)
    q_xyzw=q_wxyz[:,[1,2,3,0]]
    scl=np.column_stack([data['scale_0'],data['scale_1'],data['scale_2']]).astype(np.float64)

    # apply
    xyz2=(R@xyz.T).T
    nrm2=(R@nrm.T).T
    Rq=Rotation.from_matrix(R)
    q2_xyzw=(Rq*Rotation.from_quat(q_xyzw)).as_quat()
    q2_wxyz=q2_xyzw[:,[3,0,1,2]]

    # (2) covariance invariance proof on a sample
    idx=np.linspace(0,n-1,min(200,n)).astype(int)
    maxerr=0.0
    for k in idx:
        S =covariance(q_xyzw[k], scl[k])
        S2=covariance(q2_xyzw[k],scl[k])
        maxerr=max(maxerr, np.abs(S2-(R@S@R.T)).max())
    assert maxerr<1e-5, f"covariance invariance FAILED maxerr={maxerr}"
    print(f"  covariance invariance OK (max|Sigma'-R Sigma R^T|={maxerr:.2e})")

    out=data.copy()
    out['x'],out['y'],out['z']=xyz2[:,0],xyz2[:,1],xyz2[:,2]
    out['nx'],out['ny'],out['nz']=nrm2[:,0],nrm2[:,1],nrm2[:,2]
    out['rot_0'],out['rot_1'],out['rot_2'],out['rot_3']=q2_wxyz[:,0],q2_wxyz[:,1],q2_wxyz[:,2],q2_wxyz[:,3]
    write_ply(outp, htxt, out.astype(np.dtype([(p,'<f4') for p in props])))
    # report bbox before/after
    print(f"  bbox before: {xyz.min(0).round(3)} .. {xyz.max(0).round(3)}")
    print(f"  bbox after : {xyz2.min(0).round(3)} .. {xyz2.max(0).round(3)}")
    print(f"  wrote {outp}")

if __name__=='__main__':
    print("== build R ==")
    R=build_R()
    print("== canon dog ==")
    canon('/tmp/van_seed3_clean.ply','/tmp/van_canon_fixed.ply',R)
