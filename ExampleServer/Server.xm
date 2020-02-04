#import "MRYIPCCenter.h"

@interface MRYExampleServer : NSObject
@end

@implementation MRYExampleServer
{
	MRYIPCCenter* _center;
}

+(void)load
{
	[self sharedInstance];
}

+(instancetype)sharedInstance
{
	static dispatch_once_t onceToken = 0;
	__strong static MRYExampleServer* sharedInstance = nil;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

-(instancetype)init
{
	if ((self = [super init]))
	{
		_center = [MRYIPCCenter centerNamed:@"com.muirey03.MRYExampleServer"];
		[_center addTarget:self action:@selector(addNumbers:)];
		NSLog(@"[MRYIPCExample] running server in %@", [NSProcessInfo processInfo].processName);
	}
	return self;
}

-(NSNumber*)addNumbers:(NSDictionary*)args
{
	NSInteger value1 = [args[@"value1"] integerValue];
	NSInteger value2 = [args[@"value2"] integerValue];
	return @(value1 + value2);
}
@end
