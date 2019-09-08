import Foundation
import Metal
import MetalKit
import simd

struct Uniforms {
    var modelMatrix: float4x4
    var viewProjectionMatrix: float4x4
    var normalMatrix: float3x3
}

class Renderer: NSObject, MTKViewDelegate  {

    private let mtkView: MTKView
    private let device: MTLDevice // GPU
    private let commandQueue: MTLCommandQueue

    private let vertexDescriptor: MDLVertexDescriptor
    private let renderPipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private var meshes: [MTKMesh] = []
    var time: Float = 0

    // Colors / texture
    private let baseColorTexture: MTLTexture
    private let samplerState: MTLSamplerState


    init(view: MTKView){
        self.mtkView = view
        self.device = view.device!
        self.commandQueue = device.makeCommandQueue()!
        vertexDescriptor = Renderer.createVertexDescriptor()
        renderPipeline = Renderer.buildPipeline(device: device, view: view, vertexDescriptor: vertexDescriptor)
        meshes = Renderer.loadResources(device: device, vertexDescriptor: vertexDescriptor)
        baseColorTexture = Renderer.loadTexture(device: device)
        depthStencilState = Renderer.createDepthStencilState(device: device)
        samplerState = Renderer.createSamplerState(device: device)
        super.init()
    }

    private class func createSamplerState(device: MTLDevice) -> MTLSamplerState {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Could not make sampler state")
        }
        return samplerState
    }

    private class func loadTexture(device: MTLDevice) -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.generateMipmaps: true, .SRGB: true]
        do {
            return try textureLoader.newTexture(name: "tiles_baseColor", scaleFactor: 1.0, bundle: nil, options: options)
        }
        catch {
            fatalError("Could not load texture: \(error)")
        }
    }

    private static func createDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        // Keep fragments closest to the camera
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true // or else it doesn't work
        guard let state = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            fatalError("Could not create depthStencilState")
        }
    return state
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
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
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

    private static func createUniforms(view: MTKView, time: Float) -> Uniforms {
        let angle = -time
        let modelMatrix = float4x4(rotationAbout: float3(0, 1, 0), by: angle) *  float4x4(scaleBy: 2)
        // describes camera position
        let viewMatrix = float4x4(translationBy: float3(0, 0, -2))

        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        // Anything nearer than .1 units and further away than 100 units will bel clipped (not visible)
        let projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        let viewProjectionMatrix = projectionMatrix * viewMatrix;
        return Uniforms(modelMatrix: modelMatrix, viewProjectionMatrix: viewProjectionMatrix, normalMatrix: modelMatrix.normalMatrix)
    }

    func draw(in view: MTKView) {
        time += 1 / Float(mtkView.preferredFramesPerSecond)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // tells Metal which textures we will actually be drawing to.
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        var uniforms = Renderer.createUniforms(view: view, time: time)

        commandEncoder.setRenderPipelineState(renderPipeline)
        commandEncoder.setDepthStencilState(depthStencilState)
        commandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        commandEncoder.setFragmentTexture(baseColorTexture, index: 0)
        commandEncoder.setFragmentSamplerState(samplerState, index: 0)

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
