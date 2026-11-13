#ifndef BOOK_CURL_RENDERER_H
#define BOOK_CURL_RENDERER_H

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#include <cstddef>
#include <cstdint>
#include <vector>

class BookCurlRenderer {
public:
    static BookCurlRenderer &Instance();

    bool Initialize(uint64_t surfaceId);
    void Destroy();
    bool SetPage(int slot, int width, int height, const uint8_t *pixels, size_t byteLength);
    void SetFrame(float progress, int direction, int corner, uint32_t paperColor);
    void Resize(int width, int height);

private:
    struct Vertex {
        float x;
        float y;
        float z;
        float u;
        float v;
        float nx;
        float ny;
        float nz;
    };

    bool MakeCurrent();
    bool BuildProgram();
    void Draw();
    void DrawBackground(float fold);
    void DrawCurledPage(float progress, int direction, int corner);

    OHNativeWindow *window_ = nullptr;
    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLSurface surface_ = EGL_NO_SURFACE;
    EGLContext context_ = EGL_NO_CONTEXT;
    GLuint program_ = 0;
    GLuint vao_ = 0;
    GLuint vbo_ = 0;
    GLuint textures_[2] = {0, 0};
    int width_ = 1;
    int height_ = 1;
    bool ready_ = false;
    float progress_ = 0;
    int direction_ = 1;
    int corner_ = 0;
    float paperColor_[3] = {0.98f, 0.97f, 0.95f};
};

#endif
