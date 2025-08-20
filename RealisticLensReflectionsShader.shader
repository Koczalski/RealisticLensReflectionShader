// author : Koczalski
// 2025-08-18
// Unity Built-in RP ShaderLab
Shader "KOCZALSKI/RealisticLensReflections"
{
    Properties
    {
        _OutsideIOR ("Outside IOR (n1)", Float) = 1.000293
        _InsideIOR  ("Inside IOR (n2)",  Float) = 1.586
        _ScreenOffsetScale ("Screen Offset Scale", Range(0,2)) = 0.014
        _ProjDistance ("Projection Distance (view meters)", Range(0.01,2.0)) = 0.20

        _ThinPlateMix ("Thin Plate Mix (0:single 1:double)", Range(0,1)) = 0.30
        _Thickness    ("Apparent Thickness", Range(0,1)) = 0.50

        _SwirlStrength ("Edge Swirl Strength (rad)", Range(0,2)) = 0.10
        _SwirlExponent ("Edge Swirl Exponent", Range(0.1,6)) = 2.6

        _FresnelScale ("Fresnel Scale", Range(0,1)) = 0.60
        _ReflectTint  ("Reflect Tint", Color) = (0.86,1,0.96,1)

        _Tint  ("Tint", Color) = (1,1,1,1)
        _Alpha ("Alpha", Range(0,1)) = 1

        _ObliqueClamp ("Max UV Offset (grazing)", Range(0,0.2)) = 0.06
        _GrazingFadeStart ("Grazing Fade Start (VN)", Range(0,1)) = 0.18
        _GrazingFadeEnd   ("Grazing Fade End (VN)",   Range(0,1)) = 0.35

        _Minify ("Central Minification (signed)", Range(-0.3,0.3)) = -0.10
        _EdgePrism ("Edge Prism Shift (UV)", Range(0,0.08)) = 0.020
        _PrismRadius ("Prism/Edge Start Radius (UV)", Range(0.05,0.5)) = 0.22
        _PrismExponent ("Prism Edge Exponent", Range(0.5,4)) = 1.6

        _SpiralStrength2 ("Lens Spiral Strength (rad)", Range(0,2)) = 0.35
        _SpiralExponent2 ("Lens Spiral Exponent", Range(0.5,4)) = 1.8
        _SpiralRadius ("Spiral Radius (UV)", Range(0.05,0.5)) = 0.26

        _DebugMode ("Debug (0:off 1:offset 2:grab)", Range(0,2)) = 0
        _StencilRef("Stencil Ref", Range(0,255)) = 1
    }

    SubShader
    {
        Tags { "Queue"="Transparent+30" "RenderType"="Transparent" "IgnoreProjector"="True" }
        Cull Back
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        GrabPass { "_GrabTexture" }

        Pass
        {
            Stencil { Ref [_StencilRef] Comp NotEqual Pass Keep }

            CGPROGRAM
            #pragma target 3.0
            #pragma vertex   vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _GrabTexture;
            float4 _GrabTexture_TexelSize;

            float _OutsideIOR, _InsideIOR;
            float _ScreenOffsetScale, _ProjDistance;

            float _ThinPlateMix, _Thickness;
            float _SwirlStrength, _SwirlExponent;

            float _FresnelScale; fixed4 _ReflectTint;
            fixed4 _Tint; float _Alpha;
            float _DebugMode;

            float _ObliqueClamp, _GrazingFadeStart, _GrazingFadeEnd;

            float _Minify, _EdgePrism, _PrismRadius, _PrismExponent;
            float _SpiralStrength2, _SpiralExponent2, _SpiralRadius;

            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; };
            struct v2f
            {
                float4 pos:SV_POSITION;
                float3 wpos:TEXCOORD0;
                float3 wnor:TEXCOORD1;
                float4 sp:  TEXCOORD2;
                float4 csp: TEXCOORD3;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos  = UnityObjectToClipPos(v.vertex);
                o.wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.wnor = UnityObjectToWorldNormal(v.normal);
                o.sp   = ComputeGrabScreenPos(o.pos);

                float3 objOriginWS = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;
                float4 centerClip = UnityWorldToClipPos(objOriginWS);
                o.csp = ComputeGrabScreenPos(centerClip);
                return o;
            }

            float2 ToScreenUVFromView(float3 vp)
            {
                float4 cp = mul(UNITY_MATRIX_P, float4(vp,1));
                float2 ndc = cp.xy / max(1e-6, cp.w);
                float2 uv  = ndc * 0.5 + 0.5;
                #if UNITY_UV_STARTS_AT_TOP
                    uv.y = 1.0 - uv.y;
                #endif
                if (_ProjectionParams.x < 0) uv.y = 1.0 - uv.y;
                return uv;
            }

            float3 slerpWS(float3 a, float3 b, float t)
            {
                a = normalize(a); b = normalize(b);
                float d = clamp(dot(a,b), -1.0, 1.0);
                if (d > 0.9995) return normalize(lerp(a,b,t));
                float o = acos(d), s = sin(o);
                return normalize(a * sin((1.0-t)*o)/s + b * sin(t*o)/s);
            }

            float2 ProjectionDelta(float3 Pview, float3 DviewNorm, float L)
            {
                float3 Q = Pview + DviewNorm * L;
                float2 uvP = ToScreenUVFromView(Pview);
                float2 uvQ = ToScreenUVFromView(Q);
                return (uvQ - uvP);
            }

            float AngleScale(float VN, float n1, float n2)
            {
                float cosTi = saturate(VN);
                float sinTi = sqrt(max(0, 1.0 - cosTi*cosTi));
                float r = n1 / n2;
                float sinTt = saturate(r * sinTi);
                float cosTt = sqrt(max(0, 1.0 - sinTt*sinTt));
                float ti = acos(cosTi);
                float tt = acos(cosTt);
                float d  = abs(tt - ti);
                float k = saturate(d / 1.2);
                return k;
            }

            float AngleDistance(float VN)
            {
                float graz = pow(1.0 - VN, 1.0);
                return _ProjDistance * (1.0 + 1.25 * graz);
            }

            float FresnelSchlick(float cosTheta, float n1, float n2)
            {
                float R0 = (n1-n2)/(n1+n2); R0*=R0;
                float m = saturate(1.0 - cosTheta);
                return R0 + (1.0 - R0) * m*m*m*m*m;
            }

            float2 rot2(float2 p, float ang){
                float s = sin(ang), c = cos(ang);
                return float2(c*p.x - s*p.y, s*p.x + c*p.y);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 Pview = mul(UNITY_MATRIX_V, float4(i.wpos,1)).xyz;
                float3 Vw    = normalize(_WorldSpaceCameraPos - i.wpos);
                float3 Nw    = normalize(i.wnor);

                float n1 = _OutsideIOR, n2 = _InsideIOR;
                float3 Nf = Nw;
                float VNw = dot(Vw, Nf);
                if (VNw < 0) { Nf = -Nf; VNw = -VNw; n1 = _InsideIOR; n2 = _OutsideIOR; }

                float3 Iw = -Vw;
                float3 T0w = refract(Iw, Nf, n1/n2); if (all(T0w==0)) T0w = reflect(Iw, Nf);
                float grazPow = pow(saturate(1.0 - VNw), 1.25);
                float3 T1w = refract(Iw, Nf, n1/(n2 + 0.35*grazPow)); if (all(T1w==0)) T1w = reflect(Iw, Nf);
                float3 Tw  = slerpWS(T0w, normalize(T1w), grazPow);

                float3 Dview = normalize(mul((float3x3)UNITY_MATRIX_V, Tw));

                float VN = VNw;
                float scaleA = AngleScale(VN, n1, n2);
                float L      = AngleDistance(VN);
                float2 baseDelta = ProjectionDelta(Pview, Dview, L);
                float2 offset = baseDelta * (_ScreenOffsetScale * scaleA);

                if (_ThinPlateMix > 0.001 || _Thickness > 0.001)
                {
                    float3 Nout = -Nf;
                    float3 Tout = refract(Tw, Nout, n2/n1); if (all(Tout==0)) Tout = reflect(Tw, Nout);
                    float3 Dv2  = normalize(mul((float3x3)UNITY_MATRIX_V, normalize(Tout)));
                    float2 delta2 = ProjectionDelta(Pview, Dv2, L * (_Thickness * 0.5 + 1.0));
                    offset = lerp(offset, delta2 * (_ScreenOffsetScale * scaleA), saturate(_ThinPlateMix));
                }

                if (_SwirlStrength > 0.0001)
                {
                    float edge = pow(1.0 - VN, _SwirlExponent);
                    offset = rot2(offset, edge * _SwirlStrength);
                }

                float grazingGate = smoothstep(_GrazingFadeStart, _GrazingFadeEnd, VN);
                offset *= grazingGate;
                float len = length(offset);
                if (len > 1e-6)
                {
                    float maxUV = lerp(_ObliqueClamp * 0.5, _ObliqueClamp, saturate(VN));
                    offset *= min(1.0, maxUV / len);
                }

                float2 baseUV = i.sp.xy / i.sp.w;
                float2 cUV    = i.csp.xy / i.csp.w;
                float2 rv     = baseUV - cUV;
                float  r      = length(rv);
                float2 rvN    = (r>1e-6) ? rv / r : float2(0,0);

                rv *= (1.0 + _Minify);

                float rNorm = (_SpiralRadius > 1e-6) ? saturate(r / _SpiralRadius) : r;
                float spiralAng = _SpiralStrength2 * pow(rNorm, _SpiralExponent2) * pow(1.0 - VN, 1.0);
                rv = rot2(rv, spiralAng);

                float edgeGate = pow(saturate((r - _PrismRadius) / max(1e-6, (0.5 - _PrismRadius))), _PrismExponent);
                rv += rvN * (_EdgePrism * edgeGate);

                float2 lensUV = cUV + rv + offset;

                if (_DebugMode >= 1.0 && _DebugMode < 1.5)
                {
                    float2 o = (lensUV - baseUV) * 8.0;
                    return fixed4(0.5 + o.x, 0.5 + o.y, 0.5, 1);
                }

                float4 suv; suv.xy = lensUV * i.sp.w; suv.zw = i.sp.zw;
                float2 uv = clamp(suv.xy/suv.w, float2(0.001,0.001), float2(0.999,0.999));
                suv.xy = uv * suv.w;
                fixed4 refrCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(suv));

                if (_DebugMode >= 2.0 && _DebugMode < 2.5)
                { refrCol.a = 1; return refrCol; }

                float3 Rw = reflect(-Vw, Nf);
                float3 Rv = mul((float3x3)UNITY_MATRIX_V, Rw);
                float rz = max(1e-6, abs(Rv.z));
                float2 ro = (Rv.xy/rz) * (_ScreenOffsetScale * 0.6);
                float4 rsuv = i.sp; rsuv.xy += ro * i.sp.w;
                float2 ruv = clamp(rsuv.xy/rsuv.w, float2(0.001,0.001), float2(0.999,0.999));
                rsuv.xy = ruv * rsuv.w;
                fixed4 reflCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(rsuv)) * _ReflectTint;

                float F = FresnelSchlick(VN, _OutsideIOR, _InsideIOR) * _FresnelScale;
                float refrWeight = (1.0 - saturate(F)) * grazingGate;
                float reflWeight = 1.0 - refrWeight;
                fixed4 col = refrCol * refrWeight + reflCol * reflWeight;

                col.rgb *= _Tint.rgb; col.a = _Alpha * _Tint.a;
                return col;
            }
            ENDCG
        }
    }
    FallBack Off
}
