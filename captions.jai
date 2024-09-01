
#import "Basic";
#import "File";
#import "Windows";
#import "stb_image_write";

GetWindowTextA :: (hwnd: HWND, lpstring: LPSTR, max: s32) -> s32 #foreign user32;
CreateDIBSection :: (hdc: HDC, bmi: *BITMAPINFO, usage: u32, ppvBits: **void, hSection: HANDLE, offset: DWORD) -> HBITMAP #foreign gdi;
c_free :: (memory: *void) #foreign crt "free";

user32 :: #system_library "user32"; 
gdi :: #system_library "Gdi32";
crt :: #system_library "msvcrt";

main :: () {
    sleep_milliseconds(1000);

    hwnd := GetForegroundWindow();

    title: [256] u8;
    GetWindowTextA(hwnd, title.data, title.count);

    title_string: string;
    title_string.data = title.data;
    title_string.count = title.count;

    print("Capturing %\n", title_string);

    capture_window(hwnd);
}

capture_window :: (hwnd: HWND) {
    bytes, width, height := get_window_bytes(hwnd);
    defer free(bytes);

    for i: 0..width * height {
        bytes[i * 4 + 3] = 255;
    }

    stbi_write_png("test.png", cast(s32) width, cast(s32) height, 4, bytes, cast(s32) (4 * width));
}

get_window_bytes :: (hwnd: HWND) -> *u8, int, int {
    hdcWindow := GetDC(hwnd);
    hdcMemDC := CreateCompatibleDC(hdcWindow);

    if (!hdcMemDC) {
        print("CreateCompatibleDC failed: %\n", GetLastError());
        return null, 0, 0;
    }

    rcClient: RECT;
    GetClientRect(hwnd, *rcClient);

    width := rcClient.right - rcClient.left;
    height := rcClient.bottom - rcClient.top;

    hbmScreen := CreateCompatibleBitmap(hdcWindow, width, height);

    SelectObject(hdcMemDC, hbmScreen);

    // BitBlt(hdcMemDC, 0, 0, width, height, hdcWindow, 0, 0, ROP.SRCCOPY);
    if !PrintWindow(hwnd, hdcMemDC, PW_CLIENTONLY) {
        print("PrintWindow failed: %\n", GetLastError());
        DeleteDC(hdcMemDC);
        ReleaseDC(hwnd, hdcWindow);
        return null, 0, 0;
    }

    bmpScreen: BITMAP;
    GetObjectA(hbmScreen, size_of(BITMAP), *bmpScreen);

    bi: BITMAPINFOHEADER;
    bi.biSize = size_of(BITMAPINFOHEADER);
    bi.biWidth = width;
    bi.biHeight = height * -1;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;
    bi.biSizeImage = 0;
    bi.biXPelsPerMeter = 0;
    bi.biYPelsPerMeter = 0;
    bi.biClrUsed = 0;
    bi.biClrImportant = 0;

    pPixels := alloc(4 * width * height);

    GetDIBits(hdcMemDC, hbmScreen, 0, cast(u32) height, pPixels, cast(*BITMAPINFO) *bi, DIB_RGB_COLORS);

    DeleteObject(hbmScreen);
    DeleteDC(hdcMemDC);
    ReleaseDC(hwnd, hdcWindow);

    return pPixels, cast(int) width, cast(int) height;
}


// capture_window :: (hwnd: HWND) {
//     rect: RECT;
//     GetWindowRect(hwnd, *rect);
//     width := rect.right - rect.left;
//     height := rect.bottom - rect.top;

//     hdc_window := GetDC(hwnd);
//     hdc_mem_dc := CreateCompatibleDC(hdc_window);
//     h_bitmap := CreateCompatibleBitmap(hdc_window, width, height);
//     old_bitmap := SelectObject(hdc_mem_dc, h_bitmap);

//     BitBlt(hdc_mem_dc, 0, 0, width, height, hdc_window, 0, 0, ROP.SRCCOPY);

//     bitmap_w: s32;
//     bitmap_h: s32;
//     bitmap_comp: s32;
//     bits := get_bitmap_bits(h_bitmap, *bitmap_w, *bitmap_h, *bitmap_comp);
//     defer free(bits);
//     stbi_write_png("test.png", bitmap_w, bitmap_h, bitmap_comp, bits, bitmap_comp * bitmap_w);

//     SelectObject(hdc_mem_dc, old_bitmap);
//     DeleteObject(h_bitmap);
//     DeleteDC(hdc_mem_dc);
//     ReleaseDC(hwnd, hdc_window);
// }

get_bitmap_bits :: (hBitmap: HBITMAP, width: *s32, height: *s32, comp: *s32) -> *u8 {
    bmp: BITMAP;
    GetObjectA(hBitmap, size_of(BITMAP), *bmp);

    width.* = cast(s32) bmp.bmWidth;
    height.* = cast(s32) bmp.bmHeight;
    bytesPerPixel := bmp.bmBitsPixel / 8;
    comp.* = cast(s32) bytesPerPixel;

    imageSize := bmp.bmWidth * bmp.bmHeight * bytesPerPixel;

    bits := cast(*u8) alloc(imageSize);

    hdc := GetDC(null);
    bmi: BITMAPINFO;
    memset(*bmi, 0, size_of(BITMAPINFO));
    bmi.bmiHeader.biSize = size_of(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = cast(s32) bmp.bmWidth;
    bmi.bmiHeader.biHeight = -(cast(s32) bmp.bmHeight); // top-down DIB
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = bmp.bmBitsPixel;
    bmi.bmiHeader.biCompression = BI_RGB;

    GetDIBits(hdc, hBitmap, 0, bmp.bmHeight, bits, *bmi, DIB_RGB_COLORS);
    ReleaseDC(null, hdc);

    return bits;
}
