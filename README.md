# MRYIPC
### Easy-to-use iOS IPC without the need for RocketBootstrap

MRYIPC is an easy-to-use IPC (inter-process communication) mechanism for jailbroken devices (although it will also work on unjailbroken devices) that eliminates the need for RocketBootstrap.

`MRYIPCCenter` is similar in API to `CPDistributedMessagingCenter`, so it shouldn't be too challenging to replace current `CPDistributedMessagingCenter` implementations with `MRYIPCCenter`.

## How to use
To use MRYIPC, copy `MRYIPCCenter.h` to `$THEOS/include` and `usr/lib/libmryipc.dylib` to `$THEOS/lib/` and/or `var/jb/usr/lib/libmryipc.dylib` to `$THEOS/lib/iphone/rootless/`. Then you can add `XXX_LIBRARIES = mryipc` to your Makefile and `#import <MRYIPCCenter.h>` into any source files you want to use it in. Then add `Depends: com.muirey03.libmryipc` to your control file.

An example usage can be seen in ExampleClient and ExampleServer in this repository.

### The client
First, create the client center:

	MRYIPCCenter* center = [%c(MRYIPCCenter) centerNamed:@"com.muirey03.MRYExampleServer"];

Then, go ahead and call any method you like:

	NSNumber* result = [center callExternalMethod:@selector(addNumbers:) withArguments:@{@"value1" : @5, @"value2" : @7}];

`MRYIPCCenter` provides 3 ways to call methods on the center:

	//asynchronously call a void method
	-(void)callExternalVoidMethod:(SEL)method withArguments:(id)args;
	//synchronously call a method and recieve the return value
	-(id)callExternalMethod:(SEL)method withArguments:(id)args;
	//asynchronously call a method and receive the return value in the completion handler
	-(void)callExternalMethod:(SEL)method withArguments:(id)args completion:(void(^)(id))completionHandler;

Please note that the arguments and return value type must be one that can be stored in a plist (`NSString*`, `NSNumber*`, `NSData*`, `NSArray*` or `NSDictionary*`).

### The server
**IMPORTANT NOTE:** Only one server is allowed for any given name. You cannot create 2 servers in 2 different processes with the same name, that is illegal, and will cause the second process to crash.

Again, start by creating a sever center with the same name as the client (you'll need to store a reference somewhere to stop it being deallocated):

	MRYIPCCenter* center = [%c(MRYIPCCenter) centerNamed:@"com.muirey03.MRYExampleServer"];

Then register any methods you want to make external:

	[center addTarget:self action:@selector(addNumbers:)];

Then just implement the methods and let MRYIPC handle the rest:

	-(NSNumber*)addNumbers:(NSDictionary*)args
	{
		NSInteger value1 = [args[@"value1"] integerValue];
		NSInteger value2 = [args[@"value2"] integerValue];
		return @(value1 + value2);
	}

MRYIPC also allows for block-based servers for more simple callbacks where you don't necessarily need an object to act as the server:

	static MRYIPCCenter* center;

	%ctor
	{
		center = [MRYIPCCenter centerNamed:@"com.muirey03.MRYExampleServer"];
		[center addTarget:^NSNumber*(NSDictionary* args){
			NSInteger value1 = [args[@"value1"] integerValue];
			NSInteger value2 = [args[@"value2"] integerValue];
			return @(value1 + value2);
		} forSelector:@selector(addNumbers:)];
	}

## Credits
Feel free to follow me on Twitter [@Muirey03](https://twitter.com/muirey03). If you have any contributions you want to make to this, please submit a Pull Request.
