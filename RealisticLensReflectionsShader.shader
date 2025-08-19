// author : Koczalski
// 2025-08-18
// Unity Built-in RP ShaderLab
Shader "KOCZALSKI/RealisticLensReflections"
{
    Properties
    {
        _OutsideIOR        ("Outside IOR (n1)", Float) = 1.000293
        _InsideIOR         ("Inside  IOR (n2)", Float) = 1.5
        _ScreenOffsetScale ("Screen Offset Scale", Range(0,1)) = 0.18

        [Toggle(_BYPASS_STENCIL)] _BypassStencil ("Bypass Stencil (debug)", Float) = 0
        _ForceOffsetXY      ("Force Offset XY (debug)", Vector) = (0,0,0,0)
        _ForceOffsetScale   ("Force Offset Scale (debug)", Range(0,1)) = 0.0
        _DebugMode          ("Debug Mode (0:Normal 1:OffsetVec 2:GrabOnly)", Range(0,2)) = 0

        _FresnelScale      ("Fresnel Scale", Range(0,1)) = 0.7
        _ReflectTint       ("Reflect Tint", Color) = (1,1,1,1)

        _Tint              ("Tint", Color) = (1,1,1,1)
        _Alpha             ("Alpha", Range(0,1)) = 1

        _StencilRef        ("Stencil Ref", Range(0,255)) = 1
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
            #pragma shader_feature_local _BYPASS_STENCIL
            #pragma vertex   vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _GrabTexture;
            float4    _GrabTexture_TexelSize;

            float  _OutsideIOR, _InsideIOR;
            float  _ScreenOffsetScale;
            float  _FresnelScale;
            fixed4 _ReflectTint;

            float4 _ForceOffsetXY;
            float  _ForceOffsetScale;
            float  _DebugMode;

            fixed4 _Tint;
            float  _Alpha;

            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; };
            struct v2f {
                float4 pos:SV_POSITION;
                float3 wpos:TEXCOORD0;
                float3 wnor:TEXCOORD1;
                float4 sp :TEXCOORD2;
            };

            v2f vert(appdata v){
                v2f o;
                o.pos  = UnityObjectToClipPos(v.vertex);
                o.wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.wnor = UnityObjectToWorldNormal(v.normal);
                o.sp   = ComputeGrabScreenPos(o.pos);
                return o;
            }

            float FresnelSchlick(float cosTheta, float n1, float n2){
                float R0 = (n1-n2)/(n1+n2); R0 *= R0;
                float m = saturate(1.0 - cosTheta);
                return R0 + (1.0 - R0)*m*m*m*m*m;
            }

            fixed4 DoRefract(v2f i)
            {
                float3 N = normalize(i.wnor);
                float3 V = normalize(_WorldSpaceCameraPos - i.wpos);

                float n1=_OutsideIOR, n2=_InsideIOR;
                float3 Nf=N; float VN = dot(V,Nf);
                if (VN < 0){ Nf = -Nf; VN = -VN; n1=_InsideIOR; n2=_OutsideIOR; }

                float3 I = -V;
                float  eta = n1/n2;
                float3 T = refract(I, Nf, eta);
                if (all(T == 0)) T = reflect(I, Nf);
                T = normalize(T);

                float3 Tv = mul((float3x3)UNITY_MATRIX_V, T);
                float z   = max(0.001, abs(Tv.z));
                float2 offset = (Tv.xy / z) * _ScreenOffsetScale;

                offset += _ForceOffsetXY.xy * _ForceOffsetScale;

                if (_DebugMode >= 1.0){
                    if (_DebugMode < 1.5){
                        float2 o = offset * 8.0;
                        return fixed4(0.5 + o.x, 0.5 + o.y, 0.5, 1);
                    }
                }

                float4 suv = i.sp; suv.xy += offset * i.sp.w;
                fixed4 refrCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(suv));

                if (_DebugMode >= 2.0){
                    refrCol.a = 1;
                    return refrCol;
                }

                float3 Rw = reflect(-V, Nf);
                float3 Rv = mul((float3x3)UNITY_MATRIX_V, Rw);
                float rz  = max(0.001, abs(Rv.z));
                float2 roffset = (Rv.xy / rz) * (_ScreenOffsetScale * 0.6);
                float4 rsuv = i.sp; rsuv.xy += roffset * i.sp.w;
                fixed4 reflCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(rsuv)) * _ReflectTint;

                float F = FresnelSchlick(saturate(VN), n1, n2) * _FresnelScale;

                fixed4 col = lerp(refrCol, reflCol, saturate(F));
                col.rgb *= _Tint.rgb;
                col.a    = _Alpha * _Tint.a;
                return col;
            }

            fixed4 frag(v2f i):SV_Target
            {
                return DoRefract(i);
            }
            ENDCG
        }

        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma shader_feature_local _BYPASS_STENCIL
            #pragma vertex   vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _GrabTexture; float4 _GrabTexture_TexelSize;
            float  _OutsideIOR, _InsideIOR, _ScreenOffsetScale;
            float  _FresnelScale; fixed4 _ReflectTint;
            float4 _ForceOffsetXY; float _ForceOffsetScale; float _DebugMode;
            fixed4 _Tint; float _Alpha;

            struct appdata { float4 vertex:POSITION; float3 normal:NORMAL; };
            struct v2f { float4 pos:SV_POSITION; float3 wpos:TEXCOORD0; float3 wnor:TEXCOORD1; float4 sp:TEXCOORD2; };

            v2f vert(appdata v){
                v2f o;
                o.pos  = UnityObjectToClipPos(v.vertex);
                o.wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.wnor = UnityObjectToWorldNormal(v.normal);
                o.sp   = ComputeGrabScreenPos(o.pos);
                return o;
            }

            float FresnelSchlick(float cosTheta, float n1, float n2){
                float R0=(n1-n2)/(n1+n2); R0*=R0;
                float m=saturate(1.0 - cosTheta);
                return R0 + (1.0 - R0)*m*m*m*m*m;
            }

            fixed4 frag(v2f i):SV_Target
            {
            #ifndef _BYPASS_STENCIL
                return fixed4(0,0,0,0);
            #else
                float3 N = normalize(i.wnor);
                float3 V = normalize(_WorldSpaceCameraPos - i.wpos);
                float n1=_OutsideIOR, n2=_InsideIOR; float3 Nf=N; float VN=dot(V,Nf);
                if (VN<0){ Nf=-Nf; VN=-VN; n1=_InsideIOR; n2=_OutsideIOR; }

                float3 I=-V; float eta=n1/n2; float3 T=refract(I,Nf,eta); if(all(T==0)) T=reflect(I,Nf);
                T=normalize(T);

                float3 Tv=mul((float3x3)UNITY_MATRIX_V,T);
                float z=max(0.001,abs(Tv.z));
                float2 offset=(Tv.xy/z)*_ScreenOffsetScale;
                offset += _ForceOffsetXY.xy * _ForceOffsetScale;

                if(_DebugMode>=1.0){
                    if(_DebugMode<1.5) return fixed4(0.5+offset.x*8.0, 0.5+offset.y*8.0, 0.5, 1);
                }

                float4 suv=i.sp; suv.xy += offset * i.sp.w;
                fixed4 refrCol = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(suv));

                if(_DebugMode>=2.0){ refrCol.a=1; return refrCol; }

                float3 Rw=reflect(-V,Nf); float3 Rv=mul((float3x3)UNITY_MATRIX_V,Rw); float rz=max(0.001,abs(Rv.z));
                float2 roffset=(Rv.xy/rz)*(_ScreenOffsetScale*0.6);
                float4 rsuv=i.sp; rsuv.xy+=roffset*i.sp.w;
                fixed4 reflCol=tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(rsuv))*_ReflectTint;

                float F=FresnelSchlick(saturate(VN),n1,n2)*_FresnelScale;
                fixed4 col=lerp(refrCol,reflCol,saturate(F));
                col.rgb*=_Tint.rgb; col.a=_Alpha*_Tint.a;
                return col;
            #endif
            }
            ENDCG
        }
    }
    FallBack Off
}
