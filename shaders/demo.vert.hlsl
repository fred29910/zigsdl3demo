cbuffer Frame : register(b0, space1)
{
    float4 eye;
    float4 right;
    float4 up;
    float4 forward;
    float4 projection; // x/y scale, z scale, z offset
    float4 model;      // translation.xyz, rotation in radians
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
    float s, c, tiltS, tiltC;
    sincos(model.w, s, c);
    sincos(model.w * 0.73, tiltS, tiltC);
    float3 p = input.position;
    float3 yawed = float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
    float3 rotated = float3(yawed.x, tiltC * yawed.y - tiltS * yawed.z,
                           tiltS * yawed.y + tiltC * yawed.z);
    float3 relative = rotated + model.xyz - eye.xyz;
    float3 view = float3(dot(relative, right.xyz), dot(relative, up.xyz), dot(relative, forward.xyz));

    VertexOutput output;
    output.position = float4(view.xy * projection.xy, view.z * projection.z + projection.w, view.z);
    output.uv = input.uv;
    return output;
}
