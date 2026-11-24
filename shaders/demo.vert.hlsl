cbuffer Frame : register(b0, space1)
{
    float4 eye;
    float4 right;
    float4 up;
    float4 forward;
    float4 projection; // x/y scale, z scale, z offset
    float4 model_row0;
    float4 model_row1;
    float4 model_row2;
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
    float3 world = float3(dot(model_row0, p), dot(model_row1, p), dot(model_row2, p));
    float3 relative = world - eye.xyz;
    float3 view = float3(dot(relative, right.xyz), dot(relative, up.xyz), dot(relative, forward.xyz));

    VertexOutput output;
    output.position = float4(view.xy * projection.xy, view.z * projection.z + projection.w, view.z);
    output.uv = input.uv;
    return output;
}
