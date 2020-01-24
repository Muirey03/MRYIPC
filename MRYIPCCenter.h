@interface MRYIPCCenter : NSObject
@property (nonatomic, readonly) NSString* centerName;
+(instancetype)centerNamed:(NSString*)name;
-(void)registerMethod:(SEL)selector withTarget:(id)target;
-(id)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args;
-(void)callExternalVoidMethod:(SEL)method withArguments:(NSDictionary*)args;
-(void)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args completion:(void(^)(id))completionHandler;
@end
