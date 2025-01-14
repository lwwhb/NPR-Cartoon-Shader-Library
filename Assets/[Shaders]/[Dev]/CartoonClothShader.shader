﻿///
/// Double-sided Cloth Shader
/// Reference : UnityChan Cloth Shader 
///

Shader "Cartoon-Shader-Library/CartoonClothShader" 
{
	Properties
	{
		_Color ("Main Color", Color) = (1, 1, 1, 1)
		_ShadowColor ("Shadow Color", Color) = (0.8, 0.8, 1, 1)
		_SpecularPower ("Specular Power", Float) = 20
		_EdgeThickness ("Outline Thickness", Float) = 1
		
		_MainTex ("Diffuse", 2D) = "white" {}
		_FalloffSampler ("Falloff Control", 2D) = "white" {}
		_RimLightSampler ("RimLight Control", 2D) = "white" {}
		_SpecularReflectionSampler ("Specular / Reflection Mask", 2D) = "white" {}
		_EnvMapSampler ("Environment Map", 2D) = "" {} 
		_NormalMapSampler ("Normal Map", 2D) = "" {} 
	}

	SubShader
	{
		Tags
		{
			"RenderType"="Opaque"
			"Queue"="Geometry"
			"LightMode"="ForwardBase"
		}		

		
		//------------------------------------------
		// 主Pass
		//------------------------------------------
		Pass
		{
			Cull Off
			ZTest LEqual


			CGPROGRAM

			#pragma multi_compile_fwdbase
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"

			// Character shader
			// Includes falloff shadow and highlight, specular, reflection, and normal mapping
			#define ENABLE_CAST_SHADOWS

			#ifdef ENABLE_CAST_SHADOWS

			// Structure from vertex shader to fragment shader
			struct v2f
			{
				float4 pos      : SV_POSITION;
				LIGHTING_COORDS( 0, 1 )
				float2 uv : TEXCOORD2;
				float3 eyeDir : TEXCOORD3;
				float3 normal   : TEXCOORD4;
				float3 tangent  : TEXCOORD5;
				float3 binormal : TEXCOORD6;
				float3 lightDir : TEXCOORD7;
			};

			#else

			// Structure from vertex shader to fragment shader
			struct v2f
			{
				float4 pos      : SV_POSITION;
				float2 uv       : TEXCOORD0;
				float3 eyeDir   : TEXCOORD1;
				float3 normal   : TEXCOORD2;
				float3 tangent  : TEXCOORD3;
				float3 binormal : TEXCOORD4;
				float3 lightDir : TEXCOORD5;
			};
			#endif

			//#include "CharaMain.cg"

			// Material parameters
			float4 _Color;
			float4 _ShadowColor;
			float4 _LightColor0;
			float _SpecularPower;
			float4 _MainTex_ST;

			// Textures
			sampler2D _MainTex;
			sampler2D _FalloffSampler;
			sampler2D _RimLightSampler;
			sampler2D _SpecularReflectionSampler;
			sampler2D _EnvMapSampler;
			sampler2D _NormalMapSampler;

			// Constants
			#define FALLOFF_POWER 0.3


			// Float types
			#define float_t  half
			#define float2_t half2
			#define float3_t half3
			#define float4_t half4

			// Vertex shader
			v2f vert( appdata_tan v )
			{
				v2f o;
				o.pos = UnityObjectToClipPos( v.vertex );
				o.uv.xy = TRANSFORM_TEX( v.texcoord.xy, _MainTex );
				o.normal = normalize( mul( unity_ObjectToWorld, float4_t( v.normal, 0 ) ).xyz );
				
				// Eye direction vector
				half4 worldPos = mul( unity_ObjectToWorld, v.vertex );
				o.eyeDir.xyz = normalize( _WorldSpaceCameraPos.xyz - worldPos.xyz ).xyz;
				
				// Binormal and tangent (for normal map)
				o.tangent = v.tangent.xyz;
				o.binormal = cross( v.normal, v.tangent.xyz ) * v.tangent.w;
				
				o.lightDir = WorldSpaceLightDir( v.vertex );

			#ifdef ENABLE_CAST_SHADOWS
				TRANSFER_VERTEX_TO_FRAGMENT( o );
			#endif

				return o;
			}

			// Overlay blend
			inline float3_t GetOverlayColor( float3_t inUpper, float3_t inLower )
			{
				float3_t oneMinusLower = float3_t( 1.0, 1.0, 1.0 ) - inLower;
				float3_t valUnit = 2.0 * oneMinusLower;
				float3_t minValue = 2.0 * inLower - float3_t( 1.0, 1.0, 1.0 );
				float3_t greaterResult = inUpper * valUnit + minValue;

				float3_t lowerResult = 2.0 * inLower * inUpper;

				half3 lerpVals = round(inLower);
				return lerp(lowerResult, greaterResult, lerpVals);
			}


			// Fragment shader
			float4 frag( v2f i ) : COLOR
			{
				float4_t diffSamplerColor = tex2D( _MainTex, i.uv.xy );

				float3_t normalVec = i.normal;// GetNormalFromMap( i );
				
				// Falloff. Convert the angle between the normal and the camera direction into a lookup for the gradient
				float_t normalDotEye = dot( normalVec, i.eyeDir.xyz );
				float_t falloffU = clamp( 1.0 - abs( normalDotEye ), 0.02, 0.98 );
				float4_t falloffSamplerColor = FALLOFF_POWER * tex2D( _FalloffSampler, float2( falloffU, 0.25f ) );
				float3_t shadowColor = diffSamplerColor.rgb * diffSamplerColor.rgb;
				float3_t combinedColor = lerp( diffSamplerColor.rgb, shadowColor, falloffSamplerColor.r );
				combinedColor *= ( 1.0 + falloffSamplerColor.rgb * falloffSamplerColor.a );

				// Specular
				// Use the eye vector as the light vector
				float4_t reflectionMaskColor = tex2D( _SpecularReflectionSampler, i.uv.xy );
				float_t specularDot = dot( normalVec, i.eyeDir.xyz );
				float4_t lighting = lit( normalDotEye, specularDot, _SpecularPower );
				float3_t specularColor = saturate( lighting.z ) * reflectionMaskColor.rgb * diffSamplerColor.rgb;
				combinedColor += specularColor;
				
				// Reflection
				float3_t reflectVector = reflect( -i.eyeDir.xyz, normalVec ).xzy;
				float2_t sphereMapCoords = 0.5 * ( float2_t( 1.0, 1.0 ) + reflectVector.xy );
				float3_t reflectColor = tex2D( _EnvMapSampler, sphereMapCoords ).rgb;
				reflectColor = GetOverlayColor( reflectColor, combinedColor );

				combinedColor = lerp( combinedColor, reflectColor, reflectionMaskColor.a );
				combinedColor *= _Color.rgb * _LightColor0.rgb;
				float opacity = diffSamplerColor.a * _Color.a * _LightColor0.a;

			#ifdef ENABLE_CAST_SHADOWS
				// Cast shadows
				shadowColor = _ShadowColor.rgb * combinedColor;
				float_t attenuation = saturate( 2.0 * LIGHT_ATTENUATION( i ) - 1.0 );
				combinedColor = lerp( shadowColor, combinedColor, attenuation );
			#endif

				// Rimlight
				float_t rimlightDot = saturate( 0.5 * ( dot( normalVec, i.lightDir ) + 1.0 ) );
				falloffU = saturate( rimlightDot * falloffU );
				falloffU = tex2D( _RimLightSampler, float2( falloffU, 0.25f ) ).r;
				float3_t lightColor = diffSamplerColor.rgb; // * 2.0;
				combinedColor += falloffU * lightColor;

				return float4( combinedColor, opacity );
			}

			ENDCG
		}


		//------------------------------------------
		// outline-轮廓Pass
		//------------------------------------------
		Pass
		{
			Cull Front
			ZTest Less


			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			//#include "CharaOutline.cg"


			// Material parameters
			float4 _Color;
			float4 _LightColor0;
			float _EdgeThickness = 1.0;
			float4 _MainTex_ST;

			// Textures
			sampler2D _MainTex;

			// Structure from vertex shader to fragment shader
			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			// Float types
			#define float_t  half
			#define float2_t half2
			#define float3_t half3
			#define float4_t half4

			// Outline thickness multiplier
			#define INV_EDGE_THICKNESS_DIVISOR 0.00285
			// Outline color parameters
			#define SATURATION_FACTOR 0.6
			#define BRIGHTNESS_FACTOR 0.8

			// Vertex shader
			v2f vert( appdata_base v )
			{
				v2f o;
				o.uv = TRANSFORM_TEX( v.texcoord.xy, _MainTex );

				half4 projSpacePos = UnityObjectToClipPos( v.vertex );
				half4 projSpaceNormal = normalize( UnityObjectToClipPos( half4( v.normal, 0 ) ) );
				half4 scaledNormal = _EdgeThickness * INV_EDGE_THICKNESS_DIVISOR * projSpaceNormal; // * projSpacePos.w;

				scaledNormal.z += 0.00001;
				o.pos = projSpacePos + scaledNormal;

				return o;
			}

			// Fragment shader
			float4 frag( v2f i ) : COLOR
			{
				float4_t diffuseMapColor = tex2D( _MainTex, i.uv );

				float_t maxChan = max( max( diffuseMapColor.r, diffuseMapColor.g ), diffuseMapColor.b );
				float4_t newMapColor = diffuseMapColor;

				maxChan -= ( 1.0 / 255.0 );
				float3_t lerpVals = saturate( ( newMapColor.rgb - float3( maxChan, maxChan, maxChan ) ) * 255.0 );
				newMapColor.rgb = lerp( SATURATION_FACTOR * newMapColor.rgb, newMapColor.rgb, lerpVals );
				
				return float4( BRIGHTNESS_FACTOR * newMapColor.rgb * diffuseMapColor.rgb, diffuseMapColor.a ) * _Color * _LightColor0; 
			}

			ENDCG
		}

	}

	FallBack "Transparent/Cutout/Diffuse"
}
