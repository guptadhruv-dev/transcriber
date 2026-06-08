#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCExceptionCatcher : NSObject

+ (nullable NSError *)catchException:(NS_NOESCAPE void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
