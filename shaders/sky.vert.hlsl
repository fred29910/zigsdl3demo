cbuffer Frame : register(b0, space1)
{
    float4 eye;
    float4 right;
    float4 up;
    float4 forward;
    float4 projection;
    float4 flags; // encode sRGB
};

struct VertexOutput
{
    float4 position : SV_Position;
    float3 ray : TEXCOORD0;
    nointerpolation float encodeSRGB : TEXCOORD1;
};

VertexOutput main(uint vertex : SV_VertexID)
{
    float2 corner = float2(vertex == 1 ? 3.0 : -1.0, vertex == 2 ? 3.0 : -1.0);
    VertexOutput output;
    output.position = float4(corner, 1.0, 1.0);
    output.ray = forward.xyz + right.xyz * corner.x / projection.x + up.xyz * corner.y / projection.y;
    output.encodeSRGB = flags.x;
    return output;
}
