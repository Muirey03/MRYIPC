# MRYIPC
### Easy-to-use iOS IPC without the need for RocketBootstrap

MRYIPC is an easy-to-use IPC (inter-process communication) mechanism for jailbroken devices (although it will also work on unjailbroken devices) that eliminated the need for RocketBootstrap.

`MRYIPCCenter` is similar in API to `CPDistributedMessagingCenter`, so it shouldn't be too challenging to replace current `CPDistributedMessagingCenter` implementations with `MRYIPCCenter`.

## How to use
To use MRYIPC, copy `MRYIPCCenter.h` to `$THEOS/include` and `usr/lib/libmryipc.dylib` to `$THEOS/lib`. Then you can add `XXX_LIBRARIES = mryipc` to your Makefile and `#import "MRYIPCCenter.h"` into any source files you want to use it in.

An example usage can be seen in ExampleClient and ExampleServer in this repository.

### The client
First, create the client center:

	MRYIPCCenter* center = [MRYIPCCenter centerNamed:@"com.muirey03.MRYExampleServer"];
Then, go ahead and call any method you like:

	NSNumber* result = [center callExternalMethod:@selector(addNumbers:) withArguments:@{@"value1" : @5, @"value2" : @7}];

`MRYIPCCenter` provides 3 ways to call methods on the center:

	//asynchronously call a void method
	-(void)callExternalVoidMethod:(SEL)method withArguments:(NSDictionary*)args;
	//synchronously call a method and recieve the return value
	-(id)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args;
	//asynchronously call a method and receive the return value in the completion handler
	-(void)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args completion:(void(^)(id))completionHandler;

### The server
Again, start by creating a sever center with the same name as the client (you'll need to store a reference somewhere to stop it being deallocated):

	MRYIPCCenter* center = [MRYIPCCenter centerNamed:@"com.muirey03.MRYExampleServer"];
	
Then register any methods you want to make external:

	[center addTarget:self action:@selector(addNumbers:)];

Then just implement the methods and let MRYIPC handle the rest:

	-(NSNumber*)addNumbers:(NSDictionary*)args
	{
		NSInteger value1 = [args[@"value1"] integerValue];
		NSInteger value2 = [args[@"value2"] integerValue];
		return @(value1 + value2);
	}

## Credits
Feel free to follow me on Twitter [@Muirey03](https://twitter.com/muirey03). If you have any contributions you want to make to this, please submit a Pull Request.