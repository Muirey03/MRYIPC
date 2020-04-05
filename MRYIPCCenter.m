@import Foundation;
#include <mach/mach.h>
#include <notify.h>
#import <IOSurface/IOSurfaceRef.h>
#import "MRYIPCCenter.h"

#define THROW(...) [self _throwException:[NSString stringWithFormat:__VA_ARGS__] fromMethod:_cmd]

@interface _MRYIPCMethod : NSObject
@property (nonatomic, readonly) id target;
@property (nonatomic, readonly) SEL selector;
-(instancetype)initWithTarget:(id)target selector:(SEL)selector;
@end

@implementation _MRYIPCMethod
-(instancetype)initWithTarget:(id)target selector:(SEL)selector
{
	if ((self = [self init]))
	{
		_target = target;
		_selector = selector;
	}
	return self;
}
@end

@interface MRYIPCCenter ()
-(instancetype)initWithName:(NSString*)name;
-(void)_throwException:(NSString*)msg fromMethod:(SEL)method;
-(NSString*)_messageNameForSelector:(SEL)selector;
-(NSString*)_messageReplyNameForSelector:(SEL)selector uuid:(NSString*)uuid;
-(void)_sendNotificationWithName:(NSString*)name state:(uint64_t)state;
-(void)_addObserverForName:(NSString*)name selector:(SEL)sel;
-(IOSurfaceRef)_createSurfaceForDictionary:(NSDictionary*)dict;
-(NSDictionary*)_dictionaryForSurface:(IOSurfaceRef)surface;
@end

@implementation MRYIPCCenter
{
	NSMutableDictionary<NSString*, _MRYIPCMethod*>* _methods;
	NSMutableArray* _observerTokens;
}

+(instancetype)centerNamed:(NSString*)name
{
	return [[self alloc] initWithName:name];
}

-(instancetype)initWithName:(NSString*)name
{
	if ((self = [self init]))
	{
		if (!name.length)
			THROW(@"a center name must be supplied");
		_centerName = name;
		_methods = [NSMutableDictionary new];
		_observerTokens = [NSMutableArray new];

		[self _addObserverForName:[self _messageNameForString:@"messageReceived"] selector:@selector(_messageReceived:withState:)];
	}
	return self;
}

-(void)addTarget:(id)target action:(SEL)action
{
	if (!action || !strlen(sel_getName(action)))
		THROW(@"method cannot be null");
	if (!target)
		THROW(@"target cannot be null");
	
	NSString* messageName = [self _messageNameForSelector:action];
	if (_methods[messageName])
		THROW(@"method already registered: %@", NSStringFromSelector(action));
	
	IOSurfaceRef surface = [self _createSurfaceForDictionary:@{@"centerName" : _centerName, @"messageName" : messageName}];
	[self _sendNotificationWithName:@"com.muirey03.libmryipc-registerMethod" state:[self _stateForSurface:surface]];
	
	//wait for confirmation from server:
	NSString* replyMessageName = [messageName stringByAppendingString:@"-registered"];
	int notifyToken;
	__block dispatch_queue_t replyQueue = dispatch_queue_create("com.muirey03.libMRYIPC-registerReplyQueue", NULL);
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	notify_register_dispatch(replyMessageName.UTF8String, &notifyToken, replyQueue, ^(int token){
		notify_cancel(token);
		dispatch_semaphore_signal(sema);
		replyQueue = nil;
	});
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	CFRelease(surface);
	
	_MRYIPCMethod* method = [[_MRYIPCMethod alloc] initWithTarget:target selector:action];
	_methods[messageName] = method;
}

//deprecated
-(void)registerMethod:(SEL)selector withTarget:(id)target
{
	[self addTarget:target action:selector];
}

-(void)callExternalVoidMethod:(SEL)method withArguments:(NSDictionary*)args
{
	[self callExternalMethod:method withArguments:args completion:nil];
}

-(id)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args
{
	__block id returnValue = nil;
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	[self callExternalMethod:method withArguments:args completion:^(id ret){
		returnValue = ret;
		dispatch_semaphore_signal(sema);
	}];
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	return returnValue;
}

-(void)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args completion:(void(^)(id))completionHandler
{
	static dispatch_semaphore_t sema;
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		sema = dispatch_semaphore_create(1);
	});
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

	NSString* replyUUID = [NSUUID UUID].UUIDString;
	NSString* messageName = [self _messageNameForSelector:method];
	IOSurfaceRef messageSurface = NULL;

	NSString* replyMessageName = [NSString stringWithFormat:@"%@-client", [self _messageReplyNameForSelector:method uuid:replyUUID]];
	int notifyToken;
	__block dispatch_queue_t replyQueue = dispatch_queue_create("com.muirey03.libMRYIPC-replyQueue", NULL);
	notify_register_dispatch(replyMessageName.UTF8String, &notifyToken, replyQueue, ^(int token){
		uint64_t state;
		notify_get_state(token, &state);
		notify_cancel(token);
		mach_port_t surfacePort = (mach_port_t)state;
		IOSurfaceRef userInfoSurface = IOSurfaceLookupFromMachPort(surfacePort);
		NSDictionary* userInfo = nil;
		if (userInfoSurface)
		{
			userInfo = [self _dictionaryForSurface:userInfoSurface];
			CFRelease(userInfoSurface);
			mach_port_deallocate(mach_task_self(), surfacePort);
		}
		if (completionHandler)
			completionHandler(userInfo[@"returnValue"]);
		replyQueue = nil;
		if (messageSurface)
			CFRelease(messageSurface);
		dispatch_semaphore_signal(sema);
	});

	//create userInfo:
	NSMutableDictionary* userInfo = [NSMutableDictionary new];
	userInfo[@"name"] = messageName;
	userInfo[@"replyUUID"] = replyUUID;
	if (args)
		userInfo[@"args"] = args;
	
	//create surface:
	messageSurface = [self _createSurfaceForDictionary:userInfo];

	//send notification:
	[self _sendNotificationWithName:messageName state:[self _stateForSurface:messageSurface]];
}

-(NSString*)_messageNameForString:(NSString*)str
{
	return [NSString stringWithFormat:@"MRYIPCCenter-%@-%@", _centerName, str];
}

-(NSString*)_messageNameForSelector:(SEL)selector
{
	return [self _messageNameForString:NSStringFromSelector(selector)];
}

-(NSString*)_messageReplyNameForSelector:(SEL)selector uuid:(NSString*)uuid
{
	return [self _messageNameForString:[NSString stringWithFormat:@"%@-reply-%@", NSStringFromSelector(selector), uuid]];
}

-(IOSurfaceRef)_createSurfaceForDictionary:(NSDictionary*)dict
{
	NSError* err = nil;
	NSData* dictData = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:kNilOptions error:&err];
	size_t dictSize = dictData.length;
	const void* dictBytes = dictData.bytes;
	if (err || !dictBytes)
		THROW(@"Failed to serialize dictionary with error: %@", err);
	NSDictionary* properties = @{
		(__bridge NSString*)kIOSurfaceAllocSize : @(dictSize)
	};
	IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
	
	if (!surface)
		THROW(@"Failed to create surface for dictionary");
	if (IOSurfaceGetAllocSize(surface) < dictSize)
		THROW(@"Surface too small for dictionary");
	memcpy(IOSurfaceGetBaseAddress(surface), dictBytes, dictSize);
	return surface;
}

-(uint64_t)_stateForSurface:(IOSurfaceRef)surface
{
	return ((uint64_t)getpid() << 32) | (uint64_t)IOSurfaceCreateMachPort(surface);
}

-(void)_sendNotificationWithName:(NSString*)name state:(uint64_t)state
{
	const char* cName = name.UTF8String;
	int token;
	notify_register_check(cName, &token);
	notify_set_state(token, state);
	notify_post(cName);
	notify_cancel(token);
}

-(void)_addObserverForName:(NSString*)name selector:(SEL)sel
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
	[_observerTokens addObject:@(notifyToken)];
}

-(NSDictionary*)_dictionaryForSurface:(IOSurfaceRef)surface
{
	NSDictionary* dict = nil;
	if (surface)
	{
		void* addr = IOSurfaceGetBaseAddress(surface);
		size_t size = IOSurfaceGetAllocSize(surface);
		NSData* surfaceData = [NSData dataWithBytesNoCopy:addr length:size freeWhenDone:NO];
		NSError* err;
		NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
		dict = [NSPropertyListSerialization propertyListWithData:surfaceData options:NSPropertyListImmutable format:&format error:&err];
	}
	return dict;
}

-(void)_messageReceived:(NSString*)name withState:(uint64_t)state
{
	mach_port_t surfacePort = (mach_port_t)state;
	IOSurfaceRef userInfoSurface = IOSurfaceLookupFromMachPort(surfacePort);
	if (userInfoSurface)
	{
		NSDictionary* userInfo = [self _dictionaryForSurface:userInfoSurface];
		CFRelease(userInfoSurface);
		mach_port_deallocate(mach_task_self(), surfacePort);

		NSString* messageName = userInfo[@"name"];
		_MRYIPCMethod* method = _methods[messageName];
		if (!method)
			THROW(@"unrecognised message: %@", messageName);
		
		//call method:
		NSMethodSignature* signature = [method.target methodSignatureForSelector:method.selector];
		NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
		invocation.target = method.target;
		invocation.selector = method.selector;
		NSDictionary* args = userInfo[@"args"];
		NSString* replyUUID = userInfo[@"replyUUID"];
		if (signature.numberOfArguments > 2)
			[invocation setArgument:&args atIndex:2];
		[invocation invoke];

		//send reply:
		if (replyUUID.length)
		{
			__unsafe_unretained id weakReturnValue = nil;
			if (strcmp(signature.methodReturnType, "v") != 0)
				[invocation getReturnValue:&weakReturnValue];
			id returnValue = weakReturnValue;
			NSDictionary* replyDict = returnValue ? @{@"returnValue" : returnValue} : @{};
			IOSurfaceRef replySurface = [self _createSurfaceForDictionary:replyDict];
			NSString* replyMessageName = [self _messageReplyNameForSelector:method.selector uuid:replyUUID];
			[self _sendNotificationWithName:replyMessageName state:[self _stateForSurface:replySurface]];
			
			float timeout = 2.0;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
				CFRelease(replySurface);
			});
		}
	}
}

-(void)_throwException:(NSString*)msg fromMethod:(SEL)method
{
	NSString* reason = [NSString stringWithFormat:@"-[%@ %@] - %@", [self class], NSStringFromSelector(method), msg];
	NSException* myException = [NSException exceptionWithName:@"MRYIPCException" reason:reason userInfo:nil];
	@throw myException;
}

-(void)dealloc
{
	for (id token in _observerTokens)
		notify_cancel([token intValue]);
	[self _sendNotificationWithName:@"com.muirey03.libmryipc-removeObserver" state:(uint64_t)getpid()];
}
@end
