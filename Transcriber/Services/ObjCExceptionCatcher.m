#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (nullable NSError *)catchException:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        NSString *message = exception.reason ?: exception.name;
        return [NSError errorWithDomain:@"AudioRecorder.ObjCException"
                                   code:-100
                               userInfo:@{ NSLocalizedDescriptionKey: message }];
    }
}

@end
