#import <UIKit/UIKit.h>

@interface EditorViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSString *currentFileName;
- (void)loadDocumentFromURL:(NSURL *)url;
@end

@implementation EditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.currentFileName = @"مستند_جديد.rtf";
    self.title = self.currentFileName;

    // أزرار الشريط العلوي
    UIBarButtonItem *newBtn = [[UIBarButtonItem alloc] initWithTitle:@"جديد" style:UIBarButtonItemStylePlain target:self action:@selector(newDocument)];
    UIBarButtonItem *openBtn = [[UIBarButtonItem alloc] initWithTitle:@"فتح" style:UIBarButtonItemStylePlain target:self action:@selector(openDocumentList:)];
    self.navigationItem.leftBarButtonItems = @[newBtn, openBtn];

    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithTitle:@"حفظ ومشاركة" style:UIBarButtonItemStyleDone target:self action:@selector(saveAndShare:)];
    UIBarButtonItem *rtlBtn = [[UIBarButtonItem alloc] initWithTitle:@"ضبط عربي RTL" style:UIBarButtonItemStylePlain target:self action:@selector(applyArabicRTL)];
    self.navigationItem.rightBarButtonItems = @[exportBtn, rtlBtn];

    // محرر النصوص الرئيسي
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont systemFontOfSize:18.0];
    self.textView.textAlignment = NSTextAlignmentRight;
    self.textView.allowsEditingTextAttributes = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(20, 20, 20, 20);
    self.textView.delegate = self;

    // شريط أدوات التنسيق فوق لوحة المفاتيح
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    UIBarButtonItem *boldBtn = [[UIBarButtonItem alloc] initWithTitle:@"عريض B" style:UIBarButtonItemStylePlain target:self action:@selector(toggleBold)];
    UIBarButtonItem *italicBtn = [[UIBarButtonItem alloc] initWithTitle:@"مائل I" style:UIBarButtonItemStylePlain target:self action:@selector(toggleItalic)];
    UIBarButtonItem *underBtn = [[UIBarButtonItem alloc] initWithTitle:@"تسطير U" style:UIBarButtonItemStylePlain target:self action:@selector(toggleUnderline)];
    UIBarButtonItem *incFont = [[UIBarButtonItem alloc] initWithTitle:@"خط +" style:UIBarButtonItemStylePlain target:self action:@selector(increaseFont)];
    UIBarButtonItem *decFont = [[UIBarButtonItem alloc] initWithTitle:@"خط -" style:UIBarButtonItemStylePlain target:self action:@selector(decreaseFont)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *hideKb = [[UIBarButtonItem alloc] initWithTitle:@"إخفاء الكيبورد" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];

    toolbar.items = @[boldBtn, italicBtn, underBtn, incFont, decFont, flex, hideKb];
    self.textView.inputAccessoryView = toolbar;

    [self.view addSubview:self.textView];
    [self applyArabicRTL];

    // مراقبة لوحة المفاتيح لتجنب تغطية النص
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets insets = self.textView.contentInset;
    insets.bottom = kbFrame.size.height + 10;
    self.textView.contentInset = insets;
    self.textView.scrollIndicatorInsets = insets;
}

- (void)keyboardWillHide:(NSNotification *)note {
    UIEdgeInsets insets = self.textView.contentInset;
    insets.bottom = 0;
    self.textView.contentInset = insets;
    self.textView.scrollIndicatorInsets = insets;
}

- (void)dismissKeyboard {
    [self.textView resignFirstResponder];
}

- (void)newDocument {
    self.textView.text = @"";
    self.currentFileName = @"مستند_جديد.rtf";
    self.title = self.currentFileName;
    [self applyArabicRTL];
}

- (void)applyArabicRTL {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentRight;
    style.baseWritingDirection = NSWritingDirectionRightToLeft;

    NSMutableDictionary *typingAttrs = [self.textView.typingAttributes mutableCopy];
    typingAttrs[NSParagraphStyleAttributeName] = style;
    if (!typingAttrs[NSFontAttributeName]) {
        typingAttrs[NSFontAttributeName] = [UIFont systemFontOfSize:18.0];
    }
    self.textView.typingAttributes = typingAttrs;

    if (self.textView.attributedText.length > 0) {
        NSMutableAttributedString *attrStr = [self.textView.attributedText mutableCopy];
        NSRange range = self.textView.selectedRange.length > 0 ? self.textView.selectedRange : NSMakeRange(0, attrStr.length);
        [attrStr addAttribute:NSParagraphStyleAttributeName value:style range:range];
        self.textView.attributedText = attrStr;
    }
}

- (void)toggleTrait:(UIFontDescriptorSymbolicTraits)trait {
    NSRange range = self.textView.selectedRange;
    if (range.length == 0) return;

    NSMutableAttributedString *attrStr = [self.textView.attributedText mutableCopy];
    [attrStr enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(UIFont *font, NSRange subRange, BOOL *stop) {
        if (!font) font = [UIFont systemFontOfSize:18.0];
        UIFontDescriptorSymbolicTraits existing = font.fontDescriptor.symbolicTraits;
        UIFontDescriptorSymbolicTraits updated = (existing & trait) ? (existing & ~trait) : (existing | trait);
        UIFontDescriptor *desc = [font.fontDescriptor fontDescriptorWithSymbolicTraits:updated];
        if (desc) {
            UIFont *newFont = [UIFont fontWithDescriptor:desc size:font.pointSize];
            [attrStr addAttribute:NSFontAttributeName value:newFont range:subRange];
        }
    }];
    self.textView.attributedText = attrStr;
    self.textView.selectedRange = range;
}

- (void)toggleBold { [self toggleTrait:UIFontDescriptorTraitBold]; }
- (void)toggleItalic { [self toggleTrait:UIFontDescriptorTraitItalic]; }

- (void)toggleUnderline {
    NSRange range = self.textView.selectedRange;
    if (range.length == 0) return;
    NSMutableAttributedString *attrStr = [self.textView.attributedText mutableCopy];
    NSNumber *current = [attrStr attribute:NSUnderlineStyleAttributeName atIndex:range.location effectiveRange:nil];
    NSNumber *next = (current && current.integerValue > 0) ? @(NSUnderlineStyleNone) : @(NSUnderlineStyleSingle);
    [attrStr addAttribute:NSUnderlineStyleAttributeName value:next range:range];
    self.textView.attributedText = attrStr;
    self.textView.selectedRange = range;
}

- (void)changeFontSizeBy:(CGFloat)delta {
    NSRange range = self.textView.selectedRange.length > 0 ? self.textView.selectedRange : NSMakeRange(0, self.textView.attributedText.length);
    if (range.length == 0) return;
    NSMutableAttributedString *attrStr = [self.textView.attributedText mutableCopy];
    [attrStr enumerateAttribute:NSFontAttributeName inRange:range options:0 usingBlock:^(UIFont *font, NSRange subRange, BOOL *stop) {
        if (!font) font = [UIFont systemFontOfSize:18.0];
        CGFloat newSize = MAX(12.0, MIN(48.0, font.pointSize + delta));
        UIFont *newFont = [font fontWithSize:newSize];
        [attrStr addAttribute:NSFontAttributeName value:newFont range:subRange];
    }];
    self.textView.attributedText = attrStr;
    self.textView.selectedRange = range;
}

- (void)increaseFont { [self changeFontSizeBy:2.0]; }
- (void)decreaseFont { [self changeFontSizeBy:-2.0]; }

- (NSString *)documentsDirectory {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)loadDocumentFromURL:(NSURL *)url {
    if (!url) return;
    NSError *error = nil;
    NSDictionary *options = @{};
    NSAttributedString *doc = [[NSAttributedString alloc] initWithURL:url options:options documentAttributes:nil error:&error];

    if (doc) {
        self.textView.attributedText = doc;
        NSString *baseName = [[url.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@"_معدل.rtf"];
        self.currentFileName = baseName;
        self.title = self.currentFileName;
    } else {
        NSString *plain = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (plain) {
            self.textView.text = plain;
            [self applyArabicRTL];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر فتح الملف" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)openDocumentList:(UIBarButtonItem *)sender {
    NSString *docsDir = [self documentsDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docsDir error:nil];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"المستندات المحفوظة" message:@"اختر ملفاً لفتحه وتعديله" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *file in files) {
        if ([file isEqualToString:@"Inbox"]) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:file style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *fileURL = [NSURL fileURLWithPath:[docsDir stringByAppendingPathComponent:file]];
            [self loadDocumentFromURL:fileURL];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)saveAndShare:(UIBarButtonItem *)sender {
    NSString *docsDir = [self documentsDirectory];
    NSString *savePath = [docsDir stringByAppendingPathComponent:self.currentFileName];
    NSURL *saveURL = [NSURL fileURLWithPath:savePath];

    NSRange fullRange = NSMakeRange(0, self.textView.attributedText.length);
    NSDictionary *attrs = @{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType};
    NSData *rtfData = [self.textView.attributedText dataFromRange:fullRange documentAttributes:attrs error:nil];

    if (rtfData) {
        [rtfData writeToURL:saveURL atomically:YES];
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[saveURL] applicationActivities:nil];
        activity.popoverPresentationController.barButtonItem = sender;
        [self presentViewController:activity animated:YES completion:nil];
    }
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

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
    [self.editorVC loadDocumentFromURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    [self.editorVC loadDocumentFromURL:url];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
