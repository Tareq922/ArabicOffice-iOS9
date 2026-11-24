#import "DocxHelper.h"
#import <zlib.h>

static void zero_mem(void *ptr, size_t len) {
    volatile uint8_t *p = (volatile uint8_t *)ptr;
    while (len--) {
        *p++ = 0;
    }
}

@interface DocxXMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableAttributedString *result;
@property (nonatomic, strong) NSMutableString *currentText;
@property (nonatomic, assign) BOOL inParagraph;
@property (nonatomic, assign) BOOL inRun;
@property (nonatomic, assign) BOOL inText;
@property (nonatomic, assign) BOOL isBold;
@property (nonatomic, assign) BOOL isItalic;
@property (nonatomic, assign) BOOL isUnderline;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSTextAlignment alignment;
@property (nonatomic, assign) BOOL isRTL;
@property (nonatomic, assign) BOOL hasAppendedFirstParagraph;
@end

@implementation DocxXMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _result = [[NSMutableAttributedString alloc] init];
        _currentText = [[NSMutableString alloc] init];
        _fontSize = 18.0;
        _alignment = NSTextAlignmentRight;
        _isRTL = YES;
    }
    return self;
}

- (UIFont *)currentFont {
    NSString *fontName = @"ArialMT";
    if (self.isBold && self.isItalic) {
        fontName = @"Arial-BoldItalicMT";
    } else if (self.isBold) {
        fontName = @"Arial-BoldMT";
    } else if (self.isItalic) {
        fontName = @"Arial-ItalicMT";
    }
    UIFont *font = [UIFont fontWithName:fontName size:self.fontSize];
    if (!font) {
        font = self.isBold ? [UIFont boldSystemFontOfSize:self.fontSize] : [UIFont systemFontOfSize:self.fontSize];
    }
    return font;
}

- (NSDictionary *)currentAttributes {
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = self.alignment;
    para.baseWritingDirection = self.isRTL ? NSWritingDirectionRightToLeft : NSWritingDirectionLeftToRight;

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFontAttributeName] = [self currentFont];
    attrs[NSParagraphStyleAttributeName] = para;
    attrs[NSForegroundColorAttributeName] = [UIColor blackColor];
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

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"w:p"]) {
        if (self.hasAppendedFirstParagraph) {
            NSAttributedString *nl = [[NSAttributedString alloc] initWithString:@"\n" attributes:[self currentAttributes]];
            [self.result appendAttributedString:nl];
        }
        self.hasAppendedFirstParagraph = YES;
        self.inParagraph = YES;
        self.alignment = NSTextAlignmentRight;
        self.isRTL = YES;
    } else if ([elementName isEqualToString:@"w:bidi"] && self.inParagraph) {
        NSString *val = attributeDict[@"w:val"];
        self.isRTL = !(val && ([val isEqualToString:@"0"] || [val isEqualToString:@"false"]));
    } else if ([elementName isEqualToString:@"w:jc"] && self.inParagraph) {
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
    } else if ([elementName isEqualToString:@"w:r"]) {
        [self flushRunText];
        self.inRun = NO;
    } else if ([elementName isEqualToString:@"w:p"]) {
        [self flushRunText];
        self.inParagraph = NO;
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

+ (NSData *)extractDocumentXMLFromZipData:(NSData *)zipData {
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

        if ([entryName isEqualToString:@"word/document.xml"]) {
            if (localOffset + 30 > len) return nil;
            if ([self readUInt32:bytes + localOffset] != 0x04034b50) return nil;
            uint16_t localNameLen = [self readUInt16:bytes + localOffset + 26];
            uint16_t localExtraLen = [self readUInt16:bytes + localOffset + 28];
            NSUInteger dataStart = localOffset + 30 + localNameLen + localExtraLen;
            if (dataStart + compSize > len) return nil;

            if (method == 0) {
                return [zipData subdataWithRange:NSMakeRange(dataStart, uncompSize)];
            } else if (method == 8) {
                NSMutableData *outData = [NSMutableData dataWithLength:uncompSize];
                z_stream strm;
                zero_mem(&strm, sizeof(strm));
                strm.next_in = (Bytef *)(bytes + dataStart);
                strm.avail_in = (uInt)compSize;
                strm.next_out = (Bytef *)outData.mutableBytes;
                strm.avail_out = (uInt)uncompSize;

                if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) return nil;
                int ret = inflate(&strm, Z_FINISH);
                inflateEnd(&strm);
                if (ret == Z_STREAM_END || ret == Z_OK) {
                    return outData;
                }
                return nil;
            }
        }
        pos += 46 + nameLen + extraLen + commentLen;
    }
    return nil;
}

+ (NSAttributedString *)attributedStringFromDocxURL:(NSURL *)url error:(NSError **)error {
    NSData *zipData = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!zipData) return nil;

    NSData *xmlData = [self extractDocumentXMLFromZipData:zipData];
    if (!xmlData) {
        if (error) {
            *error = [NSError errorWithDomain:@"ArabicOfficeDocx" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"تعذر قراءة محتوى ملف Word (.docx)"}];
        }
        return nil;
    }

    DocxXMLParserDelegate *delegate = [[DocxXMLParserDelegate alloc] init];
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

+ (NSString *)buildDocumentXMLFromAttributedString:(NSAttributedString *)attrStr {
    NSMutableString *xml = [NSMutableString string];
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"];
    [xml appendString:@"<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\n<w:body>\n"];

    NSString *fullText = attrStr.string ?: @"";
    NSArray<NSString *> *lines = [fullText componentsSeparatedByString:@"\n"];
    NSUInteger location = 0;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange lineRange = NSMakeRange(location, line.length);

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
                NSString *sub = [fullText substringWithRange:range];
                UIFont *font = attrs[NSFontAttributeName];
                NSNumber *underline = attrs[NSUnderlineStyleAttributeName];

                BOOL bold = NO;
                BOOL italic = NO;
                CGFloat size = 18.0;
                if (font) {
                    size = font.pointSize;
                    UIFontDescriptorSymbolicTraits traits = font.fontDescriptor.symbolicTraits;
                    bold = (traits & UIFontDescriptorTraitBold) != 0 || ([font.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
                    italic = (traits & UIFontDescriptorTraitItalic) != 0 || ([font.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
                }
                BOOL under = (underline && underline.integerValue != NSUnderlineStyleNone);
                NSInteger halfPts = (NSInteger)(size * 2.0 + 0.5);

                [xml appendString:@"    <w:r>\n      <w:rPr>"];
                if (isRTL) [xml appendString:@"<w:rtl/>"];
                if (bold) [xml appendString:@"<w:b/>"];
                if (italic) [xml appendString:@"<w:i/>"];
                if (under) [xml appendString:@"<w:u w:val=\"single\"/>"];
                [xml appendFormat:@"<w:sz w:val=\"%ld\"/><w:szCs w:val=\"%ld\"/>", (long)halfPts, (long)halfPts];
                [xml appendString:@"</w:rPr>\n"];
                [xml appendFormat:@"      <w:t xml:space=\"preserve\">%@</w:t>\n    </w:r>\n", [self escapeXML:sub]];
            }];
        }

        [xml appendString:@"  </w:p>\n"];
        location += line.length + 1;
    }

    [xml appendString:@"</w:body>\n</w:document>\n"];
    return xml;
}

+ (NSData *)deflateRaw:(NSData *)rawData {
    if (rawData.length == 0) return [NSData data];
    z_stream strm;
    zero_mem(&strm, sizeof(strm));
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
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
    NSString *contentTypes = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                             @"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\n"
                             @"  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>\n"
                             @"  <Default Extension=\"xml\" ContentType=\"application/xml\"/>\n"
                             @"  <Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>\n"
                             @"</Types>\n";

    NSString *rels = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                     @"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n"
                     @"  <Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>\n"
                     @"</Relationships>\n";

    NSString *docRels = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                        @"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n"
                        @"</Relationships>\n";

    NSString *docXML = [self buildDocumentXMLFromAttributedString:attrStr];

    NSArray<NSDictionary *> *entries = @[
        @{@"name": @"[Content_Types].xml", @"data": [contentTypes dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"_rels/.rels", @"data": [rels dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"word/_rels/document.xml.rels", @"data": [docRels dataUsingEncoding:NSUTF8StringEncoding]},
        @{@"name": @"word/document.xml", @"data": [docXML dataUsingEncoding:NSUTF8StringEncoding]}
    ];

    NSMutableData *zip = [NSMutableData data];
    NSMutableData *centralDir = [NSMutableData data];

    for (NSDictionary *entry in entries) {
        NSData *nameData = [entry[@"name"] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *rawData = entry[@"data"];
        NSData *compData = [self deflateRaw:rawData];
        if (!compData) compData = rawData;
        uint16_t method = (compData != rawData) ? 8 : 0;

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
