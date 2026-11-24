#import "DocxHelper.h"
#import <ImageIO/ImageIO.h>
#import <zlib.h>

static void zero_mem(void *ptr, size_t len) {
    volatile uint8_t *p = (volatile uint8_t *)ptr;
    while (len--) {
        *p++ = 0;
    }
}

@interface DocxRelsParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *imageRels;
@end

@implementation DocxRelsParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageRels = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"Relationship"]) {
        NSString *rId = attributeDict[@"Id"];
        NSString *type = attributeDict[@"Type"];
        NSString *target = attributeDict[@"Target"];
        if (rId && target && [type rangeOfString:@"image" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSString *norm = target;
            if ([norm hasPrefix:@"/"]) {
                norm = [norm substringFromIndex:1];
            } else if ([norm hasPrefix:@"./"]) {
                norm = [@"word/" stringByAppendingString:[norm substringFromIndex:2]];
            } else if (![norm hasPrefix:@"word/"]) {
                norm = [@"word/" stringByAppendingString:norm];
            }
            self.imageRels[rId] = norm;
        }
    }
}

@end

@interface DocxXMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *zipEntries;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *imageRels;
@property (nonatomic, strong) NSMutableAttributedString *result;
@property (nonatomic, strong) NSMutableString *currentText;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIFont *> *fontCache;
@property (nonatomic, assign) BOOL inParagraph;
@property (nonatomic, assign) BOOL inRun;
@property (nonatomic, assign) BOOL inText;
@property (nonatomic, assign) BOOL isBold;
@property (nonatomic, assign) BOOL isItalic;
@property (nonatomic, assign) BOOL isUnderline;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, copy) NSString *requestedFontFamily;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, assign) NSTextAlignment alignment;
@property (nonatomic, assign) BOOL isRTL;
@property (nonatomic, assign) BOOL hasAppendedFirstParagraph;
@property (nonatomic, assign) CGSize currentDrawingSize;
@property (nonatomic, assign) BOOL inTable;
@property (nonatomic, assign) BOOL inTableRow;
@property (nonatomic, assign) BOOL inTableCell;
@property (nonatomic, assign) NSInteger tableRowIndex;
@property (nonatomic, assign) BOOL isFirstCellInRow;
@property (nonatomic, assign) BOOL isFirstParagraphInCell;
@end

@implementation DocxXMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _result = [[NSMutableAttributedString alloc] init];
        _currentText = [[NSMutableString alloc] init];
        _fontCache = [NSMutableDictionary dictionary];
        _fontSize = 18.0;
        _textColor = [UIColor blackColor];
        _alignment = NSTextAlignmentRight;
        _isRTL = YES;
        _currentDrawingSize = CGSizeZero;
    }
    return self;
}

- (UIImage *)fastDownsampledImageFromData:(NSData *)data maxDimension:(CGFloat)maxDim {
    if (!data || data.length == 0) return nil;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return [UIImage imageWithData:data];

    NSDictionary *opts = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @((NSInteger)maxDim),
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES
    };
    CGImageRef cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);

    if (!cgImg) return [UIImage imageWithData:data];
    UIImage *img = [UIImage imageWithCGImage:cgImg];
    CGImageRelease(cgImg);
    return img;
}

- (UIColor *)colorFromHexString:(NSString *)hex {
    if (!hex || hex.length != 6 || [hex isEqualToString:@"auto"]) return [UIColor blackColor];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb]) return [UIColor blackColor];
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

- (UIFont *)currentFont {
    BOOL effectiveBold = self.isBold || (self.inTableRow && self.tableRowIndex == 0);
    NSString *baseFamily = @"Arial";
    if (self.requestedFontFamily.length > 0) {
        NSString *low = self.requestedFontFamily.lowercaseString;
        if ([low rangeOfString:@"geeza"].location != NSNotFound) baseFamily = @"GeezaPro";
        else if ([low rangeOfString:@"damascus"].location != NSNotFound) baseFamily = @"Damascus";
        else if ([low rangeOfString:@"baghdad"].location != NSNotFound) baseFamily = @"Baghdad";
    }

    NSString *fontName = @"ArialMT";
    if ([baseFamily isEqualToString:@"GeezaPro"]) {
        fontName = effectiveBold ? @"GeezaPro-Bold" : @"GeezaPro";
    } else if ([baseFamily isEqualToString:@"Damascus"]) {
        fontName = effectiveBold ? @"DamascusBold" : @"Damascus";
    } else if ([baseFamily isEqualToString:@"Baghdad"]) {
        fontName = @"Baghdad";
    } else {
        if (effectiveBold && self.isItalic) fontName = @"Arial-BoldItalicMT";
        else if (effectiveBold) fontName = @"Arial-BoldMT";
        else if (self.isItalic) fontName = @"Arial-ItalicMT";
    }

    NSString *key = [NSString stringWithFormat:@"%@_%ld", fontName, (long)(self.fontSize * 10.0)];
    UIFont *cached = self.fontCache[key];
    if (cached) return cached;

    UIFont *font = [UIFont fontWithName:fontName size:self.fontSize];
    if (!font) {
        font = effectiveBold ? [UIFont boldSystemFontOfSize:self.fontSize] : [UIFont systemFontOfSize:self.fontSize];
    }
    if (font) self.fontCache[key] = font;
    return font;
}

- (NSDictionary *)currentAttributes {
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = self.alignment;
    para.baseWritingDirection = self.isRTL ? NSWritingDirectionRightToLeft : NSWritingDirectionLeftToRight;
    if (self.inTableRow) {
        para.lineSpacing = 4.0;
    }

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFontAttributeName] = [self currentFont];
    attrs[NSParagraphStyleAttributeName] = para;
    attrs[NSForegroundColorAttributeName] = self.textColor ?: [UIColor blackColor];
    if (self.inTableRow && self.tableRowIndex == 0) {
        attrs[NSBackgroundColorAttributeName] = [UIColor colorWithRed:0.91 green:0.94 blue:0.98 alpha:1.0];
    }
    if (self.isUnderline) {
        attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    return attrs;
}

- (void)flushRunText {
    if (self.currentText.length > 0) {
        NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:[self.currentText copy] attributes:[self currentAttributes]];
        [self.result appendAttributedString:chunk];
        [self.currentText setString:@""];
    }
}

- (void)appendImageForRelID:(NSString *)relID {
    if (!relID) return;
    NSString *mediaPath = self.imageRels[relID];
    if (!mediaPath) return;
    NSData *imgData = self.zipEntries[mediaPath];
    if (!imgData) return;

    UIImage *img = [self fastDownsampledImageFromData:imgData maxDimension:768.0];
    if (!img) return;

    [self flushRunText];

    CGFloat maxDisplayWidth = 460.0;
    CGFloat targetW = img.size.width;
    CGFloat targetH = img.size.height;

    if (self.currentDrawingSize.width > 0 && self.currentDrawingSize.height > 0) {
        targetW = self.currentDrawingSize.width;
        targetH = self.currentDrawingSize.height;
    }
    if (targetW > maxDisplayWidth && targetW > 0) {
        CGFloat ratio = maxDisplayWidth / targetW;
        targetW = maxDisplayWidth;
        targetH = (CGFloat)(NSInteger)(targetH * ratio + 0.5);
    }

    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = img;
    attachment.bounds = CGRectMake(0, 0, targetW, targetH);

    NSMutableAttributedString *imgAttr = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
    [imgAttr addAttributes:[self currentAttributes] range:NSMakeRange(0, imgAttr.length)];
    [self.result appendAttributedString:imgAttr];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"w:tbl"]) {
        self.inTable = YES;
        self.tableRowIndex = 0;
        if (self.hasAppendedFirstParagraph) {
            NSAttributedString *nl = [[NSAttributedString alloc] initWithString:@"\n" attributes:[self currentAttributes]];
            [self.result appendAttributedString:nl];
        }
        self.hasAppendedFirstParagraph = YES;
    } else if ([elementName isEqualToString:@"w:tr"] && self.inTable) {
        self.inTableRow = YES;
        self.isFirstCellInRow = YES;
        self.alignment = NSTextAlignmentRight;
        self.isRTL = YES;
    } else if ([elementName isEqualToString:@"w:tc"] && self.inTableRow) {
        self.inTableCell = YES;
        self.isFirstParagraphInCell = YES;
        if (!self.isFirstCellInRow) {
            NSMutableDictionary *sepAttrs = [[self currentAttributes] mutableCopy];
            sepAttrs[NSForegroundColorAttributeName] = [UIColor colorWithRed:0.25 green:0.45 blue:0.75 alpha:1.0];
            NSAttributedString *sep = [[NSAttributedString alloc] initWithString:@" │ " attributes:sepAttrs];
            [self.result appendAttributedString:sep];
        }
        self.isFirstCellInRow = NO;
    } else if ([elementName isEqualToString:@"w:p"]) {
        if (self.inTableCell) {
            if (!self.isFirstParagraphInCell) {
                NSAttributedString *sp = [[NSAttributedString alloc] initWithString:@" " attributes:[self currentAttributes]];
                [self.result appendAttributedString:sp];
            }
            self.isFirstParagraphInCell = NO;
        } else {
            if (self.hasAppendedFirstParagraph) {
                NSAttributedString *nl = [[NSAttributedString alloc] initWithString:@"\n" attributes:[self currentAttributes]];
                [self.result appendAttributedString:nl];
            }
            self.hasAppendedFirstParagraph = YES;
            self.alignment = NSTextAlignmentRight;
            self.isRTL = YES;
        }
        self.inParagraph = YES;
    } else if ([elementName isEqualToString:@"w:bidi"] && self.inParagraph && !self.inTableCell) {
        NSString *val = attributeDict[@"w:val"];
        self.isRTL = !(val && ([val isEqualToString:@"0"] || [val isEqualToString:@"false"]));
    } else if ([elementName isEqualToString:@"w:jc"] && self.inParagraph && !self.inTableCell) {
        NSString *val = attributeDict[@"w:val"];
        if ([val isEqualToString:@"left"] || [val isEqualToString:@"start"]) {
            self.alignment = NSTextAlignmentLeft;
        } else if ([val isEqualToString:@"center"]) {
            self.alignment = NSTextAlignmentCenter;
        } else if ([val isEqualToString:@"both"] || [val isEqualToString:@"distribute"]) {
            self.alignment = NSTextAlignmentJustified;
        } else {
            self.alignment = NSTextAlignmentRight;
        }
    } else if ([elementName isEqualToString:@"w:r"]) {
        self.inRun = YES;
        self.isBold = NO;
        self.isItalic = NO;
        self.isUnderline = NO;
        self.fontSize = 18.0;
        self.requestedFontFamily = nil;
        self.textColor = [UIColor blackColor];
    } else if ([elementName isEqualToString:@"w:rFonts"] && self.inRun) {
        self.requestedFontFamily = attributeDict[@"w:cs"] ?: attributeDict[@"w:ascii"] ?: attributeDict[@"w:hAnsi"];
    } else if ([elementName isEqualToString:@"w:color"] && self.inRun) {
        self.textColor = [self colorFromHexString:attributeDict[@"w:val"]];
    } else if ([elementName isEqualToString:@"w:b"] && self.inRun) {
        NSString *val = attributeDict[@"w:val"];
        self.isBold = !(val && ([val isEqualToString:@"0"] || [val isEqualToString:@"false"]));
    } else if ([elementName isEqualToString:@"w:i"] && self.inRun) {
        NSString *val = attributeDict[@"w:val"];
        self.isItalic = !(val && ([val isEqualToString:@"0"] || [val isEqualToString:@"false"]));
    } else if ([elementName isEqualToString:@"w:u"] && self.inRun) {
        NSString *val = attributeDict[@"w:val"];
        self.isUnderline = !(val && [val isEqualToString:@"none"]);
    } else if ([elementName isEqualToString:@"w:sz"] && self.inRun) {
        NSString *val = attributeDict[@"w:val"];
        if (val.doubleValue > 0) {
            self.fontSize = val.doubleValue / 2.0;
        }
    } else if ([elementName isEqualToString:@"w:drawing"]) {
        self.currentDrawingSize = CGSizeZero;
    } else if ([elementName isEqualToString:@"wp:extent"]) {
        double cx = [attributeDict[@"cx"] doubleValue];
        double cy = [attributeDict[@"cy"] doubleValue];
        if (cx > 0 && cy > 0) {
            self.currentDrawingSize = CGSizeMake(cx / 12700.0, cy / 12700.0);
        }
    } else if ([elementName isEqualToString:@"a:blip"]) {
        NSString *embedId = attributeDict[@"r:embed"] ?: attributeDict[@"r:link"];
        [self appendImageForRelID:embedId];
    } else if ([elementName isEqualToString:@"v:imagedata"]) {
        NSString *relId = attributeDict[@"r:id"] ?: attributeDict[@"o:relid"];
        [self appendImageForRelID:relId];
    } else if ([elementName isEqualToString:@"w:t"]) {
        self.inText = YES;
    } else if ([elementName isEqualToString:@"w:br"]) {
        [self.currentText appendString:@"\n"];
    } else if ([elementName isEqualToString:@"w:tab"]) {
        [self.currentText appendString:@"\t"];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.inText) {
        [self.currentText appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"w:t"]) {
        self.inText = NO;
    } else if ([elementName isEqualToString:@"w:drawing"]) {
        self.currentDrawingSize = CGSizeZero;
    } else if ([elementName isEqualToString:@"w:r"]) {
        [self flushRunText];
        self.inRun = NO;
    } else if ([elementName isEqualToString:@"w:p"]) {
        [self flushRunText];
        self.inParagraph = NO;
    } else if ([elementName isEqualToString:@"w:tc"]) {
        [self flushRunText];
        self.inTableCell = NO;
    } else if ([elementName isEqualToString:@"w:tr"]) {
        [self flushRunText];
        NSAttributedString *nl = [[NSAttributedString alloc] initWithString:@"\n" attributes:[self currentAttributes]];
        [self.result appendAttributedString:nl];
        self.tableRowIndex++;
        self.inTableRow = NO;
    } else if ([elementName isEqualToString:@"w:tbl"]) {
        self.inTable = NO;
        self.tableRowIndex = 0;
    }
}

@end

@implementation DocxHelper

+ (uint16_t)readUInt16:(const uint8_t *)p {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

+ (uint32_t)readUInt32:(const uint8_t *)p {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

+ (void)appendUInt16:(uint16_t)v toData:(NSMutableData *)d {
    uint8_t b[2] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF) };
    [d appendBytes:b length:2];
}

+ (void)appendUInt32:(uint32_t)v toData:(NSMutableData *)d {
    uint8_t b[4] = {
        (uint8_t)(v & 0xFF),
        (uint8_t)((v >> 8) & 0xFF),
        (uint8_t)((v >> 16) & 0xFF),
        (uint8_t)((v >> 24) & 0xFF)
    };
    [d appendBytes:b length:4];
}

+ (NSDictionary<NSString *, NSData *> *)extractZipEntriesFromData:(NSData *)zipData {
    const uint8_t *bytes = (const uint8_t *)zipData.bytes;
    NSUInteger len = zipData.length;
    if (len < 22) return nil;

    NSInteger eocdOffset = -1;
    NSInteger minSearch = (len > 65557) ? (NSInteger)(len - 65557) : 0;
    for (NSInteger i = (NSInteger)len - 22; i >= minSearch; i--) {
        if ([self readUInt32:bytes + i] == 0x06054b50) {
            eocdOffset = i;
            break;
        }
    }
    if (eocdOffset < 0) return nil;

    uint16_t totalEntries = [self readUInt16:bytes + eocdOffset + 10];
    uint32_t cdOffset = [self readUInt32:bytes + eocdOffset + 16];
    NSUInteger pos = cdOffset;

    NSMutableDictionary<NSString *, NSData *> *entries = [NSMutableDictionary dictionary];

    for (uint16_t idx = 0; idx < totalEntries; idx++) {
        if (pos + 46 > len) break;
        if ([self readUInt32:bytes + pos] != 0x02014b50) break;

        uint16_t method = [self readUInt16:bytes + pos + 10];
        uint32_t compSize = [self readUInt32:bytes + pos + 20];
        uint32_t uncompSize = [self readUInt32:bytes + pos + 24];
        uint16_t nameLen = [self readUInt16:bytes + pos + 28];
        uint16_t extraLen = [self readUInt16:bytes + pos + 30];
        uint16_t commentLen = [self readUInt16:bytes + pos + 32];
        uint32_t localOffset = [self readUInt32:bytes + pos + 42];

        if (pos + 46 + nameLen > len) break;
        NSString *entryName = [[NSString alloc] initWithBytes:bytes + pos + 46 length:nameLen encoding:NSUTF8StringEncoding];

        if (entryName && localOffset + 30 <= len && [self readUInt32:bytes + localOffset] == 0x04034b50) {
            uint16_t localNameLen = [self readUInt16:bytes + localOffset + 26];
            uint16_t localExtraLen = [self readUInt16:bytes + localOffset + 28];
            NSUInteger dataStart = localOffset + 30 + localNameLen + localExtraLen;
            if (dataStart + compSize <= len) {
                if (uncompSize == 0) {
                    entries[entryName] = [NSData data];
                } else if (method == 0) {
                    entries[entryName] = [zipData subdataWithRange:NSMakeRange(dataStart, uncompSize)];
                } else if (method == 8) {
                    NSMutableData *outData = [NSMutableData dataWithLength:uncompSize];
                    z_stream strm;
                    zero_mem(&strm, sizeof(strm));
                    strm.next_in = (Bytef *)(bytes + dataStart);
                    strm.avail_in = (uInt)compSize;
                    strm.next_out = (Bytef *)outData.mutableBytes;
                    strm.avail_out = (uInt)uncompSize;

                    if (inflateInit2(&strm, -MAX_WBITS) == Z_OK) {
                        int ret = inflate(&strm, Z_FINISH);
                        inflateEnd(&strm);
                        if (ret == Z_STREAM_END || ret == Z_OK) {
                            entries[entryName] = outData;
                        }
                    }
                }
            }
        }
        pos += 46 + nameLen + extraLen + commentLen;
    }
    return entries;
}

+ (NSAttributedString *)attributedStringFromDocxURL:(NSURL *)url error:(NSError **)error {
    NSData *zipData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!zipData) return nil;

    NSDictionary<NSString *, NSData *> *entries = [self extractZipEntriesFromData:zipData];
    NSData *xmlData = entries[@"word/document.xml"];
    if (!xmlData) {
        if (error) {
            *error = [NSError errorWithDomain:@"ArabicOfficeDocx" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"تعذر قراءة محتوى ملف Word (.docx)"}];
        }
        return nil;
    }

    NSDictionary<NSString *, NSString *> *imageRels = @{};
    NSData *relsData = entries[@"word/_rels/document.xml.rels"];
    if (relsData) {
        DocxRelsParserDelegate *relsDelegate = [[DocxRelsParserDelegate alloc] init];
        NSXMLParser *relsParser = [[NSXMLParser alloc] initWithData:relsData];
        relsParser.delegate = relsDelegate;
        [relsParser parse];
        imageRels = relsDelegate.imageRels;
    }

    DocxXMLParserDelegate *delegate = [[DocxXMLParserDelegate alloc] init];
    delegate.zipEntries = entries;
    delegate.imageRels = imageRels;

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:xmlData];
    parser.delegate = delegate;
    if (![parser parse]) {
        if (error) *error = parser.parserError;
        return nil;
    }
    return delegate.result;
}

+ (NSString *)escapeXML:(NSString *)str {
    NSMutableString *s = [str mutableCopy];
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"'" withString:@"&apos;" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

+ (NSString *)hexStringFromColor:(UIColor *)color {
    if (!color) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        NSInteger ri = (NSInteger)(r * 255.0 + 0.5);
        NSInteger gi = (NSInteger)(g * 255.0 + 0.5);
        NSInteger bi = (NSInteger)(b * 255.0 + 0.5);
        if (ri == 0 && gi == 0 && bi == 0) return nil;
        return [NSString stringWithFormat:@"%02lX%02lX%02lX", (long)ri, (long)gi, (long)bi];
    }
    return nil;
}

+ (BOOL)isTableLine:(NSString *)line {
    if (line.length == 0) return NO;
    return ([line rangeOfString:@"│"].location != NSNotFound || [line rangeOfString:@"|"].location != NSNotFound);
}

+ (void)appendFormattedRunsFromAttributedString:(NSAttributedString *)attrStr inRange:(NSRange)range isRTL:(BOOL)isRTL trimPadding:(BOOL)trimPad toXML:(NSMutableString *)xml {
    NSString *fullText = attrStr.string ?: @"";
    if (range.length == 0 || NSMaxRange(range) > fullText.length) return;

    __block NSUInteger currentLoc = range.location;
    NSUInteger endLoc = NSMaxRange(range);

    [attrStr enumerateAttributesInRange:range options:0 usingBlock:^(NSDictionary<NSString *,id> *attrs, NSRange subRange, BOOL *stop) {
        if (attrs[NSAttachmentAttributeName]) return;
        NSString *sub = [[fullText substringWithRange:subRange] stringByReplacingOccurrencesOfString:@"\uFFFC" withString:@""];
        if (trimPad) {
            if (subRange.location == range.location) {
                while ([sub hasPrefix:@" "]) sub = [sub substringFromIndex:1];
            }
            if (NSMaxRange(subRange) == endLoc) {
                while ([sub hasSuffix:@" "]) sub = [sub substringToIndex:sub.length - 1];
            }
        }
        currentLoc = NSMaxRange(subRange);
        if (sub.length == 0) return;

        UIFont *font = attrs[NSFontAttributeName];
        NSNumber *underline = attrs[NSUnderlineStyleAttributeName];
        UIColor *fgColor = attrs[NSForegroundColorAttributeName];

        BOOL bold = NO;
        BOOL italic = NO;
        CGFloat size = 18.0;
        NSString *exportFont = @"Arial";
        if (font) {
            size = font.pointSize;
            NSString *fn = font.fontName;
            if ([fn rangeOfString:@"Geeza" options:NSCaseInsensitiveSearch].location != NSNotFound) exportFont = @"Geeza Pro";
            else if ([fn rangeOfString:@"Damascus" options:NSCaseInsensitiveSearch].location != NSNotFound) exportFont = @"Damascus";
            else if ([fn rangeOfString:@"Baghdad" options:NSCaseInsensitiveSearch].location != NSNotFound) exportFont = @"Baghdad";

            UIFontDescriptorSymbolicTraits traits = font.fontDescriptor.symbolicTraits;
            bold = (traits & UIFontDescriptorTraitBold) != 0 || ([fn rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
            italic = (traits & UIFontDescriptorTraitItalic) != 0 || ([fn rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
        }
        BOOL under = (underline && underline.integerValue != NSUnderlineStyleNone);
        NSInteger halfPts = (NSInteger)(size * 2.0 + 0.5);
        NSString *hexColor = [self hexStringFromColor:fgColor];

        [xml appendString:@"    <w:r>\n      <w:rPr>"];
        [xml appendFormat:@"<w:rFonts w:ascii=\"%@\" w:hAnsi=\"%@\" w:cs=\"%@\"/>", exportFont, exportFont, exportFont];
        if (isRTL) [xml appendString:@"<w:rtl/>"];
        if (bold) [xml appendString:@"<w:b/>"];
        if (italic) [xml appendString:@"<w:i/>"];
        if (under) [xml appendString:@"<w:u w:val=\"single\"/>"];
        if (hexColor) [xml appendFormat:@"<w:color w:val=\"%@\"/>", hexColor];
        [xml appendFormat:@"<w:sz w:val=\"%ld\"/><w:szCs w:val=\"%ld\"/>", (long)halfPts, (long)halfPts];
        [xml appendString:@"</w:rPr>\n"];
        [xml appendFormat:@"      <w:t xml:space=\"preserve\">%@</w:t>\n    </w:r>\n", [self escapeXML:sub]];
    }];
}

+ (void)appendTableFromAttributedString:(NSAttributedString *)attrStr rowRanges:(NSArray<NSValue *> *)rowRanges toXML:(NSMutableString *)xml {
    if (rowRanges.count == 0) return;
    NSString *fullText = attrStr.string ?: @"";

    NSMutableArray<NSArray<NSValue *> *> *allRowsCells = [NSMutableArray arrayWithCapacity:rowRanges.count];
    NSInteger maxCols = 1;

    for (NSValue *val in rowRanges) {
        NSRange rowRange = [val rangeValue];
        NSString *rowStr = [fullText substringWithRange:rowRange];
        NSString *sep = ([rowStr rangeOfString:@"│"].location != NSNotFound) ? @"│" : @"|";

        NSMutableArray<NSValue *> *cellRanges = [NSMutableArray array];
        NSUInteger searchStart = 0;
        while (searchStart <= rowStr.length) {
            NSRange found = [rowStr rangeOfString:sep options:0 range:NSMakeRange(searchStart, rowStr.length - searchStart)];
            if (found.location == NSNotFound) {
                [cellRanges addObject:[NSValue valueWithRange:NSMakeRange(rowRange.location + searchStart, rowStr.length - searchStart)]];
                break;
            } else {
                [cellRanges addObject:[NSValue valueWithRange:NSMakeRange(rowRange.location + searchStart, found.location - searchStart)]];
                searchStart = found.location + found.length;
            }
        }
        if ((NSInteger)cellRanges.count > maxCols) {
            maxCols = (NSInteger)cellRanges.count;
        }
        [allRowsCells addObject:cellRanges];
    }

    NSInteger totalWidth = 9000;
    NSInteger colWidth = totalWidth / MAX(1, maxCols);

    [xml appendString:@"  <w:tbl>\n"];
    [xml appendString:@"    <w:tblPr>\n"];
    [xml appendString:@"      <w:bidiVisual/>\n"];
    [xml appendFormat:@"      <w:tblW w:w=\"%ld\" w:type=\"dxa\"/>\n", (long)totalWidth];
    [xml appendString:@"      <w:tblBorders>\n"];
    [xml appendString:@"        <w:top w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"444444\"/>\n"];
    [xml appendString:@"        <w:left w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"444444\"/>\n"];
    [xml appendString:@"        <w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"444444\"/>\n"];
    [xml appendString:@"        <w:right w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"444444\"/>\n"];
    [xml appendString:@"        <w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"888888\"/>\n"];
    [xml appendString:@"        <w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"888888\"/>\n"];
    [xml appendString:@"      </w:tblBorders>\n"];
    [xml appendString:@"      <w:tblCellMar>\n"];
    [xml appendString:@"        <w:top w:w=\"80\" w:type=\"dxa\"/>\n"];
    [xml appendString:@"        <w:left w:w=\"120\" w:type=\"dxa\"/>\n"];
    [xml appendString:@"        <w:bottom w:w=\"80\" w:type=\"dxa\"/>\n"];
    [xml appendString:@"        <w:right w:w=\"120\" w:type=\"dxa\"/>\n"];
    [xml appendString:@"      </w:tblCellMar>\n"];
    [xml appendString:@"    </w:tblPr>\n"];

    [xml appendString:@"    <w:tblGrid>\n"];
    for (NSInteger c = 0; c < maxCols; c++) {
        [xml appendFormat:@"      <w:gridCol w:w=\"%ld\"/>\n", (long)colWidth];
    }
    [xml appendString:@"    </w:tblGrid>\n"];

    for (NSUInteger r = 0; r < allRowsCells.count; r++) {
        NSArray<NSValue *> *cells = allRowsCells[r];
        BOOL isHeader = (r == 0);
        [xml appendString:@"    <w:tr>\n"];
        if (isHeader) {
            [xml appendString:@"      <w:trPr><w:tblHeader/></w:trPr>\n"];
        }
        for (NSInteger c = 0; c < maxCols; c++) {
            [xml appendString:@"      <w:tc>\n        <w:tcPr>"];
            [xml appendFormat:@"<w:tcW w:w=\"%ld\" w:type=\"dxa\"/>", (long)colWidth];
            if (isHeader) {
                [xml appendString:@"<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"E8EEF5\"/>"];
            }
            [xml appendString:@"</w:tcPr>\n"];
            [xml appendString:@"        <w:p><w:pPr><w:bidi/><w:jc w:val=\"right\"/></w:pPr>\n"];
            if (c < (NSInteger)cells.count) {
                NSRange cRange = [cells[c] rangeValue];
                [self appendFormattedRunsFromAttributedString:attrStr inRange:cRange isRTL:YES trimPadding:YES toXML:xml];
            }
            [xml appendString:@"        </w:p>\n      </w:tc>\n"];
        }
        [xml appendString:@"    </w:tr>\n"];
    }

    [xml appendString:@"  </w:tbl>\n"];
}

+ (NSData *)deflateRaw:(NSData *)rawData {
    if (rawData.length == 0) return [NSData data];
    z_stream strm;
    zero_mem(&strm, sizeof(strm));
    if (deflateInit2(&strm, Z_BEST_SPEED, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    NSMutableData *compressed = [NSMutableData dataWithLength:deflateBound(&strm, (uLong)rawData.length)];
    strm.next_in = (Bytef *)rawData.bytes;
    strm.avail_in = (uInt)rawData.length;
    strm.next_out = (Bytef *)compressed.mutableBytes;
    strm.avail_out = (uInt)compressed.length;

    deflate(&strm, Z_FINISH);
    compressed.length = strm.total_out;
    deflateEnd(&strm);
    return compressed;
}

+ (BOOL)writeAttributedString:(NSAttributedString *)attrStr toDocxURL:(NSURL *)url error:(NSError **)error {
    NSMutableString *xml = [NSMutableString string];
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"];
    [xml appendString:@"<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
                      @"xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
                      @"xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
                      @"xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
                      @"xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">\n<w:body>\n"];

    NSMutableArray<NSDictionary *> *mediaEntries = [NSMutableArray array];
    NSMutableString *docRelsXML = [NSMutableString string];
    [docRelsXML appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"];
    [docRelsXML appendString:@"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n"];

    __block NSInteger imageCounter = 0;

    NSString *fullText = attrStr.string ?: @"";
    NSArray<NSString *> *lines = [fullText componentsSeparatedByString:@"\n"];
    NSUInteger location = 0;
    NSMutableArray<NSValue *> *pendingTableRows = [NSMutableArray array];

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange lineRange = NSMakeRange(location, line.length);

        if ([self isTableLine:line]) {
            [pendingTableRows addObject:[NSValue valueWithRange:lineRange]];
            location += line.length + 1;
            continue;
        }

        if (pendingTableRows.count > 0) {
            [self appendTableFromAttributedString:attrStr rowRanges:pendingTableRows toXML:xml];
            [pendingTableRows removeAllObjects];
        }

        NSTextAlignment align = NSTextAlignmentRight;
        BOOL isRTL = YES;
        if (line.length > 0) {
            NSParagraphStyle *ps = [attrStr attribute:NSParagraphStyleAttributeName atIndex:location effectiveRange:NULL];
            if (ps) {
                align = ps.alignment;
                isRTL = (ps.baseWritingDirection != NSWritingDirectionLeftToRight);
            }
        }

        NSString *jcVal = @"right";
        if (align == NSTextAlignmentLeft) jcVal = @"left";
        else if (align == NSTextAlignmentCenter) jcVal = @"center";
        else if (align == NSTextAlignmentJustified) jcVal = @"both";

        [xml appendString:@"  <w:p>\n    <w:pPr>"];
        if (isRTL) [xml appendString:@"<w:bidi/>"];
        [xml appendFormat:@"<w:jc w:val=\"%@\"/></w:pPr>\n", jcVal];

        if (line.length > 0) {
            [attrStr enumerateAttributesInRange:lineRange options:0 usingBlock:^(NSDictionary<NSString *,id> *attrs, NSRange range, BOOL *stop) {
                NSTextAttachment *attachment = attrs[NSAttachmentAttributeName];
                if (attachment && attachment.image) {
                    UIImage *img = attachment.image;
                    NSData *jpegData = UIImageJPEGRepresentation(img, 0.78);
                    if (jpegData) {
                        imageCounter++;
                        NSString *rId = [NSString stringWithFormat:@"rId%ld", (long)imageCounter];
                        NSString *fileName = [NSString stringWithFormat:@"image%ld.jpg", (long)imageCounter];
                        NSString *zipPath = [NSString stringWithFormat:@"word/media/%@", fileName];

                        [mediaEntries addObject:@{@"name": zipPath, @"data": jpegData, @"store": @YES}];
                        [docRelsXML appendFormat:@"  <Relationship Id=\"%@\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/%@\"/>\n", rId, fileName];

                        CGFloat dispW = (attachment.bounds.size.width > 0) ? attachment.bounds.size.width : MIN(450.0, img.size.width);
                        CGFloat dispH = (attachment.bounds.size.height > 0) ? attachment.bounds.size.height : (img.size.width > 0 ? dispW * (img.size.height / img.size.width) : 300.0);
                        long long cx = (long long)(dispW * 12700.0 + 0.5);
                        long long cy = (long long)(dispH * 12700.0 + 0.5);

                        [xml appendString:@"    <w:r>\n      <w:drawing>\n"];
                        [xml appendString:@"        <wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">\n"];
                        [xml appendFormat:@"          <wp:extent cx=\"%lld\" cy=\"%lld\"/>\n", cx, cy];
                        [xml appendString:@"          <wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>\n"];
                        [xml appendFormat:@"          <wp:docPr id=\"%ld\" name=\"Picture %ld\"/>\n", (long)imageCounter, (long)imageCounter];
                        [xml appendString:@"          <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>\n"];
                        [xml appendString:@"          <a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">\n"];
                        [xml appendString:@"            <pic:pic>\n"];
                        [xml appendFormat:@"              <pic:nvPicPr><pic:cNvPr id=\"%ld\" name=\"%@\"/><pic:cNvPicPr/></pic:nvPicPr>\n", (long)imageCounter, fileName];
                        [xml appendFormat:@"              <pic:blipFill><a:blip r:embed=\"%@\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\n", rId];
                        [xml appendFormat:@"              <pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"%lld\" cy=\"%lld\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>\n", cx, cy];
                        [xml appendString:@"            </pic:pic>\n"];
                        [xml appendString:@"          </a:graphicData></a:graphic>\n"];
                        [xml appendString:@"        </wp:inline>\n      </w:drawing>\n    </w:r>\n"];
                    }
                    return;
                }

                [self appendFormattedRunsFromAttributedString:attrStr inRange:range isRTL:isRTL trimPadding:NO toXML:xml];
            }];
        }

        [xml appendString:@"  </w:p>\n"];
        location += line.length + 1;
    }

    if (pendingTableRows.count > 0) {
        [self appendTableFromAttributedString:attrStr rowRanges:pendingTableRows toXML:xml];
        [pendingTableRows removeAllObjects];
    }

    [xml appendString:@"</w:body>\n</w:document>\n"];
    [docRelsXML appendString:@"</Relationships>\n"];

    NSString *contentTypes = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                             @"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\n"
                             @"  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>\n"
                             @"  <Default Extension=\"xml\" ContentType=\"application/xml\"/>\n"
                             @"  <Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>\n"
                             @"  <Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>\n"
                             @"  <Default Extension=\"png\" ContentType=\"image/png\"/>\n"
                             @"  <Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>\n"
                             @"</Types>\n";

    NSString *rels = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                     @"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n"
                     @"  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>\n"
                     @"</Relationships>\n";

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithArray:@[
        @{@"name": @"[Content_Types].xml", @"data": [contentTypes dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"_rels/.rels", @"data": [rels dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"word/_rels/document.xml.rels", @"data": [docRelsXML dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"word/document.xml", @"data": [xml dataUsingEncoding:NSUTF8StringEncoding]}
    ]];
    [entries addObjectsFromArray:mediaEntries];

    NSMutableData *zip = [NSMutableData data];
    NSMutableData *centralDir = [NSMutableData data];

    for (NSDictionary *entry in entries) {
        NSData *nameData = [entry[@"name"] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *rawData = entry[@"data"];
        BOOL storeOnly = [entry[@"store"] boolValue];
        NSData *compData = storeOnly ? rawData : ([self deflateRaw:rawData] ?: rawData);
        uint16_t method = (!storeOnly && compData != rawData) ? 8 : 0;

        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, (const Bytef *)rawData.bytes, (uInt)rawData.length);
        uint32_t localOffset = (uint32_t)zip.length;

        [self appendUInt32:0x04034b50 toData:zip];
        [self appendUInt16:20 toData:zip];
        [self appendUInt16:0 toData:zip];
        [self appendUInt16:method toData:zip];
        [self appendUInt16:0 toData:zip];
        [self appendUInt16:0x0021 toData:zip];
        [self appendUInt32:(uint32_t)crc toData:zip];
        [self appendUInt32:(uint32_t)compData.length toData:zip];
        [self appendUInt32:(uint32_t)rawData.length toData:zip];
        [self appendUInt16:(uint16_t)nameData.length toData:zip];
        [self appendUInt16:0 toData:zip];
        [zip appendData:nameData];
        [zip appendData:compData];

        [self appendUInt32:0x02014b50 toData:centralDir];
        [self appendUInt16:20 toData:centralDir];
        [self appendUInt16:20 toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt16:method toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt16:0x0021 toData:centralDir];
        [self appendUInt32:(uint32_t)crc toData:centralDir];
        [self appendUInt32:(uint32_t)compData.length toData:centralDir];
        [self appendUInt32:(uint32_t)rawData.length toData:centralDir];
        [self appendUInt16:(uint16_t)nameData.length toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt16:0 toData:centralDir];
        [self appendUInt32:0 toData:centralDir];
        [self appendUInt32:localOffset toData:centralDir];
        [centralDir appendData:nameData];
    }

    uint32_t cdOffset = (uint32_t)zip.length;
    [zip appendData:centralDir];

    [self appendUInt32:0x06054b50 toData:zip];
    [self appendUInt16:0 toData:zip];
    [self appendUInt16:0 toData:zip];
    [self appendUInt16:(uint16_t)entries.count toData:zip];
    [self appendUInt16:(uint16_t)entries.count toData:zip];
    [self appendUInt32:(uint32_t)centralDir.length toData:zip];
    [self appendUInt32:cdOffset toData:zip];
    [self appendUInt16:0 toData:zip];

    return [zip writeToURL:url options:NSDataWritingAtomic error:error];
}

@end
