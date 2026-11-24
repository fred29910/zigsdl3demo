TextureCube<float4> skyTexture : register(t0, space2);
SamplerState skySampler : register(s0, space2);

float4 main(float3 ray : TEXCOORD0, nointerpolation float encodeSRGB : TEXCOORD1) : SV_Target0
{
    float3 rgb = skyTexture.Sample(skySampler, ray).rgb;
    if (encodeSRGB > 0)
        rgb = lerp(1.055 * pow(rgb, 1.0 / 2.4) - 0.055, rgb * 12.92, step(rgb, 0.0031308));
    return float4(rgb, 1.0);
}
