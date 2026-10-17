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

    // 64-byte 16-byte aligned geometry metadata
    struct GeometryInfo {
        int4 textures;
        uint vertexOffset;
        uint indexOffset;
        uint isGround;
        uint isPaint;
        float4 baseColor;
        float4 params;
    };

    // 368-byte 16-byte aligned Uniforms structure matching Swift UniformsGPU layout exactly
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
    };

    // Studio environment map gradient & overhead lighting softbox
    static float3 sampleStudioEnv(float3 dir) {
        float y = dir.y;
        float3 topColor = float3(0.04, 0.05, 0.08);
        float3 horizonColor = float3(0.12, 0.14, 0.18);
        float3 bottomColor = float3(0.02, 0.02, 0.03);
        float3 bg = (y >= 0.0) ? mix(horizonColor, topColor, pow(y, 0.6))
                               : mix(horizonColor, bottomColor, min(1.0, pow(-y, 0.5) * 1.5));

        // Studio overhead softbox
        if (dir.y > 0.55 && abs(dir.x) < 0.7 && abs(dir.z) < 0.9) {
            bg += float3(2.4, 2.4, 2.5);
        }
        // Studio rim backlight
        float rim = max(dot(dir, normalize(float3(-0.8, 0.35, 0.4))), 0.0);
        bg += float3(0.3, 0.5, 0.9) * pow(rim, 7.0);

        // Studio fill warm light
        float warm = max(dot(dir, normalize(float3(0.7, 0.5, -0.5))), 0.0);
        bg += float3(0.6, 0.45, 0.3) * pow(warm, 5.0);
        return bg;
    }

    // High quality pseudo-random number generator for anti-aliasing & glossy reflections
    static float rand(thread uint &seed) {
        seed = seed * 1664525u + 1013904223u;
        return float(seed & 0x00FFFFFFu) / float(0x01000000u);
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
        typename intersector<triangle_data>::result_type hit = inter.intersect(primaryRay, accel);

        constexpr sampler materialSampler(coord::normalized, address::repeat, filter::linear);
        float3 color = sampleStudioEnv(rayDir);

        if (hit.type == intersection_type::triangle) {
            uint geomId = hit.geometry_id;
            uint primId = hit.primitive_id;
            GeometryInfo mat = geometries[geomId];

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

            // Key studio directional light
            float3 keyLightPos = float3(5.5, 9.5, 6.5);
            // Sample the rectangular softbox; accumulation integrates its penumbra.
            keyLightPos += float3((rand(seed)-0.5)*3.0, 0.0, (rand(seed)-0.5)*2.0);
            float3 lightDir = normalize(keyLightPos - hitPos);
            float NdotL = max(dot(normal, lightDir), 0.0);

            // Ray-traced shadow ray
            ray shadowRay;
            shadowRay.origin = hitPos + normal * 0.003;
            shadowRay.direction = lightDir;
            shadowRay.min_distance = 0.01;
            shadowRay.max_distance = length(keyLightPos - hitPos);

            typename intersector<triangle_data>::result_type shadowHit = inter.intersect(shadowRay, accel);
            float shadow = (shadowHit.type == intersection_type::none) ? 1.0 : 0.22;

            if (mat.isGround == 1) {
                // ============================================================
                // NICE STUDIO GROUND & REAL VEHICLE REFLECTIONS
                // ============================================================
                float distFromCenter = length(hitPos.xz);
                float vignette = 1.0 - smoothstep(15.0, 45.0, distFromCenter);

                float3 groundBase = float3(0.10, 0.115, 0.14);
                // Cosine-weighted ambient occlusion supplies actual tire contact shadows.
                float phi = rand(seed) * 6.2831853;
                float r = sqrt(rand(seed));
                ray aoRay;
                aoRay.origin = hitPos + float3(0,0.003,0);
                aoRay.direction = float3(r*cos(phi),sqrt(1.0-r*r),r*sin(phi));
                aoRay.min_distance = 0.002;
                aoRay.max_distance = 1.2;
                auto aoHit = inter.intersect(aoRay, accel);
                float ao = aoHit.type == intersection_type::none ? 1.0 : mix(0.2,1.0,clamp(aoHit.distance/1.2,0.0,1.0));
                groundBase *= (0.18 + 0.82 * shadow) * ao;

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
                float groundRoughness = uniforms.params.w;
                float groundReflectivity = uniforms.params.z;

                // Secondary ray: Ground reflection pointing upwards into the car
                float3 reflDir = reflect(rayDir, float3(0.0, 1.0, 0.0));
                if (groundRoughness > 0.002) {
                    float3 randOff = float3(rand(seed) - 0.5, rand(seed) * 0.15, rand(seed) - 0.5) * groundRoughness;
                    reflDir = normalize(reflDir + randOff);
                }

                ray reflRay;
                reflRay.origin = hitPos + float3(0.0, 0.004, 0.0);
                reflRay.direction = reflDir;
                reflRay.min_distance = 0.01;
                reflRay.max_distance = 50.0;

                typename intersector<triangle_data>::result_type carHit = inter.intersect(reflRay, accel);
                float3 reflectedColor = sampleStudioEnv(reflDir) * 0.35;

                if (carHit.type == intersection_type::triangle) {
                    GeometryInfo carMat = geometries[carHit.geometry_id];
                    uint ci0 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 0];
                    uint ci1 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 1];
                    uint ci2 = indices[carMat.indexOffset + carHit.primitive_id * 3 + 2];
                    float2 cb = carHit.triangle_barycentric_coord;
                    float cw = 1.0 - cb.x - cb.y;
                    float3 cn = normalize(cw * vertices[ci0].normal.xyz + cb.x * vertices[ci1].normal.xyz + cb.y * vertices[ci2].normal.xyz);
                    float3 cHitPos = reflRay.origin + reflRay.direction * carHit.distance;

                    float3 carBase;
                    if (carMat.isPaint == 1) {
                        // Ground reflection: only the flat downward battery pan facing ground is dark underbody
                        if (cn.y < -0.85 && cHitPos.y < 0.20 && abs(cHitPos.z) < 0.65) {
                            carBase = float3(0.025, 0.027, 0.030);
                        } else {
                            carBase = uniforms.carPaintColor.xyz;
                        }
                    } else {
                        carBase = carMat.baseColor.xyz;
                    }

                    reflectedColor = carBase * 0.90;
                }

                // Fresnel reflection factor
                float NdotV = max(dot(float3(0.0, 1.0, 0.0), -rayDir), 0.0);
                float fresnel = 0.08 + 0.92 * pow(1.0 - NdotV, 3.5);

                float3 groundFinal = mix(groundBase, reflectedColor, groundReflectivity * fresnel);
                color = mix(sampleStudioEnv(rayDir), groundFinal, vignette);
            } else if (mat.params.w > 0.01) {
                // ============================================================
                // RAY-TRACED AUTOMOTIVE GLASS & HEADLIGHT TRANSPARENCY
                // ============================================================
                float transmission = mat.params.w;
                float3 glassTint = mat.baseColor.xyz;

                // If tinted glass roof or rear privacy windows (Cat 3):
                if ((mat.textures.w & 512) != 0) {
                    if (uniforms.tintParams.x > 0.5) {
                        // Deep factory privacy tint option enabled:
                        transmission = uniforms.tintParams.y;
                        float darkness = uniforms.tintParams.z;
                        glassTint = mix(float3(0.94, 0.97, 1.0), float3(0.65, 0.72, 0.80), darkness);
                    }
                }

                float3 viewDir = -rayDir;
                float NdotV = max(dot(normal, viewDir), 0.0);

                // Fresnel reflection coefficient (air-to-glass IOR ~1.5, F0 ~0.04)
                float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);

                // 1. Ray-traced secondary reflection ray for glossy environment reflection
                float3 reflDir = reflect(rayDir, normal);
                ray glassReflRay;
                glassReflRay.origin = hitPos + normal * 0.003;
                glassReflRay.direction = reflDir;
                glassReflRay.min_distance = 0.01;
                glassReflRay.max_distance = 50.0;

                typename intersector<triangle_data>::result_type reflHit = inter.intersect(glassReflRay, accel);
                float3 reflColor = sampleStudioEnv(reflDir);
                if (reflHit.type == intersection_type::triangle) {
                    GeometryInfo rMat = geometries[reflHit.geometry_id];
                    float3 rBase = (rMat.isPaint == 1) ? uniforms.carPaintColor.xyz : rMat.baseColor.xyz;
                    reflColor = (rMat.isGround == 1) ? float3(0.06, 0.07, 0.09) : rBase;
                }

                // 2. Ray-traced transmission ray passing through the glass into interior / headlights
                ray transRay;
                transRay.origin = hitPos + rayDir * 0.0004;
                transRay.direction = rayDir;
                transRay.min_distance = 0.0002;
                transRay.max_distance = 35.0;

                typename intersector<triangle_data>::result_type transHit = inter.intersect(transRay, accel);
                float3 transColor = sampleStudioEnv(rayDir);
                // Traverse both lens interfaces and any nested clear covers before shading.
                // Shading a second glass hit as opaque made layered headlamps look black.
                for (int layer = 0; layer < 8; ++layer) {
                    if (transHit.type != intersection_type::triangle || geometries[transHit.geometry_id].params.w <= 0.01) break;
                    transRay.origin += rayDir * (transHit.distance + 0.0004);
                    transHit = inter.intersect(transRay, accel);
                }

                if (transHit.type == intersection_type::triangle) {
                    GeometryInfo tMat = geometries[transHit.geometry_id];
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
                        transColor = tBase * (1.0 + tEmissive * 2.0);
                    } else if (tMetallic > 0.75) {
                        // Chrome reflector bowl inside headlight
                        float3 innerRefl = reflect(rayDir, tn);
                        transColor = sampleStudioEnv(innerRefl) * tBase * (0.8 + 0.5 * tNdotL);
                    } else {
                        // Cabin seats, dashboard, steering wheel
                        float3 interiorAmbient = tBase * 0.40;
                        float3 interiorDiffuse = tBase * tNdotL * 0.75;
                        transColor = interiorAmbient + interiorDiffuse;
                    }
                }

                // Attenuate transmitted color by glass tint
                transColor *= glassTint;

                // Specular highlight from key studio light on outer glass surface
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = max(dot(normal, halfDir), 0.0);
                float glassSpec = pow(NdotH, 256.0) * ((mat.textures.w & 64) != 0 ? 0.12 : 0.35);

                // Physical mix: transmitted light vs reflected light according to Fresnel
                float3 glassBlend = mix(transColor, reflColor, fresnel);

                // If transmission < 1.0, blend between opaque surface and transmitted glass
                float3 opaqueLook = glassTint * 0.1 + reflColor * fresnel;
                color = mix(opaqueLook, glassBlend, transmission) + float3(glassSpec) + float3(mat.params.z);
            } else {
                // ============================================================
                // METALLIC CAR BODY & TESLA DETAILS
                // ============================================================
                float3 baseCol = ((mat.isPaint == 1) ? uniforms.carPaintColor.xyz * texColor : mat.baseColor.xyz) * materialAO;
                float metallic = (mat.isPaint == 1) ? uniforms.carPaintColor.w : mat.baseColor.w;
                float roughness = (mat.isPaint == 1) ? uniforms.params.x : mat.params.x;
                float clearcoat = (mat.isPaint == 1) ? uniforms.params.y : mat.params.y;
                float emissive = mat.params.z;
                if (mat.isGround == 3) {
                    // PowerflowSingle.shader: flowing state, original cable pulse defaults.
                    float flow = pow(max(1.0-fract(uniforms.effectParams.x/1.5-texUV.x/1.5),0.0),2.0);
                    baseCol *= 0.2*(1.0-flow);
                    emissive = flow;
                    baseCol += float3(0.0,0.35,1.0)*flow;
                }


                float3 viewDir = -rayDir;
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = max(dot(normal, halfDir), 0.0);
                float specPower = mix(128.0, 8.0, roughness);
                float spec = pow(NdotH, specPower) * (1.0 - roughness * 0.5);

                // Secondary ray: Metallic reflection
                float3 reflDir = reflect(rayDir, normal);
                if (roughness > 0.02) {
                    float3 randOff = float3(rand(seed) - 0.5, rand(seed) - 0.5, rand(seed) - 0.5) * roughness * 0.35;
                    reflDir = normalize(reflDir + randOff);
                }

                ray carReflRay;
                carReflRay.origin = hitPos + normal * 0.003;
                carReflRay.direction = reflDir;
                carReflRay.min_distance = 0.01;
                carReflRay.max_distance = 45.0;

                typename intersector<triangle_data>::result_type secHit = inter.intersect(carReflRay, accel);
                float3 envRefl = sampleStudioEnv(reflDir);
                if (secHit.type == intersection_type::triangle) {
                    GeometryInfo secMat = geometries[secHit.geometry_id];
                    float3 hitColor = (secMat.isPaint == 1) ? uniforms.carPaintColor.xyz : secMat.baseColor.xyz;
                    envRefl = (secMat.isGround == 1) ? float3(0.08) : hitColor;
                }

                float NdotV = max(dot(normal, viewDir), 0.0);
                float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);

                // Automotive physical PBR blend
                float3 diffuse = baseCol * NdotL * shadow;
                float3 specular = mix(float3(spec), baseCol * spec, metallic) * shadow;
                float3 ambient = baseCol * 0.08;
                float3 metalRefl = mix(envRefl * fresnel, envRefl * baseCol, metallic);
                if ((mat.textures.w & 128) != 0) {
                    // Dry vulcanized rubber has a weak, broad lobe, not a polished clearcoat.
                    specular *= 0.12;
                    metalRefl *= 0.05;
                }

                // Clearcoat coat layer
                float clearcoatSpec = pow(NdotH, 256.0) * clearcoat * 1.5;

                color = diffuse + specular + ambient + metalRefl + float3(clearcoatSpec) + (mat.isGround == 3 ? float3(0.0,0.35,1.0)*emissive : float3(emissive));
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
                    color += airColor*alpha*0.3;
                }
            }
        }

        float4 prev = (isAccumulating == 1 && sampleIndex > 0) ? accumTex.read(gid) : float4(0.0);
        float4 blended = mix(float4(color, 1.0), prev, float(sampleIndex) / float(sampleIndex + 1));
        accumTex.write(blended, gid);

        // ACES Film Tone Mapping
        float3 col = blended.rgb;
        float3 a = col * (col + 0.0245786) - 0.000090537;
        float3 b = col * (0.983729 * col + 0.4329510) + 0.238081;
        float3 mapped = clamp(a / b, 0.0, 1.0);

        // Gamma 2.2 correction for sRGB display
        mapped = pow(mapped, float3(1.0 / 2.2));

        outputTex.write(float4(mapped, 1.0), gid);
    }
    """
}
