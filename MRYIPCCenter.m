#import "MRYIPCCenter.h"

#define THROW(...) [self _throwException:[NSString stringWithFormat:__VA_ARGS__] fromMethod:_cmd]

@interface NSDistributedNotificationCenter : NSNotificationCenter
+(instancetype)defaultCenter;
@end

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
@end

@implementation MRYIPCCenter
{
	NSDistributedNotificationCenter* _notificationCenter;
	NSMutableDictionary<NSString*, _MRYIPCMethod*>* _methods;
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
		_notificationCenter = [NSDistributedNotificationCenter defaultCenter];
		_methods = [NSMutableDictionary new];
	}
	return self;
}

-(void)registerMethod:(SEL)selector withTarget:(id)target
{
	if (!selector)
		THROW(@"method cannot be null");
	if (!target)
		THROW(@"target cannot be null");
	
	NSString* messageName = [self _messageNameForSelector:selector];
	if (_methods[messageName])
		THROW(@"method already registered: %@", NSStringFromSelector(selector));
	
	_MRYIPCMethod* method = [[_MRYIPCMethod alloc] initWithTarget:target selector:selector];
	_methods[messageName] = method;

	[_notificationCenter addObserver:self selector:@selector(_messageReceived:) name:messageName object:nil];
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

-(void)callExternalVoidMethod:(SEL)method withArguments:(NSDictionary*)args
{
	NSString* messageName = [self _messageNameForSelector:method];
	NSDictionary* userInfo = args ? @{@"args" : args} : @{};
	[_notificationCenter postNotificationName:messageName object:nil userInfo:userInfo];
}

-(void)callExternalMethod:(SEL)method withArguments:(NSDictionary*)args completion:(void(^)(id))completionHandler
{
	NSString* replyUUID = [NSUUID UUID].UUIDString;
	NSString* messageName = [self _messageNameForSelector:method];
	NSString* replyMessageName = [self _messageReplyNameForSelector:method uuid:replyUUID];
	__weak NSDistributedNotificationCenter* weakNotificationCenter = _notificationCenter;
	NSOperationQueue* operationQueue = [NSOperationQueue new];
	__block id observer = [_notificationCenter addObserverForName:replyMessageName object:nil queue:operationQueue usingBlock:^(NSNotification* notification){
		completionHandler(notification.userInfo[@"returnValue"]);
		[weakNotificationCenter removeObserver:observer];
		observer = nil;
	}];
	NSMutableDictionary* userInfo = [NSMutableDictionary new];
	userInfo[@"replyUUID"] = replyUUID;
	if (args)
		userInfo[@"args"] = args;
	[_notificationCenter postNotificationName:messageName object:nil userInfo:userInfo];
}

-(NSString*)_messageNameForSelector:(SEL)selector
{
	return [NSString stringWithFormat:@"MRYIPCCenter-%@-%@", _centerName, NSStringFromSelector(selector)];
}

-(NSString*)_messageReplyNameForSelector:(SEL)selector uuid:(NSString*)uuid
{
	return [NSString stringWithFormat:@"MRYIPCCenter-%@-%@-reply-%@", _centerName, NSStringFromSelector(selector), uuid];
}

-(void)_messageReceived:(NSNotification*)notification
{
	NSString* messageName = notification.name;
	_MRYIPCMethod* method = _methods[messageName];
	if (!method)
		THROW(@"unrecognised message: %@", messageName);
	
	//call method:
	NSMethodSignature* signature = [method.target methodSignatureForSelector:method.selector];
	NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
	invocation.target = method.target;
	invocation.selector = method.selector;
	NSDictionary* args = notification.userInfo[@"args"];
	NSString* replyUUID = notification.userInfo[@"replyUUID"];
	[invocation setArgument:&args atIndex:2];
	[invocation invoke];

	//send reply:
	if (replyUUID.length)
	{
		id returnValue = nil;
		if (strcmp(signature.methodReturnType, "v") != 0)
			[invocation getReturnValue:&returnValue];
		NSDictionary* replyDict = returnValue ? @{@"returnValue" : returnValue} : @{};
		NSString* replyMessageName = [self _messageReplyNameForSelector:method.selector uuid:replyUUID];
		[_notificationCenter postNotificationName:replyMessageName object:nil userInfo:replyDict];
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
	[_notificationCenter removeObserver:self];
}
@end
