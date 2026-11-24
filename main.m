#import <UIKit/UIKit.h>
#import "DocxHelper.h"

@interface EditorViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSURL *currentFileURL;
@property (nonatomic, strong) UIBarButtonItem *saveShareItem;
@property (nonatomic, strong) UIBarButtonItem *openItem;
- (void)openDocumentAtURL:(NSURL *)url;
@end

@implementation EditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"مستند_جديد.docx";

    UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithTitle:@"جديد" style:UIBarButtonItemStylePlain target:self action:@selector(newDoc)];
    self.openItem = [[UIBarButtonItem alloc] initWithTitle:@"فتح" style:UIBarButtonItemStylePlain target:self action:@selector(openDocList)];
    self.navigationItem.leftBarButtonItems = @[self.openItem, newItem];

    UIBarButtonItem *rtlItem = [[UIBarButtonItem alloc] initWithTitle:@"ضبط عربي RTL" style:UIBarButtonItemStylePlain target:self action:@selector(applyRTL)];
    self.saveShareItem = [[UIBarButtonItem alloc] initWithTitle:@"حفظ ومشاركة" style:UIBarButtonItemStyleDone target:self action:@selector(saveAndShare)];
    self.navigationItem.rightBarButtonItems = @[rtlItem, self.saveShareItem];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor whiteColor];
    self.textView.textContainerInset = UIEdgeInsetsMake(20, 24, 20, 24);
    self.textView.delegate = self;

    [self setupFormattingToolbar];
    [self.view addSubview:self.textView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];

    [self newDoc];
}

- (void)setupFormattingToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    UIBarButtonItem *hideKB = [[UIBarButtonItem alloc] initWithTitle:@"إخفاء الكيبورد" style:UIBarButtonItemStylePlain target:self.textView action:@selector(resignFirstResponder)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *fontMinus = [[UIBarButtonItem alloc] initWithTitle:@"خط -" style:UIBarButtonItemStylePlain target:self action:@selector(decreaseFont)];
    UIBarButtonItem *fontPlus = [[UIBarButtonItem alloc] initWithTitle:@"خط +" style:UIBarButtonItemStylePlain target:self action:@selector(increaseFont)];
    UIBarButtonItem *underline = [[UIBarButtonItem alloc] initWithTitle:@"تسطير U" style:UIBarButtonItemStylePlain target:self action:@selector(toggleUnderline)];
    UIBarButtonItem *italic = [[UIBarButtonItem alloc] initWithTitle:@"مائل I" style:UIBarButtonItemStylePlain target:self action:@selector(toggleItalic)];
    UIBarButtonItem *bold = [[UIBarButtonItem alloc] initWithTitle:@"عريض B" style:UIBarButtonItemStyleDone target:self action:@selector(toggleBold)];

    toolbar.items = @[hideKB, flex, fontMinus, fontPlus, underline, italic, bold];
    self.textView.inputAccessoryView = toolbar;
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
    UIFont *font = [UIFont fontWithName:@"ArialMT" size:19.0] ?: [UIFont systemFontOfSize:19.0];
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
    NSMutableAttributedString *attr = [self.textView.attributedText mutableCopy];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentRight;
    para.baseWritingDirection = NSWritingDirectionRightToLeft;
    [attr addAttribute:NSParagraphStyleAttributeName value:para range:NSMakeRange(0, attr.length)];
    self.textView.attributedText = attr;
    self.textView.typingAttributes = [self defaultArabicAttributes];
}

- (void)modifySelectedFontWithBold:(BOOL)toggleBold italic:(BOOL)toggleItalic sizeDelta:(CGFloat)delta {
    NSRange range = self.textView.selectedRange;
    if (range.length == 0) return;

    NSMutableAttributedString *attr = [self.textView.attributedText mutableCopy];
    [attr enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(UIFont *font, NSRange subRange, BOOL *stop) {
        UIFont *base = font ?: ([UIFont fontWithName:@"ArialMT" size:19.0] ?: [UIFont systemFontOfSize:19.0]);
        CGFloat size = MAX(12.0, MIN(48.0, base.pointSize + delta));
        BOOL isB = ([base.fontName rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound);
        BOOL isI = ([base.fontName rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound);
        if (toggleBold) isB = !isB;
        if (toggleItalic) isI = !isI;

        NSString *name = @"ArialMT";
        if (isB && isI) name = @"Arial-BoldItalicMT";
        else if (isB) name = @"Arial-BoldMT";
        else if (isI) name = @"Arial-ItalicMT";

        UIFont *newFont = [UIFont fontWithName:name size:size] ?: (isB ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size]);
        [attr addAttribute:NSFontAttributeName value:newFont range:subRange];
    }];
    self.textView.attributedText = attr;
    self.textView.selectedRange = range;
}

- (void)toggleBold { [self modifySelectedFontWithBold:YES italic:NO sizeDelta:0]; }
- (void)toggleItalic { [self modifySelectedFontWithBold:NO italic:YES sizeDelta:0]; }
- (void)increaseFont { [self modifySelectedFontWithBold:NO italic:NO sizeDelta:2.0]; }
- (void)decreaseFont { [self modifySelectedFontWithBold:NO italic:NO sizeDelta:-2.0]; }

- (void)toggleUnderline {
    NSRange range = self.textView.selectedRange;
    if (range.length == 0) return;
    NSMutableAttributedString *attr = [self.textView.attributedText mutableCopy];
    NSNumber *cur = [attr attribute:NSUnderlineStyleAttributeName atIndex:range.location effectiveRange:NULL];
    NSInteger next = (cur && cur.integerValue != NSUnderlineStyleNone) ? NSUnderlineStyleNone : NSUnderlineStyleSingle;
    [attr addAttribute:NSUnderlineStyleAttributeName value:@(next) range:range];
    self.textView.attributedText = attr;
    self.textView.selectedRange = range;
}

- (NSURL *)documentsDirectoryURL {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
}

- (void)saveAndShare {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"حفظ ومشاركة المستند" message:@"اختر صيغة الملف المطلوبة:" preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"ملف Word (.docx)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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

        NSError *err = nil;
        BOOL ok = NO;
        if ([ext isEqualToString:@"docx"]) {
            ok = [DocxHelper writeAttributedString:self.textView.attributedText toDocxURL:destURL error:&err];
        } else if ([ext isEqualToString:@"rtf"]) {
            NSData *rtfData = [self.textView.attributedText dataFromRange:NSMakeRange(0, self.textView.attributedText.length) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:&err];
            if (rtfData) ok = [rtfData writeToURL:destURL options:NSDataWritingAtomic error:&err];
        } else {
            ok = [self.textView.text writeToURL:destURL atomically:YES encoding:NSUTF8StringEncoding error:&err];
        }

        if (ok) {
            self.currentFileURL = destURL;
            self.title = fullName;
            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[destURL] applicationActivities:nil];
            activity.popoverPresentationController.barButtonItem = self.saveShareItem;
            [self presentViewController:activity animated:YES completion:nil];
        } else {
            [self showMessage:@"خطأ في الحفظ" body:err.localizedDescription ?: @"فشل حفظ الملف"];
        }
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
    NSError *err = nil;
    NSAttributedString *loaded = nil;

    if ([ext isEqualToString:@"docx"]) {
        loaded = [DocxHelper attributedStringFromDocxURL:url error:&err];
    } else if ([ext isEqualToString:@"rtf"]) {
        loaded = [[NSAttributedString alloc] initWithURL:url options:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} documentAttributes:nil error:&err];
    } else {
        NSString *txt = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&err];
        if (txt) {
            loaded = [[NSAttributedString alloc] initWithString:txt attributes:[self defaultArabicAttributes]];
        }
    }

    if (loaded) {
        self.textView.attributedText = loaded;
        self.currentFileURL = url;
        self.title = url.lastPathComponent;
    } else {
        [self showMessage:@"تعذر فتح الملف" body:err.localizedDescription ?: @"صيغة الملف غير مدعومة"];
    }
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
