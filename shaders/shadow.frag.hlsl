Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState baseColorSampler : register(s0, space2);

cbuffer Material : register(b0, space3)
{
    float4 baseColorFactor;
    float4 flags; // alpha cutoff, encode sRGB, normal-map enable, unlit
};

void main(float2 uv : TEXCOORD0)
{
    if (flags.x >= 0.0)
        clip(baseColorTexture.Sample(baseColorSampler, uv).a * baseColorFactor.a - flags.x);
}
