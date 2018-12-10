//
//  SCCIImageView.m
//  SCRecorder
//
//  Created by Simon CORSIN on 14/05/14.
//  Copyright (c) 2014 rFlex. All rights reserved.
//

#import "SCImageView.h"
#import "SCSampleBufferHolder.h"
#import "SCContext.h"
//#import "GlaciesGPUBGRAInput.h"

typedef struct
{
    vector_float4 position;
    vector_float2 textureCoordinate;
} LYVertex;

#if TARGET_IPHONE_SIMULATOR
@interface SCImageView()<GLKViewDelegate>

#else
@import MetalKit;

@interface SCImageView()<GLKViewDelegate, MTKViewDelegate>

@property (nonatomic, strong) MTKView *MTKView;
#endif

@property (nonatomic, strong) GLKView *GLKView;
@property (nonatomic, strong) id<MTLCommandQueue> MTLCommandQueue;
@property (nonatomic, strong) SCSampleBufferHolder *sampleBufferHolder;
#if !TARGET_IPHONE_SIMULATOR
@property (nonatomic) CVMetalTextureCacheRef textureCache;
#endif
@property (nonatomic) id<MTLComputePipelineState> computePipelineState;

@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, assign) NSUInteger numVertices;

@end

@implementation SCImageView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self _imageViewCommonInit];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self _imageViewCommonInit];
    }
    
    return self;
}

- (void)dealloc {
    [EAGLContext setCurrentContext:nil];
}

- (void)_imageViewCommonInit {
    _scaleAndResizeCIImageAutomatically = YES;
    self.preferredCIImageTransform = CGAffineTransformIdentity;
    
    _sampleBufferHolder = [SCSampleBufferHolder new];
}

- (BOOL)loadContextIfNeeded {
    if (_context == nil) {
        SCContextType contextType = _contextType;
        if (contextType == SCContextTypeAuto) {
            contextType = [SCContext suggestedContextType];
        }
        
        NSDictionary *options = nil;
        switch (contextType) {
            case SCContextTypeCoreGraphics: {
                CGContextRef contextRef = UIGraphicsGetCurrentContext();
                
                if (contextRef == nil) {
                    return NO;
                }
                options = @{SCContextOptionsCGContextKey: (__bridge id)contextRef};
            }
                break;
            case SCContextTypeCPU:
                [NSException raise:@"UnsupportedContextType" format:@"SCImageView does not support CPU context type."];
                break;
            default:
                break;
        }
        
        self.context = [SCContext contextWithType:contextType options:options];
    }
    
    return YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    _GLKView.frame = self.bounds;
    [_GLKView setNeedsDisplay];
    
#if !(TARGET_IPHONE_SIMULATOR)
    _MTKView.frame = self.bounds;
    [_MTKView setNeedsDisplay];
#endif
}

- (void)unloadContext {
    if (_GLKView != nil) {
        [_GLKView removeFromSuperview];
        _GLKView = nil;
    }
#if !(TARGET_IPHONE_SIMULATOR)
    if (_MTKView != nil) {
        _MTLCommandQueue = nil;
        [_MTKView removeFromSuperview];
        [_MTKView releaseDrawables];
        _MTKView = nil;
    }
#endif
    _context = nil;
}

- (void)setContext:(SCContext * _Nullable)context {
    [self unloadContext];
    
    if (context != nil) {
        switch (context.type) {
            case SCContextTypeCoreGraphics:
                break;
            case SCContextTypeEAGL:
                _GLKView = [[GLKView alloc] initWithFrame:self.bounds context:context.EAGLContext];
                _GLKView.contentScaleFactor = self.contentScaleFactor;
                _GLKView.delegate = self;
                _GLKView.backgroundColor = [UIColor clearColor];
                [self insertSubview:_GLKView atIndex:0];
                break;
#if !(TARGET_IPHONE_SIMULATOR)
            case SCContextTypeMetal:
                _MTLCommandQueue = [context.MTLDevice newCommandQueue];
                _MTKView = [[MTKView alloc] initWithFrame:self.bounds device:context.MTLDevice];
                _MTKView.clearColor = MTLClearColorMake(0, 0, 0, 0);
                _MTKView.contentScaleFactor = self.contentScaleFactor;
                _MTKView.delegate = self;
                _MTKView.enableSetNeedsDisplay = YES;
                _MTKView.framebufferOnly = NO;
                [self insertSubview:_MTKView atIndex:0];
                break;
#endif
            default:
                [NSException raise:@"InvalidContext" format:@"Unsupported context type: %d. SCImageView only supports CoreGraphics, EAGL and Metal", (int)context.type];
                break;
        }
    }
    
    _context = context;
}

- (void)setNeedsDisplay {
    [super setNeedsDisplay];
    
    [_GLKView setNeedsDisplay];
#if !(TARGET_IPHONE_SIMULATOR)
    [_MTKView setNeedsDisplay];
#endif
}

- (UIImage *)renderedUIImage {
    UIImage *returnedImage = nil;
    CIImage *image = [self renderedCIImage];
    
    if (image != nil) {
        CIContext *context = nil;
        if (![self loadContextIfNeeded]) {
            context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @(NO)}];
        } else {
            context = _context.CIContext;
        }
        
        CGImageRef imageRef = [context createCGImage:image fromRect:image.extent];
        
        if (imageRef != nil) {
            returnedImage = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
        }
    }
    
    return returnedImage;
}

- (CIImage *)renderedCIImage {
    CMSampleBufferRef sampleBuffer = _sampleBufferHolder.sampleBuffer;
    
    if (sampleBuffer != nil) {
        _CIImage = [CIImage imageWithCVPixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer)];
        _sampleBufferHolder.sampleBuffer = nil;
    }
    
    CIImage *image = _CIImage;
    
    if (image != nil) {
        image = [image imageByApplyingTransform:self.preferredCIImageTransform];
        
        //        if (self.context.type != SCContextTypeEAGL) {
        //            image = [image imageByApplyingOrientation:4];
        //        }
    }
    
    return image;
}

- (CGRect)scaleAndResizeCIImage:(CIImage *)image forRect:(CGRect)rect {
    CGSize imageSize = image.extent.size;
    
    CGFloat horizontalScale = rect.size.width / imageSize.width;
    CGFloat verticalScale = rect.size.height / imageSize.height;
    
    UIViewContentMode mode = self.contentMode;
    
    if (mode == UIViewContentModeScaleAspectFill) {
        horizontalScale = MAX(horizontalScale, verticalScale);
        verticalScale = horizontalScale;
    } else if (mode == UIViewContentModeScaleAspectFit) {
        horizontalScale = MIN(horizontalScale, verticalScale);
        verticalScale = horizontalScale;
    }
    
    CGFloat newWidth = imageSize.width * horizontalScale;
    CGFloat newHeight = imageSize.height * verticalScale;
    CGFloat x = (rect.size.width - newWidth) * 0.5;
    CGFloat y = (rect.size.height - newHeight) * 0.5;
    
    CGRect result = CGRectMake(x, y, newWidth, newHeight);
    return result;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if ((_CIImage != nil || _sampleBufferHolder.sampleBuffer != nil) && [self loadContextIfNeeded]) {
        if (self.context.type == SCContextTypeCoreGraphics) {
            CIImage *image = [self renderedCIImage];
            
            if (image != nil) {
                CGRect inRect = rect;
                if (_scaleAndResizeCIImageAutomatically) {
                    inRect = [self scaleAndResizeCIImage:image forRect:rect];
                }
                [_context.CIContext drawImage:image inRect:inRect fromRect:image.extent];
            }
        }
    }
}

- (void)setImageBySampleBuffer:(CMSampleBufferRef)sampleBuffer {
    _sampleBufferHolder.sampleBuffer = sampleBuffer;
    
    [self setNeedsDisplay];
}

+ (CGAffineTransform)preferredCIImageTransformFromUIImage:(UIImage *)image {
    if (image.imageOrientation == UIImageOrientationUp) {
        return CGAffineTransformIdentity;
    }
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    return transform;
}

- (void)setImageByUIImage:(UIImage *)image {
    if (image == nil) {
        self.CIImage = nil;
    } else {
        self.preferredCIImageTransform = [SCImageView preferredCIImageTransformFromUIImage:image];
        self.CIImage = [CIImage imageWithCGImage:image.CGImage];
    }
}

- (void)setCIImage:(CIImage *)CIImage {
    _CIImage = CIImage;
    
    if (CIImage != nil) {
        [self loadContextIfNeeded];
    }
    
    [self setNeedsDisplay];
}


- (void)setContextType:(SCContextType)contextType {
    if (_contextType != contextType) {
        self.context = nil;
        _contextType = contextType;
    }
}

static CGRect CGRectMultiply(CGRect rect, CGFloat contentScale) {
    rect.origin.x *= contentScale;
    rect.origin.y *= contentScale;
    rect.size.width *= contentScale;
    rect.size.height *= contentScale;
    
    return rect;
}

#pragma mark -- GLKViewDelegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (self.pauseRender) {
        return;
    }
    @autoreleasepool {
        rect = CGRectMultiply(rect, self.contentScaleFactor);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        
        CIImage *image = [self renderedCIImage];
        
        if (image != nil) {
            CGRect inRect = rect;
            if (_scaleAndResizeCIImageAutomatically) {
                inRect = [self scaleAndResizeCIImage:image forRect:rect];
            }
            [_context.CIContext drawImage:image inRect:inRect fromRect:image.extent];
        }
    }
}

#if !(TARGET_IPHONE_SIMULATOR)
#pragma mark -- MTKViewDelegate

- (void)drawInMTKView:(nonnull MTKView *)view {
    if (self.pauseRender) {
        return;
    }
    if (self.pipelineState == NULL)
    {
        [self setupPipeline:view];
        [self createTextureCache:view];
        [self setupVertex:view];
    }
    
    // new version--
    //GPU_LOGI(LOG_TAG_GPU_COMMON, @"rendertest___render");
    
    CMSampleBufferRef sampleBuffer = _sampleBufferHolder.sampleBuffer;
    CVMetalTextureRef cvmTexture = NULL;
    if (sampleBuffer == NULL)
    {
        [NSException raise:@"sampleBuffer error " format:@"SampleBuffer is null"];
    }
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, MTLPixelFormatBGRA8Unorm, width, height, 0, &cvmTexture);
    
    id<MTLTexture> sourceTex = CVMetalTextureGetTexture(cvmTexture);
    id<MTLTexture> texture = view.currentDrawable.texture;
    
    // 每次渲染都要单独创建一个CommandBuffer
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    [commandBuffer enqueue];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0, 0, 1.0f);
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        CGFloat width,height;
        if (view.bounds.size.width / view.bounds.size.height < 9 / 16.f &&
            (CGFloat)sourceTex.width / sourceTex.height == 9 / 16.f) { // 支持iPhone X全屏
            height = texture.height;
            width = height * sourceTex.width / sourceTex.height;
            CGFloat x = (texture.width - width) / 2;
            [renderEncoder setViewport:(MTLViewport){x, 0, width, height, -1.0, 1.0 }];
        } else { // 正常画幅
            width = texture.width;
            height = width * sourceTex.height / sourceTex.width;
            CGFloat y = (texture.height - height) / 2;
            [renderEncoder setViewport:(MTLViewport){0, y, width, height, -1.0, 1.0 }];
        }
        [renderEncoder setRenderPipelineState:self.pipelineState];
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:0];
        
        [renderEncoder setFragmentTexture:sourceTex
                                  atIndex:0];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:self.numVertices];
        
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit]; // 提交；
    [commandBuffer waitUntilCompleted];
}

- (void) createTextureCache :(nonnull MTKView *)view {
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, view.device, nil, &_textureCache);
}

// 设置渲染管道
-(void)setupPipeline :(nonnull MTKView *)view {
    NSError* error;
    const char* shaderSource_ = "\n"
    "#include <metal_stdlib>\n"
    
    "using namespace metal;\n"
    "typedef struct\n"
    "{\n"
    "vector_float4 position;\n"
    "vector_float2 textureCoordinate;\n"
    "} LYVertex;\n"
    " typedef struct\n"
    "{\n"
    " float4 clipSpacePosition [[position]];\n"
    
    "  float2 textureCoordinate; \n"
    
    "} RasterizerData;\n"
    
    "vertex RasterizerData \n"
    "VideoVertexShader(uint vertexID [[ vertex_id ]], \n"
    "constant LYVertex *vertexArray [[ buffer(0) ]]) { \n"
    "RasterizerData out;\n"
    "out.clipSpacePosition = vertexArray[vertexID].position;\n"
    "out.textureCoordinate = vertexArray[vertexID].textureCoordinate;\n"
    "return out;\n"
    "}\n"
    
    "fragment float4\n"
    "VideoPixelShader(RasterizerData input [[stage_in]], \n"
    "texture2d<half> colorTexture [[ texture(0) ]]) \n"
    "{\n"
    "constexpr sampler textureSampler (mag_filter::linear,\n"
    " min_filter::linear); \n"
    
    "half4 colorSample = colorTexture.sample(textureSampler, input.textureCoordinate); \n"
    
    "return float4(colorSample);\n"
    "}";
    
    NSString *myNSString = [NSString stringWithUTF8String:shaderSource_];
    id<MTLLibrary> defaultLibrary = [[GlaciesSharedContext getGlobalDevice] newLibraryWithSource:myNSString options:NULL error:&error]; // .metal
    
    if (!defaultLibrary) {
        [NSException raise:@"Failed to compile shaders" format:@"%@", [error localizedDescription]];
    }
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"VideoVertexShader"]; // 顶点shader，vertexShader是函数名
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"VideoPixelShader"]; // 片元shader，samplingShader是函数名
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    self.pipelineState = [view.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                     error:NULL]; // 创建图形渲染管道，耗性能操作不宜频繁调用
    self.commandQueue = [view.device newCommandQueue]; // CommandQueue是渲染指令队列，保证渲染指令有序地提交到GPU
}

- (void)setupVertex :(nonnull MTKView *)view {
    const float scale = 1.0;
    static const LYVertex quadVertices[] =
    {
        { {  scale, -scale, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -scale, -scale, 0.0, 1.0 },  { 0.f, 1.f } },
        { { -scale,  scale, 0.0, 1.0 },  { 0.f, 0.f } },
        
        { {  scale, -scale, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -scale,  scale, 0.0, 1.0 },  { 0.f, 0.f } },
        { {  scale,  scale, 0.0, 1.0 },  { 1.f, 0.f } },
    };
    self.vertices = [view.device newBufferWithBytes:quadVertices
                                             length:sizeof(quadVertices)
                                            options:MTLResourceCPUCacheModeDefaultCache];
    self.numVertices = sizeof(quadVertices) / sizeof(LYVertex);
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    
}
#endif

@end

