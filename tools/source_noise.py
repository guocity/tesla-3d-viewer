"""Generate the APK's seamless NoiseTexture using Godot's OpenSimplex routine."""
import ctypes
import io
import math
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path
from PIL import Image

@lru_cache(maxsize=1)
def airflow_noise():
    vendor = Path(__file__).parent/'vendor'
    with tempfile.TemporaryDirectory(prefix='tesla-noise-') as tmp:
        library = Path(tmp)/'noise.dylib'
        subprocess.run(['cc','-O3','-shared','-fPIC',str(vendor/'open-simplex-noise.c'),'-o',str(library)],check=True)
        lib=ctypes.CDLL(str(library))
        class Context(ctypes.Structure):
            _fields_=[('perm',ctypes.c_int16*256),('permGradIndex3D',ctypes.c_int16*256)]
        lib.open_simplex_noise.argtypes=[ctypes.c_int64,ctypes.POINTER(Context)]
        lib.open_simplex_noise4.argtypes=[ctypes.POINTER(Context)]+[ctypes.c_double]*4
        lib.open_simplex_noise4.restype=ctypes.c_double
        ctx=Context();lib.open_simplex_noise(0,ctypes.byref(ctx))
        # noiseTexture.tres: seamless=true, default 512px, octaves=1, period=90.2.
        size=512; radius=size/(2*math.pi);period=ctypes.c_float(90.2).value
        data=bytearray(size*size)
        for y in range(size):
            for x in range(size):
                xx=ctypes.c_float(radius*math.sin(x/size*2*math.pi)).value/period
                yy=ctypes.c_float(radius*math.cos(x/size*2*math.pi)).value/period
                zz=ctypes.c_float(radius*math.sin(y/size*2*math.pi)).value/period
                ww=ctypes.c_float(radius*math.cos(y/size*2*math.pi)).value/period
                value=lib.open_simplex_noise4(ctypes.byref(ctx),xx,yy,zz,ww)
                data[y*size+x]=max(0,min(255,int((value*0.5+0.5)*255)))
        out=io.BytesIO();Image.frombytes('L',(size,size),bytes(data)).save(out,format='PNG')
        return out.getvalue()
