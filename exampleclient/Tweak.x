#import <MRYIPCCenter.h>

%ctor
{
	NSLog(@"[MRYIPCExample] running client in %@", [NSProcessInfo processInfo].processName);
	NSLog(@"[MRYIPCExample] client is attempting to call addNumbers:");
	MRYIPCCenter* center = [MRYIPCCenter centerNamed:@"com.muirey03.MRYExampleServer"];
	NSNumber* result = [center callExternalMethod:@selector(addNumbers:) withArguments:@{@"value1" : @5, @"value2" : @7}];
	NSLog(@"[MRYIPCExample] 5 + 7 = %@", result);
}
