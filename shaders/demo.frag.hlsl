Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState baseColorSampler : register(s0, space2);
Texture2D<float4> normalTexture : register(t1, space2);
SamplerState normalSampler : register(s1, space2);
Texture2D<float> shadowTexture : register(t2, space2);
SamplerState shadowSampler : register(s2, space2);

cbuffer Material : register(b0, space3)
{
    float4 baseColorFactor;
    float4 flags; // alpha cutoff, encode sRGB, normal-map enable, unlit
    float4 surface; // normal scale, roughness
};

cbuffer Scene : register(b1, space3)
{
    float4 eye;
    float4 toLight; // xyz direction toward the sun, w shadow texel size
    float4 lightRow0;
    float4 lightRow1;
    float4 lightRow2;
};

float3 unit(float3 v)
{
    return v * rsqrt(max(dot(v, v), 1e-30));
}

float shadowVisibility(float3 world, float3 normal)
{
    float4 p = float4(world, 1.0);
    float3 light = float3(dot(lightRow0, p), dot(lightRow1, p), dot(lightRow2, p));
    float2 uv = light.xy * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || light.z < 0.0 || light.z > 1.0)
        return 1.0;

    // Compare with the receiver plane at each sampled texel center. Using
    // the center pixel's depth for all nine taps causes acne on tilted surfaces.
    float3 lightNormal = float3(dot(normal, lightRow0.xyz) / dot(lightRow0.xyz, lightRow0.xyz),
                               dot(normal, lightRow1.xyz) / dot(lightRow1.xyz, lightRow1.xyz),
                               dot(normal, lightRow2.xyz) / dot(lightRow2.xyz, lightRow2.xyz));
    float2 depthSlope = abs(lightNormal.z) > 1e-5
        ? lightNormal.xy / lightNormal.z * float2(-2.0, 2.0) : float2(0.0, 0.0);
    float texel = toLight.w;
    float2 center = (floor(uv / texel) + 0.5) * texel;
    float bias = 0.00015;
    float visible = 0.0;
    for (int y = -1; y <= 1; ++y)
        for (int x = -1; x <= 1; ++x)
        {
            float2 tap = clamp(center + float2(x, y) * texel, texel * 0.5, 1.0 - texel * 0.5);
            float depth = shadowTexture.SampleLevel(shadowSampler, tap, 0);
            float receiverDepth = light.z + dot(tap - uv, depthSlope);
            visible += receiverDepth - bias <= depth ? 1.0 : 0.0;
        }
    return visible / 9.0;
}

float3 mappedNormal(float3 n, float4 tangent, float3 dpdx, float3 dpdy,
                    float2 duvdx, float2 duvdy, float3 sampled)
{
    float3 t = tangent.xyz;
    float handedness = tangent.w;
    if (handedness == 0.0)
    {
        // Reconstruct the UV frame for assets with no authored tangents.
        float determinant = duvdx.x * duvdy.y - duvdy.x * duvdx.y;
        float signUV = determinant < 0 ? -1.0 : 1.0;
        if (determinant == 0.0)
            return n;
        t = (dpdx * duvdy.y - dpdy * duvdx.y) * signUV;
        float3 b = (dpdy * duvdx.x - dpdx * duvdy.x) * signUV;
        handedness = dot(cross(n, t), b) < 0 ? -1.0 : 1.0;
    }
    t -= n * dot(n, t);
    if (dot(t, t) < 1e-30)
        return n;
    t = unit(t);
    float3 b = cross(n, t) * handedness;
    return unit(t * sampled.x + b * sampled.y + n * sampled.z);
}

float4 main(float2 uv : TEXCOORD0, float3 world : TEXCOORD1, float3 normal : TEXCOORD2,
            float4 tangent : TEXCOORD3) : SV_Target0
{
    float4 color = baseColorTexture.Sample(baseColorSampler, uv) * baseColorFactor;
    float3 dpdx = ddx(world);
    float3 dpdy = ddy(world);
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);
    if (flags.x >= 0)
        clip(color.a - flags.x);

    if (flags.w == 0.0)
    {
        float3 v = unit(eye.xyz - world);
        float3 face = unit(cross(dpdx, dpdy));
        float3 n = dot(normal, normal) > 1e-30 ? unit(normal) : face;
        // Orient the authored frame with the visible side of two-sided geometry.
        if (dot(face, v) * dot(face, n) < 0.0)
        {
            n = -n;
            tangent.w = -tangent.w;
        }
        float visibility = shadowVisibility(world, face);
        if (flags.z != 0.0)
        {
            float3 sampled = normalTexture.SampleGrad(normalSampler, uv, duvdx, duvdy).xyz * 2.0 - 1.0;
            sampled.xy *= surface.x;
            n = mappedNormal(n, tangent, dpdx, dpdy, duvdx, duvdy, sampled);
        }

        float diffuse = saturate(dot(n, toLight.xyz));
        float3 halfVector = unit(toLight.xyz + v);
        float shininess = lerp(96.0, 8.0, saturate(surface.y));
        float specular = diffuse > 0.0 ? 0.24 * pow(saturate(dot(n, halfVector)), shininess) : 0.0;
        color.rgb = color.rgb * 0.22 + visibility * (color.rgb * 0.78 * diffuse + specular);
    }

    if (flags.y > 0)
    {
        float3 rgb = saturate(color.rgb);
        color.rgb = lerp(1.055 * pow(rgb, 1.0 / 2.4) - 0.055,
                         rgb * 12.92, step(rgb, 0.0031308));
    }
    return float4(color.rgb, 1.0);
}
