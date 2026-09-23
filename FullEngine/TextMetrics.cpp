#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <cmath>

// SVG layout uses CoreText on macOS, rather than Windows Forms/GDI text measurement.
extern "C" int statsdirect_measure_text(const char* utf8, const char* family, double pixels, int style, double* width, double* height) {
    if (!utf8 || !width || !height || !std::isfinite(pixels) || pixels <= 0) return 1;
    CFStringRef text = CFStringCreateWithCString(nullptr, utf8, kCFStringEncodingUTF8);
    CFStringRef name = CFStringCreateWithCString(nullptr, family ? family : "Arial", kCFStringEncodingUTF8);
    CTFontRef font = CTFontCreateWithName(name ? name : CFSTR("Arial"), pixels, nullptr);
    if (name) CFRelease(name);
    if (!text || !font) { if (text) CFRelease(text); if (font) CFRelease(font); return 2; }
    CTFontSymbolicTraits traits = ((style & 1) ? kCTFontBoldTrait : 0) | ((style & 2) ? kCTFontItalicTrait : 0);
    if (traits) {
        CTFontRef styled = CTFontCreateCopyWithSymbolicTraits(font, pixels, nullptr, traits, traits);
        if (styled) { CFRelease(font); font = styled; }
    }
    const void* keys[] = { kCTFontAttributeName }; const void* values[] = { font };
    CFDictionaryRef attributes = CFDictionaryCreate(nullptr, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attributed = CFAttributedStringCreate(nullptr, text, attributes);
    CTLineRef line = CTLineCreateWithAttributedString(attributed);
    CGFloat ascent = 0, descent = 0, leading = 0;
    *width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    *height = std::ceil(ascent + descent + leading);
    CFRelease(line); CFRelease(attributed); CFRelease(attributes); CFRelease(font); CFRelease(text);
    return 0;
}
