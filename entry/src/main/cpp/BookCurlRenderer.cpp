#include "BookCurlRenderer.h"

#include <hilog/log.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdio>

namespace {
constexpr int DOMAIN_ID = 0x0000;
constexpr char TAG_NAME[] = "BookCurl";
constexpr int GRID_COLUMNS = 64;
constexpr int GRID_ROWS = 4;
constexpr float CAMERA_DISTANCE = 2.8f;

const char *VERTEX_SHADER = R"(#version 300 es
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec2 aUV;
layout(location = 2) in vec3 aNormal;
uniform float uAspect;
out vec2 vUV;
out vec3 vNormal;
void main() {
    float perspective = 2.8 / (2.8 - aPosition.z);
    gl_Position = vec4(aPosition.x * perspective, aPosition.y * perspective,
        -aPosition.z * 0.05, 1.0);
    vUV = aUV;
    vNormal = aNormal;
}
)";

const char *FRAGMENT_SHADER = R"(#version 300 es
precision mediump float;
uniform sampler2D uTexture;
uniform int uBackground;
uniform float uFold;
uniform vec3 uPaperColor;
in vec2 vUV;
in vec3 vNormal;
out vec4 fragColor;
void main() {
    vec4 texel = texture(uTexture, vUV);
    if (uBackground == 1) {
        float shadow = 0.32 * exp(-pow((vUV.x - uFold) / 0.10, 2.0));
        fragColor = vec4(texel.rgb * (1.0 - shadow), texel.a);
        return;
    }
    float light = 0.72 + 0.28 * max(dot(normalize(vNormal),
        normalize(vec3(-0.25, 0.2, 1.0))), 0.0);
    if (gl_FrontFacing) {
        fragColor = vec4(texel.rgb * light, texel.a);
    } else {
        vec3 paper = mix(uPaperColor, texel.rgb, 0.10);
        fragColor = vec4(paper * (0.78 + 0.22 * light), texel.a);
    }
}
)";

GLuint CompileShader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) {
        return shader;
    }
    char log[2048] = {0};
    glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
    OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME, "shader compile failed: %{public}s", log);
    glDeleteShader(shader);
    return 0;
}
}

BookCurlRenderer &BookCurlRenderer::Instance()
{
    static BookCurlRenderer renderer;
    return renderer;
}

bool BookCurlRenderer::Initialize(uint64_t surfaceId)
{
    Destroy();
    int result = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window_);
    if (result != 0 || window_ == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME,
            "CreateNativeWindowFromSurfaceId failed: %{public}d", result);
        return false;
    }
    display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display_ == EGL_NO_DISPLAY || !eglInitialize(display_, nullptr, nullptr)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME, "eglInitialize failed");
        return false;
    }
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };
    EGLConfig config = nullptr;
    EGLint configCount = 0;
    if (!eglChooseConfig(display_, attributes, &config, 1, &configCount) || configCount < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME, "eglChooseConfig failed");
        return false;
    }
    surface_ = eglCreateWindowSurface(display_, config,
        reinterpret_cast<EGLNativeWindowType>(window_), nullptr);
    const EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context_ = eglCreateContext(display_, config, EGL_NO_CONTEXT, contextAttributes);
    if (surface_ == EGL_NO_SURFACE || context_ == EGL_NO_CONTEXT || !MakeCurrent()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME, "EGL surface/context creation failed");
        return false;
    }
    if (!BuildProgram()) {
        return false;
    }
    glGenVertexArrays(1, &vao_);
    glBindVertexArray(vao_);
    glGenBuffers(1, &vbo_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glGenTextures(2, textures_);
    for (GLuint texture : textures_) {
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    eglQuerySurface(display_, surface_, EGL_WIDTH, &width_);
    eglQuerySurface(display_, surface_, EGL_HEIGHT, &height_);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    ready_ = true;
    Draw();
    OH_LOG_Print(LOG_APP, LOG_INFO, DOMAIN_ID, TAG_NAME, "native 3D renderer ready");
    return true;
}

void BookCurlRenderer::Destroy()
{
    ready_ = false;
    if (display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (textures_[0] != 0 || textures_[1] != 0) {
            glDeleteTextures(2, textures_);
            textures_[0] = 0;
            textures_[1] = 0;
        }
        if (vbo_ != 0) {
            glDeleteBuffers(1, &vbo_);
            vbo_ = 0;
        }
        if (vao_ != 0) {
            glDeleteVertexArrays(1, &vao_);
            vao_ = 0;
        }
        if (program_ != 0) {
            glDeleteProgram(program_);
            program_ = 0;
        }
        if (context_ != EGL_NO_CONTEXT) {
            eglDestroyContext(display_, context_);
            context_ = EGL_NO_CONTEXT;
        }
        if (surface_ != EGL_NO_SURFACE) {
            eglDestroySurface(display_, surface_);
            surface_ = EGL_NO_SURFACE;
        }
        eglTerminate(display_);
        display_ = EGL_NO_DISPLAY;
    }
    if (window_ != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window_);
        window_ = nullptr;
    }
}

bool BookCurlRenderer::MakeCurrent()
{
    return display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE && context_ != EGL_NO_CONTEXT
        && eglMakeCurrent(display_, surface_, surface_, context_);
}

bool BookCurlRenderer::BuildProgram()
{
    GLuint vertex = CompileShader(GL_VERTEX_SHADER, VERTEX_SHADER);
    GLuint fragment = CompileShader(GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
    if (vertex == 0 || fragment == 0) {
        return false;
    }
    program_ = glCreateProgram();
    glAttachShader(program_, vertex);
    glAttachShader(program_, fragment);
    glLinkProgram(program_);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint linked = 0;
    glGetProgramiv(program_, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        char log[2048] = {0};
        glGetProgramInfoLog(program_, sizeof(log), nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, DOMAIN_ID, TAG_NAME, "program link failed: %{public}s", log);
        return false;
    }
    return true;
}

bool BookCurlRenderer::SetPage(int slot, int width, int height, const uint8_t *pixels, size_t byteLength)
{
    if (!ready_ || slot < 0 || slot > 1 || pixels == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    const size_t required = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    if (byteLength < required || !MakeCurrent()) {
        return false;
    }
    glBindTexture(GL_TEXTURE_2D, textures_[slot]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    const GLenum error = glGetError();
    int minChannel = 255;
    int maxChannel = 0;
    for (size_t i = 0; i + 2 < byteLength; i += 40000) {
        const int value = pixels[i];
        minChannel = std::min(minChannel, value);
        maxChannel = std::max(maxChannel, value);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, DOMAIN_ID, TAG_NAME,
        "upload slot=%{public}d size=%{public}dx%{public}d bytes=%{public}zu glError=%{public}u channel=%{public}d..%{public}d center=%{public}u",
        slot, width, height, byteLength, error, minChannel, maxChannel,
        pixels[static_cast<size_t>(height / 2) * width * 4 + width * 2]);
    Draw();
    return true;
}

void BookCurlRenderer::SetFrame(float progress, int direction, int corner, uint32_t paperColor)
{
    progress_ = std::clamp(progress, 0.0f, 1.0f);
    direction_ = direction < 0 ? -1 : 1;
    corner_ = std::clamp(corner, -1, 1);
    paperColor_[0] = ((paperColor >> 16) & 0xFF) / 255.0f;
    paperColor_[1] = ((paperColor >> 8) & 0xFF) / 255.0f;
    paperColor_[2] = (paperColor & 0xFF) / 255.0f;
    Draw();
}

void BookCurlRenderer::Resize(int width, int height)
{
    width_ = std::max(1, width);
    height_ = std::max(1, height);
    OH_LOG_Print(LOG_APP, LOG_INFO, DOMAIN_ID, TAG_NAME, "viewport=%{public}dx%{public}d", width_, height_);
    Draw();
}

void BookCurlRenderer::Draw()
{
    if (!ready_ || !MakeCurrent()) {
        return;
    }
    glViewport(0, 0, width_, height_);
    glClearColor(paperColor_[0], paperColor_[1], paperColor_[2], 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glUseProgram(program_);
    glBindVertexArray(vao_);
    const GLint samplerLocation = glGetUniformLocation(program_, "uTexture");
    glUniform1i(samplerLocation, 0);
    static bool loggedSampler = false;
    if (!loggedSampler) {
        OH_LOG_Print(LOG_APP, LOG_INFO, DOMAIN_ID, TAG_NAME,
            "sampler=%{public}d textures=%{public}u,%{public}u", samplerLocation, textures_[0], textures_[1]);
        loggedSampler = true;
    }
    glUniform3fv(glGetUniformLocation(program_, "uPaperColor"), 1, paperColor_);
    const float aspect = static_cast<float>(height_) / static_cast<float>(width_);
    glUniform1f(glGetUniformLocation(program_, "uAspect"), aspect);
    const float fold = direction_ > 0 ? 1.0f - progress_ : progress_;
    DrawBackground(fold);
    if (progress_ > 0.0001f) {
        DrawCurledPage(progress_, direction_, corner_);
    }
    eglSwapBuffers(display_, surface_);
}

void BookCurlRenderer::DrawBackground(float fold)
{
    const Vertex vertices[] = {
        {-1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f},
        {1.0f, 1.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f},
        {-1.0f, -1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f},
        {1.0f, -1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 1.0f}
    };
    glUniform1i(glGetUniformLocation(program_, "uBackground"), 1);
    glUniform1f(glGetUniformLocation(program_, "uFold"), fold);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, progress_ <= 0.0001f ? textures_[0] : textures_[1]);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, x)));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, u)));
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, nx)));
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    static int centerLogCount = 0;
    if (centerLogCount < 5) {
        uint8_t center[4] = {0, 0, 0, 0};
        glReadPixels(width_ / 2, height_ / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, center);
        OH_LOG_Print(LOG_APP, LOG_INFO, DOMAIN_ID, TAG_NAME,
            "draw center rgba=%{public}u,%{public}u,%{public}u,%{public}u error=%{public}u",
            center[0], center[1], center[2], center[3], glGetError());
        centerLogCount += 1;
    }
}

void BookCurlRenderer::DrawCurledPage(float progress, int direction, int corner)
{
    std::vector<Vertex> vertices;
    std::vector<uint16_t> indices;
    vertices.reserve((GRID_COLUMNS + 1) * (GRID_ROWS + 1));
    indices.reserve(GRID_COLUMNS * GRID_ROWS * 6);
    const float fold = direction > 0 ? 1.0f - progress : progress;
    for (int row = 0; row <= GRID_ROWS; ++row) {
        const float v = static_cast<float>(row) / GRID_ROWS;
        for (int column = 0; column <= GRID_COLUMNS; ++column) {
            const float u = static_cast<float>(column) / GRID_COLUMNS;
            const bool flipped = direction > 0 ? u > fold : u < fold;
            float x = u;
            float z = 0.0f;
            float nx = 0.0f;
            float nz = 1.0f;
            if (flipped && progress > 0.0001f) {
                const float t = direction > 0 ? (u - fold) / progress : (fold - u) / progress;
                float angle = std::clamp(t, 0.0f, 1.0f) * static_cast<float>(M_PI_2);
                if (corner > 0) {
                    angle *= 0.65f + 0.5f * v;
                } else if (corner < 0) {
                    angle *= 1.15f - 0.5f * v;
                }
                const float sine = std::sin(angle);
                const float cosine = std::cos(angle);
                x = direction > 0 ? fold + progress * (cosine - 1.0f)
                                  : fold + progress * (1.0f - cosine);
                z = progress * sine;
                nx = direction > 0 ? -sine : sine;
                nz = cosine;
            }
            vertices.push_back({2.0f * x - 1.0f, 1.0f - 2.0f * v,
                z, u, v, nx, 0.0f, nz});
        }
    }
    for (int row = 0; row < GRID_ROWS; ++row) {
        for (int column = 0; column < GRID_COLUMNS; ++column) {
            const uint16_t a = row * (GRID_COLUMNS + 1) + column;
            const uint16_t b = a + 1;
            const uint16_t c = a + GRID_COLUMNS + 1;
            const uint16_t d = c + 1;
            indices.insert(indices.end(), {a, c, b, b, c, d});
        }
    }
    glUniform1i(glGetUniformLocation(program_, "uBackground"), 0);
    glUniform1f(glGetUniformLocation(program_, "uFold"), fold);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textures_[0]);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(Vertex), vertices.data(), GL_DYNAMIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, x)));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, u)));
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
        reinterpret_cast<void *>(offsetof(Vertex, nx)));
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    glDrawElements(GL_TRIANGLES, static_cast<GLsizei>(indices.size()), GL_UNSIGNED_SHORT, indices.data());
}
