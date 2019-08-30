import Foundation
import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate  {

    private let mtkView: MTKView
    private let device: MTLDevice
    private var vertexDescriptor: MTLVertexDescriptor!
    private var meshes: [MTKMesh] = []

    init(view: MTKView){
        self.mtkView = view
        self.device = view.device!
        super.init()
        loadResources()
    }

    private func loadResources() {
        let modelURL = Bundle.main.url(forResource: "teapot", withExtension: "obj")

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        self.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)!

        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        do {
            (_, meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        } catch {
            fatalError("Could not extract meshes from Model I/O asset")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }

    func draw(in view: MTKView) {

    }
}
