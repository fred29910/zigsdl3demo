Texture2D<float4> checker : register(t0, space2);
SamplerState checkerSampler : register(s0, space2);

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    return checker.Sample(checkerSampler, uv);
}
