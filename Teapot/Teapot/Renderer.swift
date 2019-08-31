import Foundation
import Metal
import MetalKit
import simd

struct Uniforms {
    var modelViewMatrix: float4x4
    var projectionMatrix: float4x4
}

class Renderer: NSObject, MTKViewDelegate  {

    private let mtkView: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let vertexDescriptor: MDLVertexDescriptor
    private let renderPipeline: MTLRenderPipelineState
    private var meshes: [MTKMesh] = []
    var time: Float = 0

    init(view: MTKView){
        self.mtkView = view
        self.device = view.device!
        self.commandQueue = device.makeCommandQueue()!
        vertexDescriptor = Renderer.createVertexDescriptor()
        renderPipeline = Renderer.buildPipeline(device: device, view: view, vertexDescriptor: vertexDescriptor)
        meshes = Renderer.loadResources(device: device, vertexDescriptor: vertexDescriptor)
        super.init()
    }

    private static func buildPipeline(device: MTLDevice, view: MTKView, vertexDescriptor: MDLVertexDescriptor) -> MTLRenderPipelineState {
        // get library (collection of shader functions) from main bundle.
        // Shaders are defined in Shaders.metal
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default library from main bundle")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        // tell Metal the format (pixel layout) of the textures we will be drawing to
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        // Compile shaders, so they will run on GPU
        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            fatalError("Could not create render pipeline state: \(error)")
        }
    }

    private static func createVertexDescriptor() -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        return vertexDescriptor
    }

    private static func loadResources(device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) -> [MTKMesh] {
        let modelURL = Bundle.main.url(forResource: "teapot", withExtension: "obj")

        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        do {
            let (_, meshes) = try MTKMesh.newMeshes(asset: asset, device: device)
            return meshes
        } catch {
            fatalError("Could not extract meshes from Model I/O asset")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }

    func draw(in view: MTKView) {

        time += 1 / Float(mtkView.preferredFramesPerSecond)
        let angle = -time
        let modelMatrix = float4x4(rotationAbout: float3(0, 1, 0), by: angle) *  float4x4(scaleBy: 2)
        // describes camera position
        let viewMatrix = float4x4(translationBy: float3(0, 0, -2))
        let modelViewMatrix = viewMatrix * modelMatrix
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        // Anything nearer than .1 units and further away than 100 units will bel clipped (not visible)
        let projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)

        var uniforms = Uniforms(modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        // tells Metal which textures we will actually be drawing to.
        if let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {

            commandEncoder.setRenderPipelineState(renderPipeline)

            commandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)

            for mesh in meshes {
                guard let vertexBuffer = mesh.vertexBuffers.first else {
                    continue
                }
                commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)

                for submesh in mesh.submeshes {
                    commandEncoder.draw(submesh: submesh)
                }
            }
            // tell encoder we will not be drawing any more things
            commandEncoder.endEncoding()
            // callback to present the result
            commandBuffer.present(drawable)
            // ship commands to GPU
            commandBuffer.commit()
        }
    }
}

extension MTLRenderCommandEncoder {
    // tells Metal to render a sequence of primitivies (shapes)
    func draw(submesh: MTKSubmesh) {
        self.drawIndexedPrimitives(type: submesh.primitiveType, // triangle, line, point etc
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset)
    }
}
