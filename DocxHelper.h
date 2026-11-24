#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DocxHelper : NSObject

+ (NSAttributedString *)attributedStringFromDocxURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)writeAttributedString:(NSAttributedString *)attrStr toDocxURL:(NSURL *)url error:(NSError **)error;

@end
