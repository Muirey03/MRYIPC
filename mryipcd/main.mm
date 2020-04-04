@import Foundation;

#include <notify.h>
#include <mach/mach.h>
#import <IOSurface/IOSurfaceRef.h>

@interface MRYIPCObserver : NSObject
@property (nonatomic, strong) NSString* centerName;
@property (nonatomic, assign) pid_t pid;
+(instancetype)observerWithCenterName:(NSString*)centerName pid:(pid_t)pid;
@end

@implementation MRYIPCObserver
+(instancetype)observerWithCenterName:(NSString*)centerName pid:(pid_t)pid
{
	MRYIPCObserver* observer = [self new];
	observer.centerName = centerName;
	observer.pid = pid;
	return observer;
}
@end

@interface MRYIPCDaemon : NSObject
{
	NSMutableArray* _tokens;
	NSMutableDictionary* _observers;
}
-(void)addObserverForName:(NSString*)name selector:(SEL)sel;
-(void)registerMethod:(NSString*)name withState:(uint64_t)state;
-(pid_t)pidForState:(uint64_t)state;
-(mach_port_t)surfacePortForState:(uint64_t)state;
-(NSDictionary*)dictionaryForSurface:(mach_port_t)surfacePort;
-(mach_port_name_t)insertPort:(mach_port_t)port intoProcessWithPid:(pid_t)pid;
-(void)sendNotificationWithName:(NSString*)name state:(uint64_t)state;
@end

@implementation MRYIPCDaemon
+(void)load
{
	[self sharedInstance];
}

+(id)sharedInstance
{
	static dispatch_once_t once = 0;
	__strong static id sharedInstance = nil;
	dispatch_once(&once, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

-(instancetype)init
{
	if ((self = [super init]))
    {
		_tokens = [NSMutableArray new];
		_observers = [NSMutableDictionary new];

		[self addObserverForName:@"com.muirey03.libmryipc-registerMethod" selector:@selector(registerMethod:withState:)];
		[self addObserverForName:@"com.muirey03.libmryipc-removeObserver" selector:@selector(removeObserver:withState:)];
	}
    return self;
}

-(void)addObserverForName:(NSString*)name selector:(SEL)sel
{
	const char* cName = name.UTF8String;
	int notifyToken;
	__weak __typeof(self) weakSelf = self;
	notify_register_dispatch(cName, &notifyToken, dispatch_get_main_queue(), ^(int token){
		NSMethodSignature* signature = [weakSelf methodSignatureForSelector:sel];
		NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
		invocation.target = weakSelf;
		invocation.selector = sel;
		id nameObject = name;
		if (signature.numberOfArguments > 2)
			[invocation setArgument:&nameObject atIndex:2];
		if (signature.numberOfArguments > 3)
		{
			uint64_t state;
			notify_get_state(token, &state);
			[invocation setArgument:&state atIndex:3];
		}
		[invocation invoke];
	});
	[_tokens addObject:@(notifyToken)];
}

-(void)registerMethod:(NSString*)name withState:(uint64_t)state
{
	pid_t pid = [self pidForState:state];
	mach_port_t surfacePort = [self surfacePortForState:state];
	NSDictionary* dict = [self dictionaryForSurface:surfacePort];
	if (dict)
	{
		NSString* messageName = dict[@"messageName"];
		if (messageName)
		{
			_observers[messageName] = [MRYIPCObserver observerWithCenterName:dict[@"centerName"] pid:pid];
			[self addObserverForName:messageName selector:@selector(messageRequestReceived:withState:)];
		}
	}
	if (surfacePort)
		mach_port_deallocate(mach_task_self(), surfacePort);
}

-(void)removeObserver:(NSString*)name withState:(uint64_t)state
{
	pid_t pid = (pid_t)state;
	for (unsigned i = 0; i < _observers.count; i++)
	{
		NSString* messageName = _observers.allKeys[i];
		if ([_observers[messageName] pid] == pid)
		{
			[_observers removeObjectForKey:messageName];
			i--;
		}
	}
}

-(pid_t)pidForState:(uint64_t)state
{
	return (pid_t)(state >> 32);
}

-(mach_port_t)surfacePortForState:(uint64_t)state
{
	pid_t pid = [self pidForState:state];
	mach_port_name_t portName = (mach_port_name_t)(state & UINT32_MAX);
	if (portName == MACH_PORT_NULL) return MACH_PORT_NULL;
	mach_port_t task = MACH_PORT_NULL;
	task_for_pid(mach_task_self(), pid, &task);
	if (task == MACH_PORT_NULL) return MACH_PORT_NULL;
	mach_msg_type_name_t type;
	mach_port_t surfacePort = MACH_PORT_NULL;
	mach_port_extract_right(task, portName,  MACH_MSG_TYPE_PORT_SEND, &surfacePort, &type);
	mach_port_deallocate(mach_task_self(), task);
	return surfacePort;
}

-(NSDictionary*)dictionaryForSurface:(mach_port_t)surfacePort
{
	if (surfacePort == MACH_PORT_NULL) return nil;
	NSDictionary* dict = nil;
	IOSurfaceRef surface = IOSurfaceLookupFromMachPort(surfacePort);
	if (surface)
	{
		void* addr = IOSurfaceGetBaseAddress(surface);
		size_t size = IOSurfaceGetAllocSize(surface);
		NSData* surfaceData = [NSData dataWithBytesNoCopy:addr length:size freeWhenDone:NO];
		NSError* err;
		NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
		dict = [NSPropertyListSerialization propertyListWithData:surfaceData options:NSPropertyListImmutable format:&format error:&err];
		CFRelease(surface);
	}
	return dict;
}

-(void)messageRequestReceived:(NSString*)name withState:(uint64_t)state
{
	pid_t sourcePid = [self pidForState:state];
	mach_port_t surfacePort = [self surfacePortForState:state];
	NSDictionary* dict = [self dictionaryForSurface:surfacePort];
	MRYIPCObserver* observer = _observers[name];
	if (dict && observer)
	{
		//insert surface into target:
		pid_t targetPid = observer.pid;
		mach_port_name_t targetPort = [self insertPort:surfacePort intoProcessWithPid:targetPid];

		NSString* replyUUID = dict[@"replyUUID"];
		if (replyUUID.length)
		{
			NSString* replyName = [NSString stringWithFormat:@"%@-reply-%@", dict[@"name"], replyUUID];
			int notifyToken;
			notify_register_dispatch(replyName.UTF8String, &notifyToken, dispatch_get_main_queue(), ^(int token){
				uint64_t state;
				notify_get_state(token, &state);
				notify_cancel(token);
				mach_port_t replySurfacePort = [self surfacePortForState:state];
				mach_port_name_t targetReplyPort = [self insertPort:replySurfacePort intoProcessWithPid:sourcePid];
				[self sendNotificationWithName:[NSString stringWithFormat:@"%@-client", replyName] state:(uint64_t)targetReplyPort];
				if (replySurfacePort != MACH_PORT_NULL)
					mach_port_deallocate(mach_task_self(), replySurfacePort);
			});
		}

		NSString* messageName = [NSString stringWithFormat:@"MRYIPCCenter-%@-messageReceived", observer.centerName];
		[self sendNotificationWithName:messageName state:(uint64_t)targetPort];
	}
	if (surfacePort)
		mach_port_deallocate(mach_task_self(), surfacePort);
}

-(mach_port_name_t)insertPort:(mach_port_t)port intoProcessWithPid:(pid_t)pid
{
	if (port == MACH_PORT_NULL) return MACH_PORT_NULL;
	mach_port_t task = MACH_PORT_NULL;
	task_for_pid(mach_task_self(), pid, &task);
	if (task == MACH_PORT_NULL) return MACH_PORT_NULL;

	//find an unused port name:
	mach_port_name_t targetName = MACH_PORT_NULL;
	mach_port_allocate(task, MACH_PORT_RIGHT_DEAD_NAME, &targetName);
	mach_port_deallocate(task, targetName);

	kern_return_t kr = mach_port_insert_right(task, targetName, port, MACH_MSG_TYPE_PORT_SEND);
	if (kr != KERN_SUCCESS)
		return MACH_PORT_NULL;
	return targetName;
}

-(void)sendNotificationWithName:(NSString*)name state:(uint64_t)state
{
	const char* cName = name.UTF8String;
	int token;
	notify_register_check(cName, &token);
	notify_set_state(token, state);
	notify_post(cName);
	notify_cancel(token);
}

-(void)dealloc
{
	for (id token in _tokens)
		notify_cancel([token intValue]);
}
@end

int main(int argc, char** argv, char** envp)
{
	@autoreleasepool
	{
		NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
		for (;;)
			[runLoop run];
		return 0;
	}
}
