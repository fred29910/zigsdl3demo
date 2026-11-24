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
    [[vk::location(2)]] float3 normal : TEXCOORD1;
    [[vk::location(3)]] float4 tangent : TEXCOORD2;
};

struct VertexOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 world : TEXCOORD1;
    float3 normal : TEXCOORD2;
    float4 tangent : TEXCOORD3;
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
    output.world = world;

    // Cofactors produce the inverse-transpose up to a scalar. The determinant
    // sign restores the normal direction for mirrored node transforms.
    float3 cofactor0 = cross(model_row1.xyz, model_row2.xyz);
    float3 cofactor1 = cross(model_row2.xyz, model_row0.xyz);
    float3 cofactor2 = cross(model_row0.xyz, model_row1.xyz);
    float orientation = dot(model_row0.xyz, cofactor0) < 0 ? -1.0 : 1.0;
    output.normal = orientation * float3(dot(cofactor0, input.normal), dot(cofactor1, input.normal), dot(cofactor2, input.normal));
    output.tangent = float4(dot(model_row0.xyz, input.tangent.xyz),
                            dot(model_row1.xyz, input.tangent.xyz),
                            dot(model_row2.xyz, input.tangent.xyz), input.tangent.w * orientation);
    return output;
}
