#import <UIKit/UIKit.h>
#import "DocxHelper.h"

@interface EditorViewController : UIViewController <UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSURL *currentFileURL;
@property (nonatomic, strong) UIBarButtonItem *saveShareItem;
@property (nonatomic, strong) UIBarButtonItem *openItem;
@property (nonatomic, strong) UIBarButtonItem *tableItem;
@property (nonatomic, strong) UIBarButtonItem *fontItem;
@property (nonatomic, strong) UIBarButtonItem *colorItem;
@property (nonatomic, strong) UIBarButtonItem *listItem;
@property (nonatomic, strong) UIView *loadingOverlay;
@property (nonatomic, strong) UILabel *loadingLabel;
@property (nonatomic, copy) NSString *activeFontFamily;
- (void)openDocumentAtURL:(NSURL *)url;
@end

@implementation EditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"مستند_جديد.docx";
    self.activeFontFamily = @"Arial";

    UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithTitle:@"جديد" style:UIBarButtonItemStylePlain target:self action:@selector(newDoc)];
    self.openItem = [[UIBarButtonItem alloc] initWithTitle:@"فتح" style:UIBarButtonItemStylePlain target:self action:@selector(openDocList)];
    UIBarButtonItem *undoItem = [[UIBarButtonItem alloc] initWithTitle:@"تراجع" style:UIBarButtonItemStylePlain target:self action:@selector(undoEdit)];
    UIBarButtonItem *redoItem = [[UIBarButtonItem alloc] initWithTitle:@"إعادة" style:UIBarButtonItemStylePlain target:self action:@selector(redoEdit)];
    self.navigationItem.leftBarButtonItems = @[self.openItem, newItem, undoItem, redoItem];

    UIBarButtonItem *rtlItem = [[UIBarButtonItem alloc] initWithTitle:@"ضبط RTL" style:UIBarButtonItemStylePlain target:self action:@selector(applyRTL)];
    self.saveShareItem = [[UIBarButtonItem alloc] initWithTitle:@"حفظ ومشاركة" style:UIBarButtonItemStyleDone target:self action:@selector(saveAndShare)];
    self.navigationItem.rightBarButtonItems = @[rtlItem, self.saveShareItem];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor whiteColor];
    self.textView.textContainerInset = UIEdgeInsetsMake(20, 24, 20, 24);
    self.textView.layoutManager.allowsNonContiguousLayout = YES;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.delegate = self;

    [self setupFormattingToolbar];
    [self.view addSubview:self.textView];
    [self setupLoadingOverlay];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];

    [self newDoc];
}

- (void)setupLoadingOverlay {
    self.loadingOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.loadingOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.loadingOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    self.loadingOverlay.hidden = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 90)];
    box.center = CGPointMake(self.loadingOverlay.bounds.size.width / 2.0, self.loadingOverlay.bounds.size.height / 2.0);
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    box.backgroundColor = [UIColor whiteColor];
    box.layer.cornerRadius = 12.0;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    spinner.center = CGPointMake(110, 30);
    [spinner startAnimating];
    [box addSubview:spinner];

    self.loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 52, 200, 26)];
    self.loadingLabel.textAlignment = NSTextAlignmentCenter;
    self.loadingLabel.font = [UIFont systemFontOfSize:15.0];
    self.loadingLabel.textColor = [UIColor darkGrayColor];
    [box addSubview:self.loadingLabel];

    [self.loadingOverlay addSubview:box];
    [self.view addSubview:self.loadingOverlay];
}

- (void)setLoading:(BOOL)loading message:(NSString *)msg {
    self.loadingLabel.text = msg ?: @"يرجى الانتظار...";
    self.loadingOverlay.hidden = !loading;
}

- (void)setupFormattingToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    UIBarButtonItem *hideKB = [[UIBarButtonItem alloc] initWithTitle:@"إخفاء" style:UIBarButtonItemStylePlain target:self.textView action:@selector(resignFirstResponder)];
    UIBarButtonItem *insertImg = [[UIBarButtonItem alloc] initWithTitle:@"صورة" style:UIBarButtonItemStylePlain target:self action:@selector(pickImage)];
    self.tableItem = [[UIBarButtonItem alloc] initWithTitle:@"جدول" style:UIBarButtonItemStylePlain target:self action:@selector(chooseTableAction)];
    self.fontItem = [[UIBarButtonItem alloc] initWithTitle:@"الخط" style:UIBarButtonItemStylePlain target:self action:@selector(chooseFont)];
    self.colorItem = [[UIBarButtonItem alloc] initWithTitle:@"اللون" style:UIBarButtonItemStylePlain target:self action:@selector(chooseColor)];
    self.listItem = [[UIBarButtonItem alloc] initWithTitle:@"قائمة" style:UIBarButtonItemStylePlain target:self action:@selector(chooseList)];
    UIBarButtonItem *alignR = [[UIBarButtonItem alloc] initWithTitle:@"يمين" style:UIBarButtonItemStylePlain target:self action:@selector(alignRight)];
    UIBarButtonItem *alignC = [[UIBarButtonItem alloc] initWithTitle:@"وسط" style:UIBarButtonItemStylePlain target:self action:@selector(alignCenter)];
    UIBarButtonItem *alignL = [[UIBarButtonItem alloc] initWithTitle:@"يسار" style:UIBarButtonItemStylePlain target:self action:@selector(alignLeft)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *fontMinus = [[UIBarButtonItem alloc] initWithTitle:@"خط-" style:UIBarButtonItemStylePlain target:self action:@selector(decreaseFont)];
    UIBarButtonItem *fontPlus = [[UIBarButtonItem alloc] initWithTitle:@"خط+" style:UIBarButtonItemStylePlain target:self action:@selector(increaseFont)];
    UIBarButtonItem *underline = [[UIBarButtonItem alloc] initWithTitle:@"U" style:UIBarButtonItemStylePlain target:self action:@selector(toggleUnderline)];
    UIBarButtonItem *italic = [[UIBarButtonItem alloc] initWithTitle:@"I" style:UIBarButtonItemStylePlain target:self action:@selector(toggleItalic)];
    UIBarButtonItem *bold = [[UIBarButtonItem alloc] initWithTitle:@"B" style:UIBarButtonItemStyleDone target:self action:@selector(toggleBold)];

    toolbar.items = @[hideKB, insertImg, self.tableItem, self.fontItem, self.colorItem, self.listItem, alignR, alignC, alignL, flex, fontMinus, fontPlus, underline, italic, bold];
    self.textView.inputAccessoryView = toolbar;
}

#pragma mark - أدوات الجداول

- (NSAttributedString *)attributedTableRowWithCells:(NSArray<NSString *> *)cells isHeader:(BOOL)isHeader {
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentRight;
    para.baseWritingDirection = NSWritingDirectionRightToLeft;
    para.lineSpacing = 4.0;

    UIFont *font = [self buildFontWithFamily:self.activeFontFamily size:18.0 bold:isHeader italic:NO];
    NSMutableDictionary *cellAttrs = [@{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: para,
        NSForegroundColorAttributeName: [UIColor blackColor]
    } mutableCopy];

    if (isHeader) {
        cellAttrs[NSBackgroundColorAttributeName] = [UIColor colorWithRed:0.91 green:0.94 blue:0.98 alpha:1.0];
    }

    NSMutableDictionary *sepAttrs = [cellAttrs mutableCopy];
    sepAttrs[NSForegroundColorAttributeName] = [UIColor colorWithRed:0.25 green:0.45 blue:0.75 alpha:1.0];

    NSMutableAttributedString *row = [[NSMutableAttributedString alloc] init];
    for (NSUInteger i = 0; i < cells.count; i++) {
        if (i > 0) {
            [row appendAttributedString:[[NSAttributedString alloc] initWithString:@" │ " attributes:sepAttrs]];
        }
        [row appendAttributedString:[[NSAttributedString alloc] initWithString:cells[i] attributes:cellAttrs]];
    }
    return row;
}

- (void)chooseTableAction {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"أدوات الجداول" message:@"تُحفظ الجداول كجداول Word رسمية (.docx)" preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"إدراج جدول جديد..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptInsertTable];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"إضافة صف جديد للجدول" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self addRowToCurrentTable];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"إضافة عمود للجدول" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self addColumnToCurrentTable];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"حذف الصف الحالي" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteCurrentTableRow];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.tableItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptInsertTable {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إدراج جدول جديد" message:@"حدد عدد الأعمدة والصفوف:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"عدد الأعمدة (مثال: 3)";
        tf.text = @"3";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"عدد الصفوف (مثال: 3)";
        tf.text = @"3";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.textAlignment = NSTextAlignmentCenter;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"إدراج" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger cols = MAX(1, MIN(10, alert.textFields[0].text.integerValue));
        NSInteger rows = MAX(1, MIN(50, alert.textFields[1].text.integerValue));

        NSMutableAttributedString *tableBlock = [[NSMutableAttributedString alloc] init];
        NSDictionary *defAttrs = [self defaultArabicAttributes];

        NSTextStorage *storage = self.textView.textStorage;
        NSRange sel = self.textView.selectedRange;
        if (sel.location == NSNotFound || sel.location > storage.length) {
            sel = NSMakeRange(storage.length, 0);
        }

        if (sel.location > 0 && [storage.string characterAtIndex:sel.location - 1] != '\n') {
            [tableBlock appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:defAttrs]];
        }

        for (NSInteger r = 0; r < rows; r++) {
            NSMutableArray<NSString *> *cells = [NSMutableArray arrayWithCapacity:cols];
            for (NSInteger c = 0; c < cols; c++) {
                if (r == 0) {
                    [cells addObject:[NSString stringWithFormat:@"عنوان %ld", (long)(c + 1)]];
                } else {
                    [cells addObject:@"بيانات"];
                }
            }
            [tableBlock appendAttributedString:[self attributedTableRowWithCells:cells isHeader:(r == 0)]];
            [tableBlock appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:defAttrs]];
        }

        [storage beginEditing];
        [storage replaceCharactersInRange:sel withAttributedString:tableBlock];
        [storage endEditing];
        self.textView.selectedRange = NSMakeRange(sel.location + tableBlock.length, 0);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSRange)currentParagraphLineRange {
    NSTextStorage *storage = self.textView.textStorage;
    if (storage.length == 0) return NSMakeRange(0, 0);
    NSRange sel = self.textView.selectedRange;
    if (sel.location == NSNotFound || sel.location >= storage.length) {
        sel = NSMakeRange(storage.length - 1, 0);
    }
    NSRange paraRange = [storage.string paragraphRangeForRange:sel];
    while (paraRange.length > 0 && [storage.string characterAtIndex:NSMaxRange(paraRange) - 1] == '\n') {
        paraRange.length--;
    }
    return paraRange;
}

- (void)addRowToCurrentTable {
    NSTextStorage *storage = self.textView.textStorage;
    NSRange lineRange = [self currentParagraphLineRange];
    if (lineRange.length == 0) {
        [self showMessage:@"تنبيه" body:@"ضع المؤشر داخل صف من الجدول أولاً لإضافة صف جديد."];
        return;
    }

    NSString *lineStr = [storage.string substringWithRange:lineRange];
    NSString *sep = ([lineStr rangeOfString:@"│"].location != NSNotFound) ? @"│" : (([lineStr rangeOfString:@"|"].location != NSNotFound) ? @"|" : nil);
    if (!sep) {
        [self showMessage:@"تنبيه" body:@"السطر الحالي لا يحتوي على جدول. ضع المؤشر داخل الجدول أولاً."];
        return;
    }

    NSArray<NSString *> *parts = [lineStr componentsSeparatedByString:sep];
    NSMutableArray<NSString *> *newCells = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSUInteger i = 0; i < parts.count; i++) {
        [newCells addObject:@"بيانات"];
    }

    NSMutableAttributedString *insertRow = [[NSMutableAttributedString alloc] initWithString:@"\n" attributes:[self defaultArabicAttributes]];
    [insertRow appendAttributedString:[self attributedTableRowWithCells:newCells isHeader:NO]];

    NSUInteger insertPos = NSMaxRange(lineRange);
    [storage beginEditing];
    [storage replaceCharactersInRange:NSMakeRange(insertPos, 0) withAttributedString:insertRow];
    [storage endEditing];
    self.textView.selectedRange = NSMakeRange(insertPos + 1, 0);
}

- (void)addColumnToCurrentTable {
    NSTextStorage *storage = self.textView.textStorage;
    NSRange curLine = [self currentParagraphLineRange];
    if (curLine.length == 0) {
        [self showMessage:@"تنبيه" body:@"ضع المؤشر داخل الجدول أولاً لإضافة عمود."];
        return;
    }

    NSString *full = storage.string;
    NSString *curStr = [full substringWithRange:curLine];
    if ([curStr rangeOfString:@"│"].location == NSNotFound && [curStr rangeOfString:@"|"].location == NSNotFound) {
        [self showMessage:@"تنبيه" body:@"السطر الحالي لا يحتوي على جدول."];
        return;
    }

    // تحديد بداية ونهاية كتلة الجدول المتصلة
    NSUInteger blockStart = curLine.location;
    while (blockStart > 0) {
        NSRange prevPara = [full paragraphRangeForRange:NSMakeRange(blockStart - 1, 0)];
        NSRange prevClean = prevPara;
        while (prevClean.length > 0 && [full characterAtIndex:NSMaxRange(prevClean) - 1] == '\n') prevClean.length--;
        NSString *prevStr = [full substringWithRange:prevClean];
        if ([prevStr rangeOfString:@"│"].location != NSNotFound || [prevStr rangeOfString:@"|"].location != NSNotFound) {
            blockStart = prevPara.location;
        } else {
            break;
        }
    }

    NSUInteger blockEnd = NSMaxRange(curLine);
    while (blockEnd < full.length) {
        NSUInteger nextStart = blockEnd;
        if ([full characterAtIndex:nextStart] == '\n') nextStart++;
        if (nextStart >= full.length) break;
        NSRange nextPara = [full paragraphRangeForRange:NSMakeRange(nextStart, 0)];
        NSRange nextClean = nextPara;
        while (nextClean.length > 0 && [full characterAtIndex:NSMaxRange(nextClean) - 1] == '\n') nextClean.length--;
        NSString *nextStr = [full substringWithRange:nextClean];
        if ([nextStr rangeOfString:@"│"].location != NSNotFound || [nextStr rangeOfString:@"|"].location != NSNotFound) {
            blockEnd = NSMaxRange(nextClean);
        } else {
            break;
        }
    }

    NSRange tableRange = NSMakeRange(blockStart, blockEnd - blockStart);
    NSString *tableBlockStr = [full substringWithRange:tableRange];
    NSArray<NSString *> *rows = [tableBlockStr componentsSeparatedByString:@"\n"];

    NSMutableAttributedString *rebuilt = [[NSMutableAttributedString alloc] init];
    for (NSUInteger r = 0; r < rows.count; r++) {
        NSString *rowStr = rows[r];
        NSString *sep = ([rowStr rangeOfString:@"│"].location != NSNotFound) ? @"│" : @"|";
        NSArray<NSString *> *rawCells = [rowStr componentsSeparatedByString:sep];
        NSMutableArray<NSString *> *trimmedCells = [NSMutableArray arrayWithCapacity:rawCells.count + 1];
        for (NSString *c in rawCells) {
            [trimmedCells addObject:[c stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        [trimmedCells addObject:(r == 0 ? @"عمود جديد" : @"بيانات")];

        if (r > 0) {
            [rebuilt appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:[self defaultArabicAttributes]]];
        }
        [rebuilt appendAttributedString:[self attributedTableRowWithCells:trimmedCells isHeader:(r == 0)]];
    }

    [storage beginEditing];
    [storage replaceCharactersInRange:tableRange withAttributedString:rebuilt];
    [storage endEditing];
}

- (void)deleteCurrentTableRow {
    NSTextStorage *storage = self.textView.textStorage;
    if (storage.length == 0) return;
    NSRange sel = self.textView.selectedRange;
    if (sel.location == NSNotFound || sel.location >= storage.length) {
        sel = NSMakeRange(storage.length - 1, 0);
    }
    NSRange paraRange = [storage.string paragraphRangeForRange:sel];
    NSString *lineStr = [storage.string substringWithRange:paraRange];
    if ([lineStr rangeOfString:@"│"].location == NSNotFound && [lineStr rangeOfString:@"|"].location == NSNotFound) {
        [self showMessage:@"تنبيه" body:@"السطر الحالي ليس صفاً في جدول."];
        return;
    }

    [storage beginEditing];
    [storage deleteCharactersInRange:paraRange];
    [storage endEditing];
}

#pragma mark - الخطوط والألوان والقوائم والمحاذاة

- (UIFont *)buildFontWithFamily:(NSString *)family size:(CGFloat)size bold:(BOOL)isB italic:(BOOL)isI {
    NSString *fam = family ?: self.activeFontFamily ?: @"Arial";
    NSString *name = @"ArialMT";
    if ([fam isEqualToString:@"GeezaPro"]) {
        name = isB ? @"GeezaPro-Bold" : @"GeezaPro";
    } else if ([fam isEqualToString:@"Damascus"]) {
        name = isB ? @"DamascusBold" : @"Damascus";
    } else if ([fam isEqualToString:@"Baghdad"]) {
        name = @"Baghdad";
    } else {
        if (isB && isI) name = @"Arial-BoldItalicMT";
        else if (isB) name = @"Arial-BoldMT";
        else if (isI) name = @"Arial-ItalicMT";
    }
    UIFont *f = [UIFont fontWithName:name size:size];
    if (!f) {
        f = isB ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    }
    return f;
}

- (void)chooseFont {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"نوع الخط العربي" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary<NSString *, NSString *> *fonts = @{
        @"Arial (الافتراضي)": @"Arial",
        @"Geeza Pro (نسخ واضح)": @"GeezaPro",
        @"Damascus (دمشق)": @"Damascus",
        @"Baghdad (بغداد)": @"Baghdad"
    };
    NSArray *titles = @[@"Arial (الافتراضي)", @"Geeza Pro (نسخ واضح)", @"Damascus (دمشق)", @"Baghdad (بغداد)"];
    for (NSString *t in titles) {
        NSString *fam = fonts[t];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self applyFontFamily:fam];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.fontItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)applyFontFamily:(NSString *)family {
    self.activeFontFamily = family;
    NSTextStorage *storage = self.textView.textStorage;
    NSRange range = self.textView.selectedRange;

    if (range.length > 0) {
        [storage beginEditing];
        [storage enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(UIFont *font, NSRange subRange, BOOL *stop) {
            UIFont *base = font ?: [self buildFontWithFamily:family size:19.0 bold:NO italic:NO];
            BOOL isB = ([base.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
            BOOL isI = ([base.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
            UIFont *newFont = [self buildFontWithFamily:family size:base.pointSize bold:isB italic:isI];
            [storage addAttribute:NSFontAttributeName value:newFont range:subRange];
        }];
        [storage endEditing];
    }

    NSMutableDictionary *typing = [self.textView.typingAttributes mutableCopy] ?: [[self defaultArabicAttributes] mutableCopy];
    UIFont *curTyping = typing[NSFontAttributeName];
    CGFloat sz = curTyping ? curTyping.pointSize : 19.0;
    BOOL isB = curTyping && ([curTyping.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL isI = curTyping && ([curTyping.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
    typing[NSFontAttributeName] = [self buildFontWithFamily:family size:sz bold:isB italic:isI];
    self.textView.typingAttributes = typing;
}

- (void)chooseColor {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"لون النص" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"أسود" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self applyTextColor:[UIColor blackColor]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"أزرق داكن" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self applyTextColor:[UIColor colorWithRed:0.05 green:0.28 blue:0.65 alpha:1.0]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"أحمر" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self applyTextColor:[UIColor colorWithRed:0.75 green:0.10 blue:0.10 alpha:1.0]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"أخضر" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self applyTextColor:[UIColor colorWithRed:0.08 green:0.48 blue:0.20 alpha:1.0]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.colorItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)applyTextColor:(UIColor *)color {
    NSTextStorage *storage = self.textView.textStorage;
    NSRange range = self.textView.selectedRange;
    if (range.length > 0) {
        [storage beginEditing];
        [storage addAttribute:NSForegroundColorAttributeName value:color range:range];
        [storage endEditing];
    }
    NSMutableDictionary *typing = [self.textView.typingAttributes mutableCopy] ?: [[self defaultArabicAttributes] mutableCopy];
    typing[NSForegroundColorAttributeName] = color;
    self.textView.typingAttributes = typing;
}

- (void)chooseList {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"تنسيق القوائم" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"قائمة نقطية (•)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self formatSelectedLinesAsNumbered:NO removePrefix:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"قائمة رقمية (1. 2. 3.)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self formatSelectedLinesAsNumbered:YES removePrefix:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إزالة الترقيم/النقاط" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self formatSelectedLinesAsNumbered:NO removePrefix:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.listItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)formatSelectedLinesAsNumbered:(BOOL)numbered removePrefix:(BOOL)removeOnly {
    NSTextStorage *storage = self.textView.textStorage;
    NSRange sel = self.textView.selectedRange;
    if (sel.location == NSNotFound || sel.location > storage.length) {
        sel = NSMakeRange(storage.length, 0);
    }

    if (storage.length == 0) {
        if (!removeOnly) {
            NSString *prefix = numbered ? @"1. " : @"• ";
            NSAttributedString *ins = [[NSAttributedString alloc] initWithString:prefix attributes:self.textView.typingAttributes ?: [self defaultArabicAttributes]];
            [storage beginEditing];
            [storage replaceCharactersInRange:NSMakeRange(0, 0) withAttributedString:ins];
            [storage endEditing];
            self.textView.selectedRange = NSMakeRange(prefix.length, 0);
        }
        return;
    }

    NSRange paraRange = [storage.string paragraphRangeForRange:sel];
    NSString *block = [storage.string substringWithRange:paraRange];
    NSArray<NSString *> *lines = [block componentsSeparatedByString:@"\n"];

    NSMutableArray<NSString *> *updatedLines = [NSMutableArray arrayWithCapacity:lines.count];
    NSInteger counter = 1;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        if (i == lines.count - 1 && line.length == 0 && lines.count > 1) {
            [updatedLines addObject:@""];
            continue;
        }
        NSString *clean = line;
        if ([clean hasPrefix:@"• "]) {
            clean = [clean substringFromIndex:2];
        } else {
            NSRange dotRange = [clean rangeOfString:@". "];
            if (dotRange.location != NSNotFound && dotRange.location <= 3) {
                NSString *numPart = [clean substringToIndex:dotRange.location];
                if (numPart.integerValue > 0) {
                    clean = [clean substringFromIndex:dotRange.location + 2];
                }
            }
        }
        if (removeOnly) {
            [updatedLines addObject:clean];
        } else {
            NSString *prefix = numbered ? [NSString stringWithFormat:@"%ld. ", (long)counter++] : @"• ";
            [updatedLines addObject:[prefix stringByAppendingString:clean]];
        }
    }

    NSString *replacement = [updatedLines componentsJoinedByString:@"\n"];
    NSDictionary *attrs = [storage attributesAtIndex:paraRange.location effectiveRange:NULL];
    NSAttributedString *repAttr = [[NSAttributedString alloc] initWithString:replacement attributes:attrs];

    [storage beginEditing];
    [storage replaceCharactersInRange:paraRange withAttributedString:repAttr];
    [storage endEditing];
    self.textView.selectedRange = NSMakeRange(paraRange.location, repAttr.length);
}

- (void)undoEdit {
    if ([self.textView.undoManager canUndo]) {
        [self.textView.undoManager undo];
    }
}

- (void)redoEdit {
    if ([self.textView.undoManager canRedo]) {
        [self.textView.undoManager redo];
    }
}

- (void)setParagraphAlignment:(NSTextAlignment)alignment {
    NSTextStorage *storage = self.textView.textStorage;
    NSRange sel = self.textView.selectedRange;
    if (sel.location == NSNotFound || sel.location > storage.length) {
        sel = NSMakeRange(storage.length, 0);
    }

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = alignment;
    para.baseWritingDirection = (alignment == NSTextAlignmentLeft) ? NSWritingDirectionLeftToRight : NSWritingDirectionRightToLeft;

    if (storage.length > 0) {
        NSRange paraRange = [storage.string paragraphRangeForRange:sel];
        [storage beginEditing];
        [storage addAttribute:NSParagraphStyleAttributeName value:para range:paraRange];
        [storage endEditing];
    }

    NSMutableDictionary *typing = [self.textView.typingAttributes mutableCopy] ?: [[self defaultArabicAttributes] mutableCopy];
    typing[NSParagraphStyleAttributeName] = para;
    self.textView.typingAttributes = typing;
}

- (void)alignRight { [self setParagraphAlignment:NSTextAlignmentRight]; }
- (void)alignCenter { [self setParagraphAlignment:NSTextAlignmentCenter]; }
- (void)alignLeft { [self setParagraphAlignment:NSTextAlignmentLeft]; }

- (void)pickImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *picked = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!picked) return;

        CGFloat maxDim = 768.0;
        UIImage *finalImg = picked;
        if (picked.size.width > maxDim || picked.size.height > maxDim) {
            CGFloat scale = maxDim / MAX(picked.size.width, picked.size.height);
            CGSize newSize = CGSizeMake((CGFloat)(NSInteger)(picked.size.width * scale + 0.5), (CGFloat)(NSInteger)(picked.size.height * scale + 0.5));
            UIGraphicsBeginImageContextWithOptions(newSize, YES, 1.0);
            [picked drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            if (resized) finalImg = resized;
        }

        CGFloat maxDisplayW = 460.0;
        CGFloat dispW = finalImg.size.width;
        CGFloat dispH = finalImg.size.height;
        if (dispW > maxDisplayW && dispW > 0) {
            CGFloat ratio = maxDisplayW / dispW;
            dispW = maxDisplayW;
            dispH = (CGFloat)(NSInteger)(dispH * ratio + 0.5);
        }

        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = finalImg;
        attachment.bounds = CGRectMake(0, 0, dispW, dispH);

        NSMutableAttributedString *imgStr = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
        [imgStr addAttributes:[self defaultArabicAttributes] range:NSMakeRange(0, imgStr.length)];

        NSMutableAttributedString *insertion = [[NSMutableAttributedString alloc] initWithString:@"\n" attributes:[self defaultArabicAttributes]];
        [insertion appendAttributedString:imgStr];
        [insertion appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:[self defaultArabicAttributes]]];

        NSTextStorage *storage = self.textView.textStorage;
        NSRange sel = self.textView.selectedRange;
        if (sel.location == NSNotFound || sel.location > storage.length) {
            sel = NSMakeRange(storage.length, 0);
        }

        [storage beginEditing];
        [storage replaceCharactersInRange:sel withAttributedString:insertion];
        [storage endEditing];
        self.textView.selectedRange = NSMakeRange(sel.location + insertion.length, 0);
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect localFrame = [self.view convertRect:kbFrame fromView:nil];
    CGFloat bottomInset = MAX(0, self.view.bounds.size.height - localFrame.origin.y);
    UIEdgeInsets insets = self.textView.contentInset;
    insets.bottom = bottomInset;
    self.textView.contentInset = insets;
    self.textView.scrollIndicatorInsets = insets;
}

- (NSDictionary *)defaultArabicAttributes {
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentRight;
    para.baseWritingDirection = NSWritingDirectionRightToLeft;
    UIFont *font = [self buildFontWithFamily:self.activeFontFamily size:19.0 bold:NO italic:NO];
    return @{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: para,
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
}

- (void)newDoc {
    self.currentFileURL = nil;
    self.title = @"مستند_جديد.docx";
    self.textView.typingAttributes = [self defaultArabicAttributes];
    self.textView.attributedText = [[NSAttributedString alloc] initWithString:@"بسم الله الرحمن الرحيم\n" attributes:[self defaultArabicAttributes]];
}

- (void)applyRTL {
    NSTextStorage *storage = self.textView.textStorage;
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentRight;
    para.baseWritingDirection = NSWritingDirectionRightToLeft;

    [storage beginEditing];
    [storage addAttribute:NSParagraphStyleAttributeName value:para range:NSMakeRange(0, storage.length)];
    [storage endEditing];
    self.textView.typingAttributes = [self defaultArabicAttributes];
}

- (void)modifySelectedFontWithBold:(BOOL)toggleBold italic:(BOOL)toggleItalic sizeDelta:(CGFloat)delta {
    NSRange range = self.textView.selectedRange;
    if (range.length > 0) {
        NSTextStorage *storage = self.textView.textStorage;
        [storage beginEditing];
        [storage enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(UIFont *font, NSRange subRange, BOOL *stop) {
            UIFont *base = font ?: [self buildFontWithFamily:self.activeFontFamily size:19.0 bold:NO italic:NO];
            CGFloat size = MAX(12.0, MIN(48.0, base.pointSize + delta));
            BOOL isB = ([base.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
            BOOL isI = ([base.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
            if (toggleBold) isB = !isB;
            if (toggleItalic) isI = !isI;

            NSString *fam = self.activeFontFamily;
            if ([base.fontName rangeOfString:@"Geeza" options:NSCaseInsensitiveSearch].location != NSNotFound) fam = @"GeezaPro";
            else if ([base.fontName rangeOfString:@"Damascus" options:NSCaseInsensitiveSearch].location != NSNotFound) fam = @"Damascus";
            else if ([base.fontName rangeOfString:@"Baghdad" options:NSCaseInsensitiveSearch].location != NSNotFound) fam = @"Baghdad";

            UIFont *newFont = [self buildFontWithFamily:fam size:size bold:isB italic:isI];
            [storage addAttribute:NSFontAttributeName value:newFont range:subRange];
        }];
        [storage endEditing];
    }

    NSMutableDictionary *typing = [self.textView.typingAttributes mutableCopy] ?: [[self defaultArabicAttributes] mutableCopy];
    UIFont *cur = typing[NSFontAttributeName] ?: [self buildFontWithFamily:self.activeFontFamily size:19.0 bold:NO italic:NO];
    CGFloat size = MAX(12.0, MIN(48.0, cur.pointSize + delta));
    BOOL isB = ([cur.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL isI = ([cur.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
    if (toggleBold) isB = !isB;
    if (toggleItalic) isI = !isI;
    typing[NSFontAttributeName] = [self buildFontWithFamily:self.activeFontFamily size:size bold:isB italic:isI];
    self.textView.typingAttributes = typing;
}

- (void)toggleBold { [self modifySelectedFontWithBold:YES italic:NO sizeDelta:0]; }
- (void)toggleItalic { [self modifySelectedFontWithBold:NO italic:YES sizeDelta:0]; }
- (void)increaseFont { [self modifySelectedFontWithBold:NO italic:NO sizeDelta:2.0]; }
- (void)decreaseFont { [self modifySelectedFontWithBold:NO italic:NO sizeDelta:-2.0]; }

- (void)toggleUnderline {
    NSRange range = self.textView.selectedRange;
    if (range.length > 0) {
        NSTextStorage *storage = self.textView.textStorage;
        NSNumber *cur = [storage attribute:NSUnderlineStyleAttributeName atIndex:range.location effectiveRange:NULL];
        NSInteger next = (cur && cur.integerValue != NSUnderlineStyleNone) ? NSUnderlineStyleNone : NSUnderlineStyleSingle;

        [storage beginEditing];
        [storage addAttribute:NSUnderlineStyleAttributeName value:@(next) range:range];
        [storage endEditing];
    }
    NSMutableDictionary *typing = [self.textView.typingAttributes mutableCopy] ?: [[self defaultArabicAttributes] mutableCopy];
    NSNumber *curT = typing[NSUnderlineStyleAttributeName];
    NSInteger nextT = (curT && curT.integerValue != NSUnderlineStyleNone) ? NSUnderlineStyleNone : NSUnderlineStyleSingle;
    typing[NSUnderlineStyleAttributeName] = @(nextT);
    self.textView.typingAttributes = typing;
}

- (NSURL *)documentsDirectoryURL {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
}

- (void)saveAndShare {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"حفظ ومشاركة المستند" message:@"اختر صيغة الملف المطلوبة:" preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"ملف Word مع الجداول والصور (.docx)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptFilenameAndSaveWithExtension:@"docx"];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"مستند منسق (.rtf)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptFilenameAndSaveWithExtension:@"rtf"];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"نص عادي (.txt)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptFilenameAndSaveWithExtension:@"txt"];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.saveShareItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptFilenameAndSaveWithExtension:(NSString *)ext {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"اسم الملف" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.textAlignment = NSTextAlignmentRight;
        NSString *base = self.currentFileURL ? [[self.currentFileURL lastPathComponent] stringByDeletingPathExtension] : @"مستند_عربي";
        tf.text = base;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ ومشاركة" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"مستند_عربي";
        NSString *fullName = [NSString stringWithFormat:@"%@.%@", name, ext];
        NSURL *destURL = [[self documentsDirectoryURL] URLByAppendingPathComponent:fullName];
        NSAttributedString *snapshot = [self.textView.attributedText copy];
        NSString *plainSnapshot = [self.textView.text copy];

        [self setLoading:YES message:@"جاري حفظ المستند..."];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *err = nil;
            BOOL ok = NO;
            if ([ext isEqualToString:@"docx"]) {
                ok = [DocxHelper writeAttributedString:snapshot toDocxURL:destURL error:&err];
            } else if ([ext isEqualToString:@"rtf"]) {
                NSData *rtfData = [snapshot dataFromRange:NSMakeRange(0, snapshot.length) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:&err];
                if (rtfData) ok = [rtfData writeToURL:destURL options:NSDataWritingAtomic error:&err];
            } else {
                ok = [plainSnapshot writeToURL:destURL atomically:YES encoding:NSUTF8StringEncoding error:&err];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self setLoading:NO message:nil];
                if (ok) {
                    self.currentFileURL = destURL;
                    self.title = fullName;
                    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[destURL] applicationActivities:nil];
                    activity.popoverPresentationController.barButtonItem = self.saveShareItem;
                    [self presentViewController:activity animated:YES completion:nil];
                } else {
                    [self showMessage:@"خطأ في الحفظ" body:err.localizedDescription ?: @"فشل حفظ الملف"];
                }
            });
        });
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openDocList {
    NSURL *docsURL = [self documentsDirectoryURL];
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:docsURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"الملفات المحفوظة" message:@"يمكنك أيضاً فتح أي ملف .docx من Filza أو البريد باختيار ArabicOffice" preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSURL *fileURL in files) {
        NSString *ext = fileURL.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"docx"] || [ext isEqualToString:@"rtf"] || [ext isEqualToString:@"txt"]) {
            [sheet addAction:[UIAlertAction actionWithTitle:fileURL.lastPathComponent style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self openDocumentAtURL:fileURL];
            }]];
        }
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.openItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openDocumentAtURL:(NSURL *)url {
    NSString *ext = url.pathExtension.lowercaseString;
    NSDictionary *defaultAttrs = [self defaultArabicAttributes];

    [self setLoading:YES message:@"جاري فتح المستند..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        NSAttributedString *loaded = nil;

        if ([ext isEqualToString:@"docx"]) {
            loaded = [DocxHelper attributedStringFromDocxURL:url error:&err];
        } else if ([ext isEqualToString:@"rtf"]) {
            loaded = [[NSAttributedString alloc] initWithURL:url options:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} documentAttributes:nil error:&err];
        } else {
            NSString *txt = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
            if (txt) {
                loaded = [[NSAttributedString alloc] initWithString:txt attributes:defaultAttrs];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setLoading:NO message:nil];
            if (loaded) {
                self.textView.attributedText = loaded;
                self.currentFileURL = url;
                self.title = url.lastPathComponent;
            } else {
                [self showMessage:@"تعذر فتح الملف" body:err.localizedDescription ?: @"صيغة الملف غير مدعومة"];
            }
        });
    });
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) EditorViewController *editorVC;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.editorVC = [[EditorViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.editorVC];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options {
    if (url.isFileURL) {
        NSURL *dest = [[self.editorVC documentsDirectoryURL] URLByAppendingPathComponent:url.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:url toURL:dest error:nil];
        [self.editorVC openDocumentAtURL:dest];
        return YES;
    }
    return NO;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self application:application openURL:url options:@{}];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
