#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 textCoords [[attribute(2)]];
};

struct VertexOut {
    // position in clip-space
    float4 position [[position]];
    // surface normal in camera ("eye") coordinates
    float4 eyeNormal;
    // position of vertex in camera coordinates
    float4 eyePosition;
    // texture coordinates
    float2 textCoords;
};

struct Uniforms {
    // transforms vertices and normals of the model into camera coordinates
    float4x4 modelViewMatrix;
    //
    float4x4 projectionMatrix;
};


vertex VertexOut vertex_main(
     VertexIn in [[stage_in]], // stage_in: built for us by loading data according to vertexDescriptor
     constant Uniforms &uniforms [[buffer(1)]]
)
{
    VertexOut out;
    // Matrix multiplication is read from right to left
    
    // position -> clip space
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * float4(in.position, 1);
    
    // normal -> camera space, for calculating lighting and reflections
    out.eyeNormal = uniforms.modelViewMatrix * float4(in.normal, 0);
    
    // position -> camera space
    out.eyePosition = uniforms.modelViewMatrix * float4(in.position, 1);
    
    out.textCoords = in.textCoords;
    return out;
}

fragment float4 fragment_main(VertexOut fragmentIn [[stage_in]])
{
    return float4(1, 0, 0, 1);
}
