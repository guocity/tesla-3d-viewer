import Foundation

public struct ShaderSource {
    public static let metalRaytracingSource = """
    #include <metal_stdlib>
    #include <metal_raytracing>
    using namespace metal;
    using namespace metal::raytracing;

    // 48-byte 16-byte aligned vertex structure matching Swift SIMD4<Float> layout exactly
    struct Vertex {
        float4 position;
        float4 uv;
        float4 normal;
    };

    // 80-byte 16-byte aligned geometry metadata
    struct GeometryInfo {
        float4 emission; // independent emission tint, texture index
        int4 textures;
        uint opticalGroup;
        uint indexOffset;
        uint isGround;
        uint isPaint;
        float4 baseColor;
        float4 params;
    };

    // 16-byte aligned Uniforms structure matching Swift UniformsGPU layout exactly
    struct Uniforms {
        float4 effectParams;
        int4 effectTextures;
        float4x4 climateLeft;
        float4x4 climateRight;
        float4x4 invView;
        float4x4 invProj;
        float4 cameraPos;
        float4 carPaintColor;
        float4 params;
        uint4 viewport;
        float4 tintParams;
        float4 interiorFinish;
        float4 rearStrip;
        float4 rearStripSize;
        float4x4 rearStripDepths;
        float4 headlampLeft;
        float4 headlampRight;
        float4 weather; // rain density, surface wetness, weather time, reserved
        float4 renderOptions; // lighting preset, exposure, window trim, lens reflection
    };

    struct Lighting {
        float3 keyPosition;
        float3 keyColor;
        float3 ambientColor;
        float3 groundColor;
        float softSize;
    };
    static Lighting lightingForPreset(float preset) {
        if (preset < 0.5) return {float3(5.5,9.5,6.5),float3(2.0,1.94,1.85),float3(0.16,0.18,0.21),float3(0.05,0.055,0.062),3.0};
        if (preset < 1.5) return {float3(-8,35,15),float3(1.25,1.35,1.5),float3(0.42,0.48,0.58),float3(0.16,0.175,0.19),22.0};
        if (preset < 2.5) return {float3(-45,12,32),float3(3.6,1.95,0.82),float3(0.22,0.30,0.46),float3(0.17,0.13,0.095),1.2};
        if (preset > 4.5) return {float3(-18,25,12),float3(1.6,1.85,2.2),float3(0.24,0.30,0.38),float3(0.065,0.075,0.085),14.0};
        if (preset > 3.5) return {float3(5,8,5),float3(1.3,1.65,2.1),float3(0.085,0.12,0.19),float3(0.025,0.032,0.045),2.0};
        return {float3(22,9,-30),float3(0.8,1.05,1.7),float3(0.14,0.21,0.38),float3(0.07,0.085,0.12),4.0};
    }

    // Deterministic world-space detail: no downloaded textures or scene assets.
    static float hash21(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
    static float noise2(float2 p) {
        float2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
        return mix(mix(hash21(i),hash21(i+float2(1,0)),f.x),mix(hash21(i+float2(0,1)),hash21(i+1.0),f.x),f.y);
    }
    static float puddleAt(float2 p) {
        return smoothstep(0.38,0.67,noise2(p*0.38)*0.7+noise2(p*1.1)*0.3);
    }
    static float3 wetNormal(float2 p, float time, float amount) {
        float2 cell=floor(p*2.4), local=fract(p*2.4)-0.5;
        float phase=fract(time*0.8+hash21(cell));
        float radius=length(local);
        float ring=sin((radius-phase*0.65)*65.0)*exp(-abs(radius-phase*0.65)*22.0)*(1.0-phase);
        float2 slope=local/max(radius,0.02)*ring*0.025;
        slope+=float2(sin(p.x*91.0+p.y*47.0),cos(p.y*83.0-p.x*29.0))*0.008;
        return normalize(float3(slope.x*amount,1.0,slope.y*amount));
    }

    static float3 sampleEnvironment(float3 dir, float preset) {
        float y = clamp(dir.y, -1.0, 1.0);
        if (preset > 3.5) {
            float angle=atan2(dir.z,dir.x);
            float az=(angle+3.14159265)*10.0;
            float building=floor(az);
            float height=0.10+hash21(float2(building,7))*0.31;
            float3 sky=mix(float3(0.17,0.23,0.32),float3(0.008,0.018,0.045),pow(max(y,0.0),0.45));
            if (preset > 4.5) {
                sky=mix(float3(0.45,0.53,0.62),float3(0.09,0.14,0.23),pow(max(y,0.0),0.5));
                float cloud=noise2(dir.xz/max(abs(y)+0.15,0.15)*4.0);
                sky*=0.70+cloud*0.3;
                float ridge=0.025+0.05*sin(angle*7.0)+0.025*sin(angle*19.0);
                if (y < ridge && y > -0.06) sky=float3(0.055,0.075,0.085)*(0.7+noise2(dir.xz*50.0)*0.3);
                return sky;
            }
            // Distant skyline with independently lit windows and neon light ribbons.
            if (y < height && y > -0.02) {
                float2 windowUV=float2(fract(az)*9.0,y*110.0);
                float2 pane=fract(windowUV);
                float lit=step(0.57,hash21(floor(windowUV)+float2(building*17.0,0)));
                float mask=smoothstep(0.12,0.23,pane.x)*(1.0-smoothstep(0.70,0.83,pane.x))
                          *smoothstep(0.12,0.24,pane.y)*(1.0-smoothstep(0.62,0.78,pane.y));
                float3 tint=mix(float3(0.35,0.7,1.0),float3(1.0,0.48,0.22),hash21(float2(building,3)));
                sky=float3(0.009,0.014,0.025)+tint*mask*lit*0.65;
                float sign=exp(-abs(fract(az)-0.25)*95.0)*step(0.04,y)*step(y,height*0.8);
                sky+=mix(float3(0.02,2.8,4.5),float3(4.0,0.06,0.65),step(0.5,hash21(float2(building,2))))*sign;
            }
            float cyan=pow(max(dot(dir,normalize(float3(-1,0.24,0.6))),0.0),150.0);
            float pink=pow(max(dot(dir,normalize(float3(0.7,0.18,-1))),0.0),190.0);
            sky+=float3(0.03,2.5,4.0)*cyan+float3(4.5,0.08,0.7)*pink;
            float overhead=pow(max(dot(dir,normalize(float3(0.3,1,0.2))),0.0),8.0);
            sky+=float3(0.65,0.78,0.95)*overhead;
            return sky;
        }
        if (preset >= 0.5) {
            float3 zenith, horizon, ground;
            if (preset < 1.5) {
                zenith=float3(0.5,0.6,0.75); horizon=float3(0.85,0.88,0.9); ground=float3(0.15,0.17,0.19);
            } else if (preset < 2.5) {
                zenith=float3(0.16,0.29,0.52); horizon=float3(1.05,0.51,0.20); ground=float3(0.14,0.10,0.07);
            } else {
                zenith=float3(0.035,0.075,0.18); horizon=float3(0.3,0.25,0.37); ground=float3(0.035,0.045,0.07);
            }
            float3 sky = y >= 0 ? mix(horizon,zenith,pow(y,0.45)) : mix(horizon,ground,smoothstep(0.0,0.22,-y));
            Lighting l=lightingForPreset(preset);
            float sun=max(dot(dir,normalize(l.keyPosition)),0.0);
            if (preset > 1.5) sky += l.keyColor*(pow(sun,600.0)*3.0+pow(sun,12.0)*0.12);
            return sky;
        }
        // Automotive photo studio: dark cyclorama, a large overhead softbox and
        // long strip lights that draw crisp highlight lines along the body.
        float3 bg = y >= 0 ? mix(float3(0.075,0.080,0.090),float3(0.018,0.020,0.024),pow(y,0.55))
                              : mix(float3(0.075,0.080,0.090),float3(0.012),smoothstep(0.0,0.35,-y));
        if (dir.y > 0.05) {
            float2 q = dir.xz/dir.y;
            float box = (1.0-smoothstep(0.62,0.70,abs(q.x)))*(1.0-smoothstep(0.30,0.36,abs(q.y)));
            float diffuser = 0.88+0.12*(1.0-smoothstep(0.0,0.7,length(q*float2(1.0,1.8))));
            bg += float3(5.2,5.2,5.4)*box*diffuser;
            // Soft spill halo around the softbox frame.
            bg += float3(0.10,0.11,0.13)*(1.0-smoothstep(0.6,1.6,length(q*float2(0.9,1.6))));
        }
        for (int s = -1; s <= 1; s += 2) {
            float side = float(s);
            if (dir.z*side > 0.08) {
                float2 q = dir.xy/abs(dir.z);
                // Two horizontal strips per side at different heights.
                float upper = 1.0-smoothstep(0.012,0.022,abs(q.y-0.62));
                float lower = 1.0-smoothstep(0.008,0.016,abs(q.y-0.26));
                float len = 1.0-smoothstep(1.6,1.75,abs(q.x));
                bg += float3(7.5,7.6,8.0)*upper*len + float3(3.0,3.05,3.2)*lower*len;
            }
            if (dir.x*side > 0.08) {
                // Vertical rim strips at the front and rear corners.
                float2 q = dir.zy/abs(dir.x);
                float rim = (1.0-smoothstep(0.015,0.03,abs(abs(q.x)-0.85)))*smoothstep(-0.05,0.02,q.y)*(1.0-smoothstep(0.9,1.0,q.y));
                bg += float3(3.2,3.3,3.6)*rim;
            }
        }
        // Cool bounce card on camera-left.
        bg += float3(0.10,0.16,0.26)*pow(max(dot(dir,normalize(float3(-0.8,0.35,0.4))),0.0),6.0);
        return bg;
    }

    // What the camera sees directly. In the studio the light fixtures sit
    // off-camera: they appear in reflections, not as objects in the backdrop.
    static float3 sampleBackdrop(float3 dir, float preset) {
        if (preset >= 0.5) return sampleEnvironment(dir, preset);
        float y = clamp(dir.y, -1.0, 1.0);
        float3 bg = y >= 0 ? mix(float3(0.075,0.080,0.090),float3(0.018,0.020,0.024),pow(y,0.55))
                           : mix(float3(0.075,0.080,0.090),float3(0.012),smoothstep(0.0,0.35,-y));
        return bg + float3(0.05,0.055,0.065)*pow(max(y,0.0),3.0);
    }

    static void applyFinish(thread GeometryInfo &mat, constant Uniforms &uniforms) {
        if (uniforms.interiorFinish.x > 0.5 && (mat.textures.w & (2097152 | 4194304)) != 0) {
            bool seat = (mat.textures.w & 2097152) != 0;
            mat.baseColor = float4(0.82,0.84,0.86,0.0);
            mat.params.x = seat ? 0.84 : 0.78;
            mat.params.y = 0.0;
            // The source black albedo atlas would darken a white color override.
            // Keep the separate source AO, UVs and geometry intact.
            mat.textures.x = -1; mat.textures.y = -1;
            if (seat) mat.textures.w |= 1048576;
        }
        if ((mat.textures.w & 1024) == 0 || uniforms.renderOptions.z < 0.5) return;
        bool chrome = uniforms.renderOptions.z < 1.5;
        mat.baseColor = chrome ? float4(0.82,0.85,0.89,1.0) : float4(0.012,0.015,0.018,0.0);
        mat.params.x = chrome ? 0.13 : 0.32;
        mat.params.y = chrome ? 0.0 : 0.15;
        mat.textures.x = -1; mat.textures.y = -1;
    }

    static float3 fresnelSchlick(float cosTheta, float3 f0) {
        return f0+(1.0-f0)*pow(1.0-clamp(cosTheta,0.0,1.0),5.0);
    }
    static float3 directBRDF(float3 n, float3 v, float3 l, float3 base, float metal, float rough) {
        float3 h=normalize(v+l);
        float nv=max(dot(n,v),0.001), nl=max(dot(n,l),0.0), nh=max(dot(n,h),0.0);
        float a=max(rough*rough,0.018), a2=a*a;
        float d=nh*nh*(a2-1.0)+1.0;
        float D=a2/max(3.14159265*d*d,0.000001);
        float gv=2.0*nv/(nv+sqrt(a2+(1.0-a2)*nv*nv));
        float gl=2.0*nl/max(nl+sqrt(a2+(1.0-a2)*nl*nl),0.001);
        float3 F=fresnelSchlick(dot(v,h),mix(float3(0.04),base,metal));
        return ((1.0-F)*base*(1.0-metal)/3.14159265 + D*gv*gl*F/max(4.0*nv*nl,0.001))*nl;
    }
    // Recessed rear-panel wash from the downward-facing parking strip.
    // Finite width and a tight rear-housing depth keep light off bumper/cabin.
    static float3 rearPanelLight(float3 p, float3 n, float3 v, float3 base, float metal, float rough, constant Uniforms &u) {
        if (u.rearStrip.w<=0.0) return float3(0);
        float3 source=u.rearStrip.xyz;
        source.z=clamp(p.z,source.z-u.rearStripSize.x,source.z+u.rearStripSize.x);
        float along=clamp((source.z-u.rearStrip.z+u.rearStripSize.x)/(2.0*u.rearStripSize.x),0.0,1.0)*15.0;
        uint a=min(uint(along),14u), b=a+1u;
        source.x=mix(u.rearStripDepths[a/4u][a%4u],u.rearStripDepths[b/4u][b%4u],along-float(a));
        float drop=source.y-p.y;
        float depth=p.x-source.x;
        float mask=smoothstep(0.0,0.012,drop)*(1.0-smoothstep(0.035,0.065,drop))
                  *(1.0-smoothstep(0.08,0.18,abs(depth)))
                  *(1.0-smoothstep(u.rearStripSize.x,u.rearStripSize.x+0.04,abs(p.z-u.rearStrip.z)));
        float3 delta=source-p;
        float distance=max(length(delta),0.015);
        float3 direction=delta/distance;
        float down=max(direction.y,0.0);
        return directBRDF(n,v,direction,base,metal,max(rough,0.45))*float3(1.0,0.004,0.001)
               *u.rearStrip.w*down*mask*1.8/(0.012+distance*distance);
    }
    static float3 emittedLight(GeometryInfo mat, float4 uv, array<texture2d<float>,32> textures, constant Uniforms &u) {
        uint signals=uint(u.effectParams.w);
        bool indicating=((mat.textures.w & 32768)!=0 && (signals & 2u)!=0)
                      || ((mat.textures.w & 262144)!=0 && (signals & 4u)!=0);
        if (indicating && (signals & 1u)==0) return float3(0);
        float3 e=mat.emission.xyz;
        if (mat.emission.w>=0.0) {
            constexpr sampler smp(coord::normalized,address::repeat,filter::linear);
            float2 coords=(mat.textures.w & 4096)!=0 ? uv.zw : uv.xy;
            e*=pow(max(textures[int(mat.emission.w)].sample(smp,coords).rgb,0.0),float3(2.2));
        }
        return e*mat.params.z;
    }
    static float3 surfaceRadiance(GeometryInfo mat, float3 n, float3 v, float3 p, float4 uv,
                                  constant Uniforms &u, array<texture2d<float>,32> textures) {
        constexpr sampler smp(coord::normalized,address::repeat,filter::linear);
        applyFinish(mat,u);
        float3 base=mat.isPaint==1 ? u.carPaintColor.xyz : mat.baseColor.xyz;
        if (mat.textures.x>=0 && (mat.textures.w & 16)==0)
            base*=pow(max(textures[mat.textures.x].sample(smp,uv.xy).rgb,0.0),float3(2.2));
        float metal=mat.isPaint==1 ? u.carPaintColor.w : mat.baseColor.w;
        float rough=mat.isPaint==1 ? u.params.x : mat.params.x;
        Lighting l=lightingForPreset(u.renderOptions.x);
        float3 env=sampleEnvironment(reflect(-v,n),u.renderOptions.x);
        float3 F=fresnelSchlick(dot(n,v),mix(float3(0.04),base,metal));
        if ((mat.textures.w & 1048576)!=0) F *= 0.18;
        return directBRDF(n,v,normalize(l.keyPosition-p),base,metal,max(rough,sqrt(l.softSize/max(length(l.keyPosition-p),1.0))*0.36))*l.keyColor
             +rearPanelLight(p,n,v,base,metal,rough,u)+base*l.ambientColor*(1.0-metal)+env*F*(1.0-rough*0.5)+(mat.isGround==4 ? base*mat.params.z : emittedLight(mat,uv,textures,u));
    }

    // Visibility to the source airflow plane. Transparent interfaces transmit;
    // every opaque triangle, including a body panel behind a window, blocks it.
    static float airflowVisibility(float3 origin, float3 direction, float distance,
                                    primitive_acceleration_structure accel,
                                    constant GeometryInfo *geometries) {
        intersector<triangle_data> inter;
        ray r; r.origin=origin; r.direction=direction; r.min_distance=0.0002;
        float remaining=distance-0.001, visibility=1.0;
        for (int layer=0; layer<24 && remaining>0.0; ++layer) {
            r.max_distance=remaining;
            auto h=inter.intersect(r,accel);
            if (h.type == intersection_type::none) return visibility;
            GeometryInfo m=geometries[h.geometry_id];
            if (m.params.w <= 0.01) return 0.0;
            visibility *= m.params.w;
            float step=h.distance+0.0004;
            r.origin += direction*step; remaining -= step;
        }
        return remaining <= 0.0 ? visibility : 0.0;
    }

    // High quality pseudo-random number generator for anti-aliasing & glossy reflections
    static float rand(thread uint &seed) {
        seed = seed * 1664525u + 1013904223u;
        return float(seed & 0x00FFFFFFu) / float(0x01000000u);
    }

    kernel void climateOcclusionProbe(
        primitive_acceleration_structure accel [[buffer(0)]],
        constant GeometryInfo *geometries [[buffer(1)]],
        device float *results [[buffer(2)]], uint id [[thread_position_in_grid]]) {
        if (id < 5) results[id] = airflowVisibility(float3(float(id)*2.0,0,-2),float3(0,0,1),4.0,accel,geometries);
    }

    // Honor source face culling using the authored normals, including interior
    // light blockers that must not cover an exterior lamp when seen from behind.
    static typename intersector<triangle_data>::result_type intersectVisible(
        ray r, primitive_acceleration_structure accel, device const Vertex *vertices,
        device const uint *indices, constant GeometryInfo *geometries, constant Uniforms &u) {
        intersector<triangle_data> tracer;
        auto h=tracer.intersect(r,accel);
        for (int layer=0;layer<24 && h.type==intersection_type::triangle;++layer) {
            GeometryInfo m=geometries[h.geometry_id];
            uint signal=uint(u.effectParams.w);
            bool darkIndicator=(m.textures.w & 524288)!=0 && (signal & 1u)==0
                && (((m.textures.w & 32768)!=0 && (signal & 2u)!=0)
                 || ((m.textures.w & 262144)!=0 && (signal & 4u)!=0));
            if (darkIndicator) {
                r.min_distance=h.distance+0.00001;
                h=tracer.intersect(r,accel); continue;
            }
            if ((m.textures.w & (8192|16384))==0) return h;
            uint offset=m.indexOffset+h.primitive_id*3;
            float2 b=h.triangle_barycentric_coord;
            float3 n=vertices[indices[offset]].normal.xyz*(1.0-b.x-b.y)
                     +vertices[indices[offset+1]].normal.xyz*b.x+vertices[indices[offset+2]].normal.xyz*b.y;
            if ((m.textures.w & 16384)!=0 ? dot(n,r.direction)>0.0 : dot(n,r.direction)<0.0) return h;
            r.min_distance=h.distance+0.0001;
            h=tracer.intersect(r,accel);
        }
        return h;
    }

    static float opticalTransmission(GeometryInfo m, constant Uniforms &u) {
        if (m.params.w <= 0.01) return 0.0;
        return (m.textures.w & 512)!=0 && u.tintParams.x > 0.5 ? u.tintParams.y : m.params.w;
    }
    // Several source surfaces describe the two sides of one pane. Absorption
    // belongs to that pane once; another window farther along the ray adds its own.
    static float paneAttenuation(GeometryInfo m, float distance, constant Uniforms &u,
                                  thread uint &group, thread float &paneTransmission) {
        float t=opticalTransmission(m,u);
        if (m.opticalGroup==group && distance<0.04) {
            float next=min(paneTransmission,t);
            float factor=next/max(paneTransmission,0.0001);
            paneTransmission=next; return factor;
        }
        group=m.opticalGroup; paneTransmission=t; return t;
    }
    static float lightVisibility(ray r, primitive_acceleration_structure accel,
                                 device const Vertex *vertices, device const uint *indices,
                                 constant GeometryInfo *geometries, constant Uniforms &u) {
        float visibility=1.0, paneTransmission=1.0;
        uint group=0xffffffffu;
        for (int layer=0;layer<24;++layer) {
            auto h=intersectVisible(r,accel,vertices,indices,geometries,u);
            if (h.type!=intersection_type::triangle) return visibility;
            GeometryInfo m=geometries[h.geometry_id];
            if (m.params.w<=0.01) return 0.0;
            visibility*=paneAttenuation(m,h.distance,u,group,paneTransmission);
            float step=h.distance+0.0004;
            r.origin+=r.direction*step; r.max_distance-=step; r.min_distance=0.0002;
            if (r.max_distance<=r.min_distance) return visibility;
        }
        return 0.0;
    }

    kernel void cabinOpticsProbe(
        primitive_acceleration_structure accel [[buffer(0)]],
        device const Vertex *vertices [[buffer(1)]], device const uint *indices [[buffer(2)]],
        constant GeometryInfo *geometries [[buffer(3)]], constant Uniforms &u [[buffer(4)]],
        device float *results [[buffer(5)]], uint id [[thread_position_in_grid]]) {
        if (id>=8) return;
        ray r; r.origin=float3(float(id)*2.0,0,-2); r.direction=float3(0,0,1);
        r.min_distance=0.0002; r.max_distance=4.0;
        results[id]=lightVisibility(r,accel,vertices,indices,geometries,u);
    }

    // ------------------------------------------------------------------
    // Physically based sampling helpers
    // ------------------------------------------------------------------
    static float hash31(float3 p) { return fract(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453); }
    static float3 tangentToWorld(float3 local, float3 n) {
        float3 up = abs(n.y) < 0.999 ? float3(0,1,0) : float3(1,0,0);
        float3 t = normalize(cross(up,n));
        float3 b = cross(n,t);
        return normalize(t*local.x + b*local.y + n*local.z);
    }
    static float3 sampleCosine(float3 n, thread uint &seed) {
        float u1 = rand(seed), u2 = rand(seed);
        float r = sqrt(u1), phi = 6.2831853*u2;
        return tangentToWorld(float3(r*cos(phi), r*sin(phi), sqrt(max(0.0,1.0-u1))), n);
    }
    // GGX microfacet importance sampling: reflect the view about a sampled half vector.
    static float3 sampleGGXReflection(float3 n, float3 v, float rough, thread uint &seed) {
        float a = max(rough*rough, 0.0004);
        float u1 = rand(seed), u2 = rand(seed);
        float cosT = sqrt((1.0-u1)/(1.0+(a*a-1.0)*u1));
        float sinT = sqrt(max(0.0,1.0-cosT*cosT)), phi = 6.2831853*u2;
        float3 h = tangentToWorld(float3(sinT*cos(phi), sinT*sin(phi), cosT), n);
        float3 r = reflect(-v,h);
        return dot(r,n) > 0.0 ? r : reflect(-v,n);
    }
    static float3 hitNormal(typename intersector<triangle_data>::result_type h, GeometryInfo m,
                            device const Vertex *vertices, device const uint *indices, float3 dir, thread float4 &uvOut) {
        uint i = m.indexOffset + h.primitive_id*3;
        Vertex a = vertices[indices[i]], b = vertices[indices[i+1]], c = vertices[indices[i+2]];
        float2 bc = h.triangle_barycentric_coord; float w = 1.0-bc.x-bc.y;
        float3 n = normalize(a.normal.xyz*w + b.normal.xyz*bc.x + c.normal.xyz*bc.y);
        uvOut = a.uv*w + b.uv*bc.x + c.uv*bc.y;
        return dot(n,dir) > 0.0 ? -n : n;
    }
    // Radiance arriving along a glossy/specular secondary ray.
    static float3 traceRadiance(float3 origin, float3 dir, float maxDist,
                                primitive_acceleration_structure accel, device const Vertex *vertices,
                                device const uint *indices, constant GeometryInfo *geometries,
                                constant Uniforms &u, array<texture2d<float>,32> textures) {
        ray r; r.origin = origin; r.direction = dir; r.min_distance = 0.01; r.max_distance = maxDist;
        auto h = intersectVisible(r,accel,vertices,indices,geometries,u);
        if (h.type != intersection_type::triangle) return sampleEnvironment(dir,u.renderOptions.x);
        GeometryInfo m = geometries[h.geometry_id];
        applyFinish(m,u);
        Lighting l = lightingForPreset(u.renderOptions.x);
        if (m.isGround == 1) return l.groundColor*(l.ambientColor + l.keyColor*0.25);
        float4 uv; float3 n = hitNormal(h,m,vertices,indices,dir,uv);
        return surfaceRadiance(m,n,-dir,origin+dir*h.distance,uv,u,textures);
    }
    // Conservative one-bounce diffuse estimate: unshadowed key light is omitted
    // so wheel wells, panel gaps and the underbody stay properly occluded.
    static float3 traceIrradiance(float3 origin, float3 dir, primitive_acceleration_structure accel,
                                  device const Vertex *vertices, device const uint *indices,
                                  constant GeometryInfo *geometries, constant Uniforms &u,
                                  array<texture2d<float>,32> textures) {
        ray r; r.origin = origin; r.direction = dir; r.min_distance = 0.004; r.max_distance = 6.0;
        auto h = intersectVisible(r,accel,vertices,indices,geometries,u);
        float transmission=1.0,paneTransmission=1.0;
        uint group=0xffffffffu;
        for (int layer=0;layer<24 && h.type==intersection_type::triangle;++layer) {
            GeometryInfo glass=geometries[h.geometry_id];
            if (glass.params.w<=0.01) break;
            transmission*=paneAttenuation(glass,h.distance,u,group,paneTransmission);
            float step=h.distance+0.0004;
            r.origin+=dir*step; r.max_distance-=step; r.min_distance=0.0002;
            if (r.max_distance<=r.min_distance) return float3(0);
            h=intersectVisible(r,accel,vertices,indices,geometries,u);
        }
        if (h.type != intersection_type::triangle) return sampleEnvironment(dir,u.renderOptions.x)*transmission;
        GeometryInfo m = geometries[h.geometry_id];
        if (m.params.w>0.01) return float3(0);
        applyFinish(m,u);
        Lighting l = lightingForPreset(u.renderOptions.x);
        if (m.isGround == 1) return l.groundColor*(l.ambientColor + l.keyColor*0.12)*transmission;
        float3 base = m.isPaint == 1 ? u.carPaintColor.xyz : m.baseColor.xyz;
        float3 bounce = base*l.ambientColor*0.35;
        if (m.isGround == 4) bounce += base*m.params.z;
        else if (m.params.z > 0.0) {
            float4 uv; hitNormal(h,m,vertices,indices,dir,uv);
            bounce += emittedLight(m,uv,textures,u);
        }
        return bounce*transmission;
    }

    // Source AO supplies stable upholstery contact shading. The matte diffuse
    // fill avoids stochastic glossy/indirect rays; direct light still casts
    // transparent, area-sampled shadows through the real scene geometry.
    static float3 matteIrradiance(float3 n, constant Uniforms &u) {
        Lighting l=lightingForPreset(u.renderOptions.x);
        return l.ambientColor*(0.75+0.25*max(n.y,0.0));
    }

    kernel void raytraceKernel(
        primitive_acceleration_structure accel [[buffer(0)]],
        device const Vertex *vertices [[buffer(1)]],
        device const uint *indices [[buffer(2)]],
        constant GeometryInfo *geometries [[buffer(3)]],
        constant Uniforms &uniforms [[buffer(4)]],
        texture2d<float, access::read_write> accumTex [[texture(0)]],
        texture2d<float, access::write> outputTex [[texture(1)]],
        array<texture2d<float>, 32> sourceTextures [[texture(2)]],
        uint2 gid [[thread_position_in_grid]])
    {
        uint width = uniforms.viewport.x;
        uint height = uniforms.viewport.y;
        uint sampleIndex = uniforms.viewport.z;
        uint isAccumulating = uniforms.viewport.w;

        if (gid.x >= width || gid.y >= height) return;

        uint seed = (gid.y * width + gid.x) ^ (sampleIndex * 719393u + 13u);
        float2 jitter = (isAccumulating == 1 && sampleIndex > 0)
            ? float2(rand(seed) - 0.5, rand(seed) - 0.5)
            : float2(0.0);

        float2 uv = (float2(gid) + float2(0.5) + jitter) / float2(width, height);
        float2 ndc = uv * 2.0 - 1.0;
        ndc.y = -ndc.y;

        float4 target = uniforms.invProj * float4(ndc, 1.0, 1.0);
        float3 rayDir = normalize((uniforms.invView * float4(target.xyz / target.w, 0.0)).xyz);
        float3 rayOrigin = uniforms.cameraPos.xyz;

        ray primaryRay;
        primaryRay.origin = rayOrigin;
        primaryRay.direction = rayDir;
        primaryRay.min_distance = 0.01;
        primaryRay.max_distance = 500.0;

        intersector<triangle_data> inter;
        typename intersector<triangle_data>::result_type hit = intersectVisible(primaryRay,accel,vertices,indices,geometries,uniforms);

        constexpr sampler materialSampler(coord::normalized, address::repeat, filter::linear);
        float3 color = sampleBackdrop(rayDir,uniforms.renderOptions.x);

        if (hit.type == intersection_type::triangle) {
            uint geomId = hit.geometry_id;
            uint primId = hit.primitive_id;
            GeometryInfo mat = geometries[geomId];
            applyFinish(mat,uniforms);

            // Global indices lookup
            uint i0 = indices[mat.indexOffset + primId * 3 + 0];
            uint i1 = indices[mat.indexOffset + primId * 3 + 1];
            uint i2 = indices[mat.indexOffset + primId * 3 + 2];

            float2 b = hit.triangle_barycentric_coord;
            float w = 1.0 - b.x - b.y;

            float3 n0 = vertices[i0].normal.xyz;
            float3 n1 = vertices[i1].normal.xyz;
            float3 n2 = vertices[i2].normal.xyz;
            float3 normal = normalize(w * n0 + b.x * n1 + b.y * n2);
            if (dot(normal, rayDir) > 0.0) normal = -normal;

            float2 texUV = w*vertices[i0].uv.xy + b.x*vertices[i1].uv.xy + b.y*vertices[i2].uv.xy;
            float2 texUV2 = w*vertices[i0].uv.zw + b.x*vertices[i1].uv.zw + b.y*vertices[i2].uv.zw;
            float3 texColor = float3(1.0);
            if (mat.textures.x >= 0) {
                float4 sample = sourceTextures[mat.textures.x].sample(materialSampler,(mat.textures.w & 16) != 0 ? texUV2 : texUV);
                texColor = pow(max(sample.rgb,0.0),float3(2.2));
                if ((mat.textures.w & 16) != 0) {
                    texColor = mix(float3(1),sample.rgb/10.0/max(uniforms.carPaintColor.xyz,float3(0.001)),sample.a);
                    mat.params.x = mix(mat.params.x,0.9,sample.a);
                    mat.baseColor.w = mix(mat.baseColor.w,0.0,sample.a);
                }
                mat.baseColor.xyz *= texColor;
            }
            if (mat.textures.y >= 0) {
                float3 mra = sourceTextures[mat.textures.y].sample(materialSampler,texUV).rgb;
                mat.baseColor.w *= mra.r;
                mat.params.x *= mra.g;
            }
            float materialAO = 1.0;
            if (mat.textures.z >= 0) {
                float4 ao = sourceTextures[mat.textures.z].sample(materialSampler,(mat.textures.w & 32) != 0 ? texUV2 : texUV);
                materialAO = ao[(mat.textures.w & 3)];
            }
            float3 hitPos = rayOrigin + rayDir * hit.distance;

            bool weatherScene=uniforms.renderOptions.x > 3.5;
            float wet=weatherScene ? uniforms.weather.y : 0.0;
            if (wet > 0.0 && mat.isGround == 0 && ((mat.isPaint == 1) || mat.params.w > 0.01)) {
                // Millimetric bead normals only on exposed outward/upward surfaces.
                float beads=pow(noise2(hitPos.xz*180.0+hitPos.y*23.0),18.0);
                float3 tangent=normalize(cross(normal,abs(normal.y)<0.95 ? float3(0,1,0) : float3(1,0,0)));
                normal=normalize(normal+tangent*beads*wet*0.035);
            }
            Lighting lighting = lightingForPreset(uniforms.renderOptions.x);
            float3 keyLightPos = lighting.keyPosition;
            keyLightPos += float3(rand(seed)-0.5,0.0,rand(seed)-0.5)*lighting.softSize;
            // Integrate the broad light lobe analytically; jitter only visibility.
            float3 lightDir = normalize(lighting.keyPosition - hitPos);
            float areaRoughness=sqrt(lighting.softSize/max(length(lighting.keyPosition-hitPos),1.0))*0.36;
            float NdotL = max(dot(normal, lightDir), 0.0);

            // Ray-traced soft shadow toward a jittered point on the area light.
            ray shadowRay;
            shadowRay.origin = hitPos + normal * 0.003;
            shadowRay.direction = normalize(keyLightPos - hitPos);
            shadowRay.min_distance = 0.01;
            shadowRay.max_distance = length(keyLightPos - hitPos);

            float shadow = mat.params.w>0.01 ? 1.0 : lightVisibility(shadowRay,accel,vertices,indices,geometries,uniforms);

            if (mat.isGround == 1) {
                // ============================================================
                // NICE STUDIO GROUND & REAL VEHICLE REFLECTIONS
                // ============================================================
                float distFromCenter = length(hitPos.xz);
                float vignette = weatherScene ? 1.0 : 1.0 - smoothstep(15.0, 45.0, distFromCenter);

                float3 groundBase = lighting.groundColor;
                float puddle=puddleAt(hitPos.xz)*wet;
                if (weatherScene) {
                    float grain=noise2(hitPos.xz*190.0);
                    groundBase*=mix(0.70,1.20,grain)*(1.0-0.48*wet);
                    // Weather scenes are roads: worn dashed lane paint and shoulder lines.
                    float lane=1.0-smoothstep(0.04,0.065,abs(abs(hitPos.z)-3.3));
                    float center=(1.0-smoothstep(0.035,0.055,abs(hitPos.z))) * step(0.38,fract(hitPos.x/4.5));
                    float worn=smoothstep(0.2,0.55,noise2(hitPos.xz*42.0));
                    groundBase=mix(groundBase,float3(0.45,0.40,0.24),max(lane,center)*worn*0.55);
                }
                // Cosine-weighted ambient occlusion supplies actual tire contact shadows.
                float phi = rand(seed) * 6.2831853;
                float r = sqrt(rand(seed));
                ray aoRay;
                aoRay.origin = hitPos + float3(0,0.003,0);
                aoRay.direction = float3(r*cos(phi),sqrt(1.0-r*r),r*sin(phi));
                aoRay.min_distance = 0.002;
                aoRay.max_distance = 1.2;
                auto aoHit = intersectVisible(aoRay,accel,vertices,indices,geometries,uniforms);
                float ao = aoHit.type == intersection_type::none ? 1.0 : mix(0.2,1.0,clamp(aoHit.distance/1.2,0.0,1.0));
                groundBase *= (lighting.ambientColor + lighting.keyColor*NdotL*shadow*0.4) * ao;

                if (abs(uniforms.effectParams.y) > 0.01 && uniforms.effectTextures.x >= 0) {
                    // road.tscn: +/-1.8m lane placement, .1 x 100m planes, UV scale (1,8).
                    float laneX = (abs(hitPos.z)-1.8)/0.1 + 0.5;
                    if (laneX >= 0.0 && laneX <= 1.0) {
                        float offset = clamp(uniforms.effectParams.y,-20.0,60.0)/60.0*1.8*uniforms.effectParams.x;
                        float2 uvLane = float2(laneX,(hitPos.x/100.0+0.5)*8.0+5.064+offset);
                        float4 lane = sourceTextures[uniforms.effectTextures.x].sample(materialSampler,uvLane);
                        groundBase = mix(groundBase,float3(0.2),lane.a);
                    }
                }
                float groundRoughness = mix(uniforms.params.w,0.018,puddle);
                float groundReflectivity = mix(uniforms.params.z,0.95,wet);
                float3 roadNormal=wetNormal(hitPos.xz,uniforms.weather.z,wet*uniforms.weather.x);

                // Secondary ray: Ground reflection pointing upwards into the car
                float3 reflDir = groundRoughness > 0.002
                    ? sampleGGXReflection(roadNormal,-rayDir,groundRoughness*0.8,seed)
                    : reflect(rayDir, roadNormal);

                ray reflRay;
                reflRay.origin = hitPos + float3(0.0, 0.004, 0.0);
                reflRay.direction = reflDir;
                reflRay.min_distance = 0.01;
                reflRay.max_distance = 50.0;

                typename intersector<triangle_data>::result_type carHit = intersectVisible(reflRay,accel,vertices,indices,geometries,uniforms);
                float3 reflectedColor = sampleEnvironment(reflDir,uniforms.renderOptions.x);

                if (carHit.type == intersection_type::triangle) {
                    GeometryInfo carMat = geometries[carHit.geometry_id];
                    applyFinish(carMat,uniforms);
                    uint ci0 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 0];
                    uint ci1 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 1];
                    uint ci2 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 2];
                    float2 cb = carHit.triangle_barycentric_coord;
                    float cw = 1.0 - cb.x - cb.y;
                    float3 cn = normalize(cw * vertices[ci0].normal.xyz + cb.x * vertices[ci1].normal.xyz + cb.y * vertices[ci2].normal.xyz);
                    float3 cHitPos = reflRay.origin + reflRay.direction * carHit.distance;

                    if (dot(cn,reflDir)>0.0) cn=-cn;
                    float4 cuv=cw*vertices[ci0].uv+cb.x*vertices[ci1].uv+cb.y*vertices[ci2].uv;
                    reflectedColor=surfaceRadiance(carMat,cn,-reflDir,cHitPos,cuv,uniforms,sourceTextures);
                }

                // Fresnel reflection factor
                float NdotV = max(dot(float3(0.0, 1.0, 0.0), -rayDir), 0.0);
                float fresnel = mix(0.08,0.02,wet) + mix(0.92,0.98,wet) * pow(1.0 - NdotV, 5.0);

                if (uniforms.weather.w > 0.5) {
                    float4 sources[2]={uniforms.headlampLeft,uniforms.headlampRight};
                    for (int lamp=0;lamp<2;++lamp) {
                        float3 src=sources[lamp].xyz;
                        float roadDist=hitPos.x-src.x;
                        if (sources[lamp].w<0.5 || roadDist<=0.0) continue;
                        float span=0.35+roadDist*0.25;
                        float lateral=abs(hitPos.z-src.z)/span;
                        if (lateral<1.0) {
                            float3 toGround=hitPos-src;
                            float visibility=airflowVisibility(src+float3(0.01,0,0),normalize(toGround),length(toGround),accel,geometries);
                            groundBase+=float3(0.95,0.98,1.0)*(1.0-lateral*lateral)*exp(-roadDist*0.16)/(1.0+roadDist*0.18)*visibility;
                        }
                    }
                }

                float3 groundFinal = mix(groundBase, reflectedColor, groundReflectivity * fresnel);
                color = mix(sampleBackdrop(rayDir,uniforms.renderOptions.x), groundFinal, vignette);
            } else if (mat.params.w > 0.01) {
                // ============================================================
                // RAY-TRACED AUTOMOTIVE GLASS & HEADLIGHT TRANSPARENCY
                // ============================================================
                float transmission = mat.params.w;
                float3 glassTint = mat.baseColor.xyz;

                transmission = opticalTransmission(mat,uniforms);

                float3 viewDir = -rayDir;
                float NdotV = max(dot(normal, viewDir), 0.0);

                // Fresnel reflection coefficient (air-to-glass IOR ~1.5, F0 ~0.04)
                float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);
                if ((mat.textures.w & 64) != 0) fresnel *= uniforms.renderOptions.w;

                // 1. Ray-traced secondary reflection ray for glossy environment reflection
                float3 reflDir = reflect(rayDir, normal);
                ray glassReflRay;
                glassReflRay.origin = hitPos + normal * 0.003;
                glassReflRay.direction = reflDir;
                glassReflRay.min_distance = 0.01;
                glassReflRay.max_distance = 50.0;

                typename intersector<triangle_data>::result_type reflHit = intersectVisible(glassReflRay,accel,vertices,indices,geometries,uniforms);
                float3 reflColor = sampleEnvironment(reflDir,uniforms.renderOptions.x);
                if (reflHit.type == intersection_type::triangle) {
                    GeometryInfo rMat = geometries[reflHit.geometry_id];
                    applyFinish(rMat,uniforms);
                    uint ri=rMat.indexOffset+reflHit.primitive_id*3;
                    Vertex ra=vertices[indices[ri]], rb=vertices[indices[ri+1]], rc=vertices[indices[ri+2]];
                    float2 bary=reflHit.triangle_barycentric_coord; float rw=1.0-bary.x-bary.y;
                    float3 rn=normalize(ra.normal.xyz*rw+rb.normal.xyz*bary.x+rc.normal.xyz*bary.y);
                    if (dot(rn,reflDir)>0.0) rn=-rn;
                    float4 ruv=ra.uv*rw+rb.uv*bary.x+rc.uv*bary.y;
                    float3 rp=glassReflRay.origin+reflDir*reflHit.distance;
                    reflColor=rMat.isGround==1 ? lighting.groundColor*(lighting.ambientColor+lighting.keyColor*0.25)
                        : surfaceRadiance(rMat,rn,-reflDir,rp,ruv,uniforms,sourceTextures);
                }

                // 2. Ray-traced transmission ray passing through the glass into interior / headlights
                ray transRay;
                transRay.origin = hitPos + rayDir * 0.0004;
                transRay.direction = rayDir;
                transRay.min_distance = 0.0002;
                transRay.max_distance = 35.0;

                typename intersector<triangle_data>::result_type transHit = intersectVisible(transRay,accel,vertices,indices,geometries,uniforms);
                float3 transColor = sampleEnvironment(rayDir,uniforms.renderOptions.x);
                uint paneGroup=mat.opticalGroup;
                float paneTransmission=transmission;
                // Traverse glass interfaces, retaining each pane's neutral absorption.
                // Shading a second glass hit as opaque made layered headlamps look black.
                for (int layer = 0; layer < 24; ++layer) {
                    if (transHit.type != intersection_type::triangle || geometries[transHit.geometry_id].params.w <= 0.01) break;
                    transmission *= paneAttenuation(geometries[transHit.geometry_id],transHit.distance,uniforms,paneGroup,paneTransmission);
                    transRay.origin += rayDir * (transHit.distance + 0.0004);
                    transHit = intersectVisible(transRay,accel,vertices,indices,geometries,uniforms);
                }

                if (transHit.type == intersection_type::triangle && geometries[transHit.geometry_id].params.w<=0.01) {
                    GeometryInfo tMat = geometries[transHit.geometry_id];
                    applyFinish(tMat,uniforms);
                    uint ti0 = indices[tMat.indexOffset + transHit.primitive_id * 3 + 0];
                    uint ti1 = indices[tMat.indexOffset + transHit.primitive_id * 3 + 1];
                    uint ti2 = indices[tMat.indexOffset + transHit.primitive_id * 3 + 2];

                    float2 tb = transHit.triangle_barycentric_coord;
                    float tw = 1.0 - tb.x - tb.y;
                    float3 tn0 = vertices[ti0].normal.xyz;
                    float3 tn1 = vertices[ti1].normal.xyz;
                    float3 tn2 = vertices[ti2].normal.xyz;
                    float3 tn = normalize(tw * tn0 + tb.x * tn1 + tb.y * tn2);
                    if (dot(tn, rayDir) > 0.0) tn = -tn;

                    float3 tHitPos = transRay.origin + rayDir * transHit.distance;
                    float3 tLightDir = normalize(keyLightPos - tHitPos);
                    float tNdotL = max(dot(tn, tLightDir), 0.0);

                    float3 tBase = (tMat.isPaint == 1) ? uniforms.carPaintColor.xyz : tMat.baseColor.xyz;
                    float2 tUV = tw*vertices[ti0].uv.xy + tb.x*vertices[ti1].uv.xy + tb.y*vertices[ti2].uv.xy;
                    if (tMat.textures.x >= 0 && (tMat.textures.w & 16) == 0) {
                        tBase *= pow(max(sourceTextures[tMat.textures.x].sample(materialSampler,tUV).rgb,0.0),float3(2.2));
                    }
                    float tMetallic = (tMat.isPaint == 1) ? uniforms.carPaintColor.w : tMat.baseColor.w;
                    float tEmissive = tMat.params.z;

                    // Interior shading: Chrome reflector, LED emitter, or cabin interior
                    if (tEmissive > 0.1) {
                        transColor = emittedLight(tMat,tw*vertices[ti0].uv+tb.x*vertices[ti1].uv+tb.y*vertices[ti2].uv,sourceTextures,uniforms);
                    } else if (tMetallic > 0.75) {
                        // Chrome reflector bowl inside headlight
                        float3 innerRefl = reflect(rayDir, tn);
                        transColor = sampleEnvironment(innerRefl,uniforms.renderOptions.x) * tBase * (0.8 + 0.5 * tNdotL);
                    } else {
                        // Shade the actual cabin surface with the same visibility
                        // and occluded diffuse bounce used when viewed directly.
                        ray cabinShadow;
                        cabinShadow.origin=tHitPos+tn*0.003;
                        bool matte=(tMat.textures.w & 1048576)!=0;
                        float3 cabinKey=keyLightPos;
                        cabinShadow.direction=normalize(cabinKey-tHitPos);
                        cabinShadow.min_distance=0.0002;
                        cabinShadow.max_distance=length(cabinKey-tHitPos);
                        float visibility=lightVisibility(cabinShadow,accel,vertices,indices,geometries,uniforms);
                        float4 cabinUV=tw*vertices[ti0].uv+tb.x*vertices[ti1].uv+tb.y*vertices[ti2].uv;
                        float ao=1.0;
                        if (tMat.textures.z>=0) {
                            float4 sourceAO=sourceTextures[tMat.textures.z].sample(materialSampler,(tMat.textures.w & 32)!=0 ? cabinUV.zw : cabinUV.xy);
                            ao=sourceAO[tMat.textures.w & 3];
                        }
                        float3 gi=matte ? matteIrradiance(tn,uniforms)
                            : traceIrradiance(tHitPos+tn*0.003,sampleCosine(tn,seed),accel,vertices,indices,geometries,uniforms,sourceTextures);
                        transColor=directBRDF(tn,viewDir,normalize(cabinKey-tHitPos),tBase,tMetallic,max(tMat.params.x,areaRoughness))*lighting.keyColor*visibility
                            +tBase*(1.0-tMetallic)*min(gi,float3(2.5))*ao;
                    }
                    transColor += rearPanelLight(tHitPos,tn,viewDir,tBase,tMetallic,tMat.params.x,uniforms);
                }

                if (transHit.type==intersection_type::triangle && geometries[transHit.geometry_id].params.w>0.01) transColor=float3(0);
                // Attenuate transmitted color by glass tint
                transColor *= glassTint;

                // Specular highlight from key studio light on outer glass surface
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = max(dot(normal, halfDir), 0.0);
                float glassSpec = pow(NdotH, 256.0) * ((mat.textures.w & 64) != 0 ? 0.06*uniforms.renderOptions.w : 0.18);

                // Tint absorbs transmitted light; it does not turn glass into
                // an opaque blue/gray surface or dim the front-surface reflection.
                color = transColor*transmission*(1.0-fresnel)+reflColor*fresnel
                    +float3(glassSpec)+emittedLight(mat,float4(texUV,texUV2),sourceTextures,uniforms);
            } else {
                // ============================================================
                // METALLIC CAR BODY & TESLA DETAILS
                // ============================================================
                float3 baseCol = ((mat.isPaint == 1) ? uniforms.carPaintColor.xyz * texColor : mat.baseColor.xyz);
                float metallic = (mat.isPaint == 1) ? uniforms.carPaintColor.w : mat.baseColor.w;
                float roughness = (mat.isPaint == 1) ? uniforms.params.x : mat.params.x;
                float clearcoat = (mat.isPaint == 1) ? uniforms.params.y : mat.params.y;
                if (mat.isPaint == 1) {
                    // Subtle flake variation beneath an independent dielectric coat.
                    roughness=clamp(roughness+(noise2(hitPos.xz*320.0+hitPos.y*91.0)-0.5)*0.025,0.045,1.0);
                    clearcoat=mix(clearcoat,1.0,wet);
                    roughness=mix(roughness,roughness*0.65,wet);
                }
                float emissive = mat.params.z;
                if (mat.isGround == 3) {
                    // PowerflowSingle.shader: flowing state, original cable pulse defaults.
                    float flow = pow(max(1.0-fract(uniforms.effectParams.x/1.5-texUV.x/1.5),0.0),2.0);
                    baseCol *= 0.2*(1.0-flow);
                    emissive = flow;
                    baseCol += float3(0.0,0.35,1.0)*flow;
                }


                float3 viewDir = -rayDir;
                bool isPaint = mat.isPaint == 1;
                bool isStainlessSteel = ((mat.textures.w & 2048) != 0);
                bool isRubber = (mat.textures.w & 128) != 0;
                bool isLeather = (mat.textures.w & 1048576) != 0;
                float3 tangent = normalize(cross(abs(normal.y) < 0.95 ? float3(0,1,0) : float3(1,0,0), normal));
                float3 bitangent = cross(normal, tangent);

                // Layer normals: the clearcoat carries a faint orange-peel wave,
                // the base carries randomly oriented metallic flakes.
                float3 coatN = normal, flakeN = normal;
                float baseRough = roughness, coatRough = 0.05;
                float flakeSparkle = 0.0;
                if (isPaint) {
                    float2 peel = float2(noise2(hitPos.xz*38.0+hitPos.y*21.0), noise2(hitPos.zy*38.0+hitPos.x*17.0)) - 0.5;
                    coatN = normalize(normal + (tangent*peel.x + bitangent*peel.y)*0.010*(1.0-wet));
                    float3 cell = floor(fmod(abs(hitPos)*1400.0, 8192.0));
                    float3 tilt = float3(hash31(cell), hash31(cell+17.13), hash31(cell+41.71)) - 0.5;
                    flakeN = normalize(normal + (tangent*tilt.x + bitangent*tilt.y)*0.22*metallic);
                    flakeSparkle = step(0.93, hash31(cell+7.7))*metallic;
                    baseRough = mix(roughness, clamp(roughness*2.2+0.14, 0.2, 0.62), clearcoat);
                    coatRough = clamp(roughness*0.22, 0.012, 0.06);
                } else if (isLeather) {
                    // Fine, restrained grain keeps broad leather highlights soft.
                    float2 grain = float2(noise2(hitPos.xy*950.0+hitPos.z*51.0),
                                          noise2(hitPos.zy*950.0+hitPos.x*47.0))-0.5;
                    flakeN = normalize(normal+(tangent*grain.x+bitangent*grain.y)*0.018);
                    baseRough = max(0.82,roughness);
                } else if (isStainlessSteel) {
                    float grain = (noise2(hitPos.xz*450.0 + hitPos.y*120.0) - 0.5)*0.045;
                    baseRough = clamp(roughness + grain, 0.05, 1.0);
                }

                float NdotV = max(dot(normal, viewDir), 0.001);
                float3 F0 = mix(float3(0.04), baseCol, metallic);
                if (isStainlessSteel) { F0 = max(F0, float3(0.78, 0.80, 0.82)); }
                float3 envF = fresnelSchlick(NdotV, F0);

                // Base layer: GGX importance-sampled reflection through the scene.
                float3 baseDir = sampleGGXReflection(normal, viewDir, max(baseRough, 0.02), seed);
                float3 baseRefl = isLeather ? sampleEnvironment(reflect(rayDir,normal),uniforms.renderOptions.x)
                    : traceRadiance(hitPos + normal*0.003, baseDir, 45.0, accel, vertices, indices, geometries, uniforms, sourceTextures);
                float3 specBase = baseRefl*envF*mix(1.0, 0.72, baseRough);

                // Diffuse: cosine-sampled sky/bounce ray = real ambient occlusion + GI.
                float3 giDir = sampleCosine(normal, seed);
                // Clamp keeps small hot emitters from producing slow-converging speckle.
                float3 irradiance = isLeather ? matteIrradiance(normal,uniforms)
                    : min(traceIrradiance(hitPos + normal*0.003, giDir, accel, vertices, indices, geometries, uniforms, sourceTextures), float3(2.5));
                float3 diffuseGI = baseCol*(1.0-metallic)*irradiance*materialAO;
                // Metallic pigment still scatters some colored light under the coat.
                if (isPaint) diffuseGI += baseCol*metallic*0.18*irradiance*materialAO;

                float3 direct = directBRDF(flakeN, viewDir, lightDir, baseCol, metallic, max(baseRough, areaRoughness))*lighting.keyColor*shadow;
                if (isPaint) {
                    // Glints: individual flakes catching the key light.
                    float3 h = normalize(lightDir + viewDir);
                    direct += baseCol*lighting.keyColor*shadow*flakeSparkle*pow(max(dot(flakeN,h),0.0),220.0)*0.8*max(dot(normal,lightDir),0.0);
                }
                if (isRubber) { direct *= 0.8; specBase *= 0.05; }
                if (isLeather) { specBase *= 0.18; }
                direct += rearPanelLight(hitPos, normal, viewDir, baseCol, metallic, roughness, uniforms);

                float3 layered = direct + diffuseGI + specBase;
                if (clearcoat > 0.02) {
                    float coatNV = max(dot(coatN, viewDir), 0.001);
                    float coatF = 0.04 + 0.96*pow(1.0-coatNV, 5.0);
                    float3 coatDir = sampleGGXReflection(coatN, viewDir, coatRough, seed);
                    float3 coatRefl = traceRadiance(hitPos + normal*0.003, coatDir, 60.0, accel, vertices, indices, geometries, uniforms, sourceTextures);
                    float3 coatDirect = directBRDF(coatN, viewDir, lightDir, float3(0), 0.0, max(coatRough, areaRoughness))*lighting.keyColor*shadow;
                    layered = layered*(1.0 - clearcoat*coatF) + clearcoat*(coatDirect + coatRefl*coatF);
                }
                color = layered
                     +(mat.isGround==3 ? float3(0.0,0.35,1.0)*emissive : (mat.isGround==4 ? baseCol*emissive : emittedLight(mat,float4(texUV,texUV2),sourceTextures,uniforms)));
                if (uniforms.renderOptions.x>3.5) {
                    // Colored off-camera practicals provide matching neon highlights.
                    float3 cyanDir=normalize(float3(-1,0.24,0.6));
                    float3 pinkDir=normalize(float3(0.7,0.18,-1));
                    if (uniforms.renderOptions.x<4.5)
                        color+=directBRDF(normal,viewDir,cyanDir,baseCol,metallic,roughness)*float3(0.03,1.4,2.3)
                              +directBRDF(normal,viewDir,pinkDir,baseCol,metallic,roughness)*float3(2.2,0.04,0.35);
                }
            }
        }

        // ============================================================
        // PROGRESSIVE ACCUMULATION & TONE MAPPING
        // ============================================================
        if (uniforms.effectParams.z > 0.0) {
            // airflow_shader.tres + Airflow.gdc: half-speed time, UV velocity -0.8,
            // 1.5/.35 UV scale and the original edge-fade expression.
            for (int plane = 0; plane < min(uniforms.effectTextures.y,2); ++plane) {
                float4x4 inv = plane == 0 ? uniforms.climateLeft : uniforms.climateRight;
                float3 o = (inv*float4(rayOrigin,1)).xyz;
                float3 d = (inv*float4(rayDir,0)).xyz;
                if (abs(d.z) < 0.0001) continue;
                float distance = -o.z/d.z;
                float2 uvAir = (o+d*distance).xy + 0.5;
                if (distance > 0.0 && all(uvAir >= 0.0) && all(uvAir <= 1.0)) {
                    uvAir.y = 1.0-uvAir.y;
                    float2 noiseUV = uvAir*float2(1.5,0.35)+float2(0,-uniforms.effectParams.x*0.4);
                    float noise = uniforms.effectTextures.z >= 0 ? sourceTextures[uniforms.effectTextures.z].sample(materialSampler,noiseUV).r : 0.5;
                    float alpha = noise*(1.0-uvAir.y)*clamp(uvAir.y/0.05,0.0,1.0)*(1.0-abs(uvAir.x-0.5)*2.0)*3.0;
                    float3 airColor = uniforms.effectParams.z > 1.5 ? float3(0.918,0.251,0.251) : float3(1);
                    float visibility=airflowVisibility(rayOrigin,rayDir,distance,accel,geometries);
                    color += airColor*alpha*0.3*visibility;
                }
            }
        }

        // ============================================================
        // VOLUMETRIC AUTOMOTIVE HEADLIGHT BEAMS
        // ============================================================
        // VOLUMETRIC AUTOMOTIVE HEADLIGHT BEAMS & OPTICAL GLARE
        // Dual LED projector lamps with atmospheric scattering & lens flare matching reference
        // ============================================================
        if (uniforms.weather.w > 0.5) {
            float maxRayDist = (hit.type == intersection_type::triangle) ? hit.distance : 40.0;
            float4 beamSources[2]={uniforms.headlampLeft,uniforms.headlampRight};
            float3 beamAxis = normalize(float3(1.0, -0.05, 0.0)); // Downward road projection
            float3 beamColor = float3(0.94, 0.97, 1.0); // 6200K pure automotive LED


            for (int b = 0; b < 2; ++b) {
                if (beamSources[b].w<0.5) continue;
                float3 src = beamSources[b].xyz;
                float3 delta = rayOrigin - src;

                // Direct lens flare / core bloom when looking towards headlight emitters
                float3 toEmitter = src - rayOrigin;
                float distToEmitter = length(toEmitter);
                if (distToEmitter > 0.1 && distToEmitter <= maxRayDist + 0.15) {
                    float3 dirToEmitter = toEmitter / distToEmitter;
                    float lookAlign = dot(rayDir, dirToEmitter);
                    if (lookAlign > 0.999) {
                        float glareAngle = (lookAlign - 0.999) / 0.001;
                        float emitterFacing = dot(-dirToEmitter, beamAxis); // Only visible from front
                        if (emitterFacing > 0.1) {
                            float glare = pow(glareAngle, 6.0) * emitterFacing * 1.8;
                            float starburst = pow(glareAngle, 18.0) * 2.5;
                            color += beamColor * (glare + starburst) / (1.0 + distToEmitter * 0.18)
                                *airflowVisibility(rayOrigin,dirToEmitter,distToEmitter,accel,geometries);
                        }
                    }
                }

                // Ray-marched volumetric forward beam cone
                float d12 = dot(rayDir, beamAxis);
                float det = 1.0 - d12 * d12;
                if (det > 0.001) {
                    float tRay = (dot(beamAxis, delta) * d12 - dot(rayDir, delta)) / det;
                    float tBeam = dot(rayDir, beamAxis) * tRay + dot(beamAxis, delta);
                    tRay = clamp(tRay, 0.2, maxRayDist);
                    if (tBeam > 0.05 && tBeam < 20.0) {
                        float3 pRay = rayOrigin + rayDir * tRay;
                        float3 pBeam = src + beamAxis * tBeam;
                        float distToCore = length(pRay - pBeam);

                        // Realistic wide headlight beam cone expansion
                        float coneRadius = 0.08 + tBeam * 0.22;
                        if (distToCore < coneRadius) {
                            float profile = 1.0 - smoothstep(0.0, coneRadius, distToCore);
                            profile = profile * profile; // Gaussian radial falloff
                            float distanceAttenuation = exp(-tBeam * 0.22) / (1.0 + tBeam * 0.12);
                            float beamVisibility=airflowVisibility(src+beamAxis*0.01,normalize(pRay-src),length(pRay-src),accel,geometries);
                            float beamIntensity = profile * distanceAttenuation * 0.25*beamVisibility;

                            // Forward Mie scattering phase function
                            float cosTheta = dot(rayDir, beamAxis);
                            float mie = 0.6 + 0.8 * pow(max(cosTheta, 0.0), 3.5);
                            color += beamColor * beamIntensity * mie;
                        }
                    }
                }
            }
        }


        if (uniforms.renderOptions.x > 3.5) {
            float distance=hit.type==intersection_type::triangle ? hit.distance : 100.0;
            float density=uniforms.renderOptions.x>4.5 ? 0.017 : 0.027;
            float fog=1.0-exp(-distance*density);
            float3 fogColor=uniforms.renderOptions.x>4.5 ? float3(0.17,0.22,0.29) : float3(0.025,0.045,0.08);
            color=mix(color,fogColor,fog*0.65);
            // World anchored rain slabs. Bound intersections by the primary hit,
            // so rain behind an opaque car cannot be drawn over its silhouette.
            bool useZ=abs(rayDir.z)>abs(rayDir.x);
            float axisOrigin=useZ ? rayOrigin.z : rayOrigin.x;
            float axisDir=useZ ? rayDir.z : rayDir.x;
            if (abs(axisDir)>0.001 && uniforms.weather.x>0.0) {
                float axisStep=axisDir>0.0 ? 1.0 : -1.0;
                for (int layer=0;layer<12;++layer) {
                    float plane=(floor(axisOrigin/2.5)+(axisStep>0 ? 1.0 : 0.0)+float(layer)*axisStep)*2.5;
                    float t=(plane-axisOrigin)/axisDir;
                    if (t<0.15 || t>min(distance,35.0)) continue;
                    float3 p=rayOrigin+rayDir*t;
                    float2 rainUV=float2((useZ ? p.x : p.z)+p.y*0.13,p.y+uniforms.weather.z*8.0)*float2(8,1.8);
                    float2 cell=floor(rainUV), f=fract(rainUV);
                    float random=hash21(cell+plane*17.0);
                    float width=max(0.009,t/float(height)*1.4);
                    float streak=(1.0-smoothstep(width,width*2.0,abs(f.x-0.5)))
                        *smoothstep(0.05,0.12,f.y)*(1.0-smoothstep(0.18,0.40,f.y));
                    streak*=step(1.0-uniforms.weather.x*0.12,random)*exp(-t*0.045);
                    color+=float3(0.40,0.57,0.72)*streak*0.14;
                }
            }
        }

        // Firefly suppression: clamp per-sample luminance and reject NaNs so
        // thin strip lights seen through GGX lobes converge cleanly.
        if (any(isnan(color)) || any(isinf(color))) color = float3(0.0);
        float sampleLum = dot(color, float3(0.2126,0.7152,0.0722));
        if (sampleLum > 16.0) color *= 16.0/sampleLum;

        float4 prev = (isAccumulating == 1 && sampleIndex > 0) ? accumTex.read(gid) : float4(0.0);
        float4 blended = mix(float4(color, 1.0), prev, float(sampleIndex) / float(sampleIndex + 1));
        accumTex.write(blended, gid);

        // ACES Film Tone Mapping (fallback; postProcessKernel overwrites this)
        float3 col = max(blended.rgb*uniforms.renderOptions.y,float3(0.0));
        float3 a = col * (col + 0.0245786) - 0.000090537;
        float3 b = col * (0.983729 * col + 0.4329510) + 0.238081;
        float3 mapped = clamp(a / b, 0.0, 1.0);

        // Gamma 2.2 correction for sRGB display
        mapped = pow(mapped, float3(1.0 / 2.2));

        outputTex.write(float4(mapped, 1.0), gid);
    }

    // ============================================================
    // CINEMATIC POST: bloom, filmic tone curve, lens effects
    // ============================================================
    kernel void bloomBrightPass(
        texture2d<float, access::read> accumTex [[texture(0)]],
        texture2d<float, access::write> bloomTex [[texture(1)]],
        constant Uniforms &uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= uniforms.viewport.x || gid.y >= uniforms.viewport.y) return;
        float3 c = max(accumTex.read(gid).rgb*uniforms.renderOptions.y, float3(0.0));
        float lum = dot(c, float3(0.2126,0.7152,0.0722));
        // Soft-knee threshold keeps bloom to genuinely hot highlights.
        float knee = 0.6, threshold = 1.1;
        float soft = clamp(lum - threshold + knee, 0.0, 2.0*knee);
        soft = soft*soft/(4.0*knee + 1e-4);
        float contrib = max(soft, lum - threshold)/max(lum, 1e-4);
        bloomTex.write(float4(min(c*contrib, float3(64.0)), 1.0), gid);
    }

    static float3 tentSample(texture2d<float> t, sampler s, float2 uv, float lod, float2 texel) {
        float2 o = texel*exp2(lod);
        float3 c = t.sample(s, uv, level(lod)).rgb*4.0;
        c += (t.sample(s, uv+float2(o.x,0), level(lod)).rgb + t.sample(s, uv-float2(o.x,0), level(lod)).rgb
            + t.sample(s, uv+float2(0,o.y), level(lod)).rgb + t.sample(s, uv-float2(0,o.y), level(lod)).rgb)*2.0;
        c += t.sample(s, uv+o, level(lod)).rgb + t.sample(s, uv-o, level(lod)).rgb
           + t.sample(s, uv+float2(o.x,-o.y), level(lod)).rgb + t.sample(s, uv+float2(-o.x,o.y), level(lod)).rgb;
        return c/16.0;
    }

    static float3 acesFitted(float3 c) {
        const float3x3 inputMat = float3x3(float3(0.59719,0.07600,0.02840),
                                           float3(0.35458,0.90834,0.13383),
                                           float3(0.04823,0.01566,0.83777));
        const float3x3 outputMat = float3x3(float3( 1.60475,-0.10208,-0.00327),
                                            float3(-0.53108, 1.10813,-0.07276),
                                            float3(-0.07367,-0.00605, 1.07602));
        c = inputMat*c;
        float3 a = c*(c + 0.0245786) - 0.000090537;
        float3 b = c*(0.983729*c + 0.4329510) + 0.238081;
        return clamp(outputMat*(a/b), 0.0, 1.0);
    }

    static float3 linearToSRGB(float3 c) {
        return select(1.055*pow(c, float3(1.0/2.4)) - 0.055, c*12.92, c <= 0.0031308);
    }

    kernel void postProcessKernel(
        texture2d<float, access::read> accumTex [[texture(0)]],
        texture2d<float> bloomTex [[texture(1)]],
        texture2d<float, access::write> outputTex [[texture(2)]],
        constant Uniforms &uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        uint w = uniforms.viewport.x, h = uniforms.viewport.y;
        if (gid.x >= w || gid.y >= h) return;
        constexpr sampler linearSmp(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
        float2 size = float2(w, h);
        float2 uv = (float2(gid) + 0.5)/size;
        float2 centered = uv - 0.5;
        float exposure = uniforms.renderOptions.y;

        // Subtle lateral chromatic aberration toward the frame edges.
        float2 caOffset = centered*dot(centered, centered)*0.35;
        int2 maxP = int2(w-1, h-1);
        int2 pr = clamp(int2(float2(gid) + caOffset*size*0.012), int2(0), maxP);
        int2 pb = clamp(int2(float2(gid) - caOffset*size*0.012), int2(0), maxP);
        float3 hdr = float3(accumTex.read(uint2(pr)).r, accumTex.read(gid).g, accumTex.read(uint2(pb)).b)*exposure;

        // Multi-scale bloom from the bright-pass mip chain.
        float2 texel = 1.0/size;
        float3 bloom = tentSample(bloomTex, linearSmp, uv, 1.0, texel)*0.30
                     + tentSample(bloomTex, linearSmp, uv, 2.0, texel)*0.26
                     + tentSample(bloomTex, linearSmp, uv, 3.0, texel)*0.20
                     + tentSample(bloomTex, linearSmp, uv, 4.0, texel)*0.13
                     + tentSample(bloomTex, linearSmp, uv, 5.0, texel)*0.07
                     + tentSample(bloomTex, linearSmp, uv, 6.0, texel)*0.04;
        float bloomStrength = uniforms.renderOptions.x > 3.5 ? 0.22 : 0.12;
        hdr += bloom*bloomStrength;

        // Optical vignette (cos^4-like falloff).
        float2 vc = centered*float2(size.x/size.y, 1.0);
        float vignette = 1.0 - 0.38*smoothstep(0.25, 1.05, length(vc));
        hdr *= vignette;

        float3 mapped = acesFitted(max(hdr, float3(0.0)));
        // Gentle saturation lift typical of a racing-game grade.
        float l = dot(mapped, float3(0.2126,0.7152,0.0722));
        mapped = clamp(mix(float3(l), mapped, 1.08), 0.0, 1.0);
        float3 display = linearToSRGB(mapped);
        // Static film grain doubles as dither against banding in dark gradients.
        float grain = fract(sin(dot(float2(gid), float2(12.9898,78.233)))*43758.5453) - 0.5;
        display += grain*(1.5/255.0);
        outputTex.write(float4(clamp(display, 0.0, 1.0), 1.0), gid);
    }
    """
}
