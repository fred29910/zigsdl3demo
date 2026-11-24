cbuffer Draw : register(b0, space1)
{
    float4 modelRow0;
    float4 modelRow1;
    float4 modelRow2;
    float4 lightRow0;
    float4 lightRow1;
    float4 lightRow2;
};

struct VertexInput
{
    [[vk::location(0)]] float3 position : POSITION;
    [[vk::location(1)]] float2 uv : TEXCOORD0;
};

struct VertexOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VertexOutput main(VertexInput input)
{
    float4 p = float4(input.position, 1.0);
    float4 world = float4(dot(modelRow0, p), dot(modelRow1, p), dot(modelRow2, p), 1.0);
    VertexOutput output;
    output.position = float4(dot(lightRow0, world), dot(lightRow1, world), dot(lightRow2, world), 1.0);
    output.uv = input.uv;
    return output;
}
