@import Foundation;
#include <mach/mach.h>
#include "mrybootstrap.h"
#import "MRYIPCCenter.h"

#define THROW(...) _throwException([NSString stringWithFormat:__VA_ARGS__], _cmd)
#define kMRYIPCCallMethodID 'CALL'
#define kMRYIPCMethodReplyID 'REPL'

static void _throwException(NSString* msg, SEL method)
{
	NSString* reason = [NSString stringWithFormat:@"%@ - %@", NSStringFromSelector(method), msg];
	NSException* myException = [NSException exceptionWithName:@"MRYIPCException" reason:reason userInfo:nil];
	@throw myException;
}

@interface _MRYIPCMethod : NSObject
@property (nonatomic, readonly) id target;
@property (nonatomic, readonly) SEL selector;
-(instancetype)initWithTarget:(id)target selector:(SEL)selector;
-(id)invokeWithArguments:(id)args;
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

-(id)invokeWithArguments:(id)args
{
	//call method:
	NSMethodSignature* signature = [_target methodSignatureForSelector:_selector];
	NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
	invocation.target = _target;
	invocation.selector = _selector;
	if (signature.numberOfArguments > 2)
		[invocation setArgument:&args atIndex:2];
	[invocation invoke];

	__unsafe_unretained id weakReturnValue = nil;
	if (strcmp(signature.methodReturnType, "v") != 0)
		[invocation getReturnValue:&weakReturnValue];
	id returnValue = weakReturnValue;
	return returnValue;
}
@end

@interface _MRYIPCBlockMethod : _MRYIPCMethod
@property (nonatomic, readonly) id(^block)(id);
@end

@implementation _MRYIPCBlockMethod
-(instancetype)initWithBlock:(id(^)(id))block
{
	if ((self = [super init]))
	{
		_block = block;
	}
	return self;
}

-(id)invokeWithArguments:(id)args
{
	return _block(args);
}
@end

typedef struct MRYIPCMessage
{
	mach_msg_base_t base;
	mach_msg_ool_descriptor_t messageName;
	mach_msg_ool_descriptor_t userInfo;
} MRYIPCMessage_t;

@interface MRYIPCCenter ()
-(instancetype)initWithName:(NSString*)name;
-(void)_addTargetMethod:(_MRYIPCMethod*)method forSelector:(SEL)selector;
-(NSString*)_messageNameForSelector:(SEL)selector;
-(void)_createMessage:(MRYIPCMessage_t*)msg withName:(const char*)name userInfo:(NSDictionary*)userInfo remotePort:(mach_port_t)remotePort userInfoData:(__strong NSData**)userInfoData;
-(BOOL)_validateMessage:(MRYIPCMessage_t*)msg forID:(uint32_t)msgID;
-(NSDictionary*)_userInfoForMessage:(MRYIPCMessage_t*)msg;
-(void)_freeOOLDataInMessage:(MRYIPCMessage_t*)msg;
-(BOOL)_messageReceived:(MRYIPCMessage_t*)msg;
@end

@implementation MRYIPCCenter
{
	NSMutableDictionary<NSString*, _MRYIPCMethod*>* _methods;
	name_t _serviceName;
	mach_port_t _serverPort;
	dispatch_queue_t _queue;
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
		snprintf(_serviceName, sizeof(_serviceName), "mry:%s-service", name.UTF8String);
		_methods = [NSMutableDictionary new];
		_queue = dispatch_queue_create("com.muirey03.libmryipc-messageQueue", NULL);
	}
	return self;
}

-(void)_addTargetMethod:(_MRYIPCMethod*)method forSelector:(SEL)selector
{
	NSString* messageName = [self _messageNameForSelector:selector];
	if (_methods[messageName])
		THROW(@"method already registered: %@", NSStringFromSelector(selector));
	
	if (_serverPort == MACH_PORT_NULL)
	{
		kern_return_t kr = mrybootstrap_check_in(_serviceName, &_serverPort);
		if (kr != KERN_SUCCESS)
			THROW(@"Failed to create server receive port: %s", bootstrap_strerror(kr));

		dispatch_async(_queue, ^{
			for (;;)
			{
				#define MAX_RCV_SIZE (sizeof(MRYIPCMessage_t) + 8)
				union
				{
					MRYIPCMessage_t msg;
					char padding[MAX_RCV_SIZE];
				} buffer;
				MRYIPCMessage_t* msg = &buffer.msg;
				
				mach_msg_return_t ret = mach_msg(&msg->base.header, MACH_RCV_MSG, 0, MAX_RCV_SIZE, _serverPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
				if (ret == KERN_SUCCESS)
				{
					BOOL success = [self _messageReceived:msg];
					if (success)
					{
						mach_msg(&msg->base.header, MACH_SEND_MSG, msg->base.header.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
					}
				}
			}
		});
	}

	_methods[messageName] = method;
}

-(void)addTarget:(id)target action:(SEL)action
{
	if (!action || !strlen(sel_getName(action)))
		THROW(@"method cannot be null");
	if (!target)
		THROW(@"target cannot be null");
	_MRYIPCMethod* method = [[_MRYIPCMethod alloc] initWithTarget:target selector:action];
	[self _addTargetMethod:method forSelector:action];
}

-(void)addTarget:(id(^)(id))target forSelector:(SEL)selector
{
	if (!selector || !strlen(sel_getName(selector)))
		THROW(@"selector cannot be null");
	if (!target)
		THROW(@"target cannot be null");
	_MRYIPCBlockMethod* method = [[_MRYIPCBlockMethod alloc] initWithBlock:target];
	[self _addTargetMethod:method forSelector:selector];
}

//deprecated
-(void)registerMethod:(SEL)selector withTarget:(id)target
{
	[self addTarget:target action:selector];
}

-(void)callExternalVoidMethod:(SEL)method withArguments:(id)args
{
	[self callExternalMethod:method withArguments:args completion:nil];
}

-(id)callExternalMethod:(SEL)method withArguments:(id)args
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

-(void)callExternalMethod:(SEL)method withArguments:(id)args completion:(void(^)(id))completionHandler
{
	dispatch_async(_queue, ^{
		kern_return_t kr;
		if (!_serverPort)
		{
			mach_port_t sendPort = MACH_PORT_NULL;
			kr = mrybootstrap_look_up(_serviceName, &sendPort);
			if (kr != KERN_SUCCESS)
				THROW(@"Failed to lookup service port: %s", bootstrap_strerror(kr));
			_serverPort = sendPort;
		}

		NSString* messageName = [self _messageNameForSelector:method];

		mach_port_t (^createReplyPort)(void) = ^{
			kern_return_t kr;
			mach_port_t port = MACH_PORT_NULL;
			kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
			kr = mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
			return port;
		};

		#define MAX_RCV_SIZE (sizeof(MRYIPCMessage_t) + 8)
		union
		{
			MRYIPCMessage_t msg;
			char padding[MAX_RCV_SIZE];
		} buffer;
		MRYIPCMessage_t* msg = &buffer.msg;

		NSData* userInfoData;
		NSDictionary* userInfo = args ? @{@"args" : args} : nil;
		[self _createMessage:msg withName:messageName.UTF8String userInfo:userInfo remotePort:_serverPort userInfoData:&userInfoData];
		mach_port_t replyPort = createReplyPort();
		msg->base.header.msgh_local_port = replyPort;
		mach_msg_return_t ret = KERN_SUCCESS;
		ret = mach_msg(&msg->base.header, MACH_SEND_MSG | MACH_RCV_MSG, sizeof(MRYIPCMessage_t), MAX_RCV_SIZE, replyPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
		if (ret != KERN_SUCCESS)
			THROW(@"mach_msg failed: %s", mach_error_string(ret));
		BOOL valid = [self _validateMessage:msg forID:kMRYIPCMethodReplyID];
		if (!valid)
			THROW(@"Invalid reply message");

		userInfo = [self _userInfoForMessage:msg];
		id returnValue = userInfo ? userInfo[@"returnValue"] : nil;
		if (completionHandler)
			completionHandler(returnValue);
		mach_port_deallocate(mach_task_self(), replyPort);
		[self _freeOOLDataInMessage:msg];
		#undef MAX_RCV_SIZE
	});
}

-(NSString*)_messageNameForSelector:(SEL)selector
{
	return [NSString stringWithFormat:@"MRYIPCCenter-%@-%@", _centerName, NSStringFromSelector(selector)];
}

-(void)_createMessage:(MRYIPCMessage_t*)msg withName:(const char*)name userInfo:(NSDictionary*)userInfo remotePort:(mach_port_t)remotePort userInfoData:(__strong NSData**)userInfoData
{
	void (^fillOOLDescriptor)(mach_msg_ool_descriptor_t*, const void*, size_t, bool) = ^(mach_msg_ool_descriptor_t* desc, const void* buffer, size_t size, bool deallocate){
		desc->address = (void*)buffer;
		desc->size = size;
		desc->deallocate = deallocate;
		desc->copy = MACH_MSG_VIRTUAL_COPY;
		desc->type = MACH_MSG_OOL_DESCRIPTOR;
	};

	memset(msg, 0, sizeof(MRYIPCMessage_t));
	msg->base.header.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	msg->base.header.msgh_size = sizeof(MRYIPCMessage_t);
	msg->base.header.msgh_remote_port = remotePort;
	msg->base.header.msgh_id = kMRYIPCCallMethodID;
	msg->base.body.msgh_descriptor_count = 2;
	fillOOLDescriptor(&msg->messageName, name, strlen(name) + 1, false);
	if (userInfo)
	{
		NSError* err;
		NSData* data = [NSPropertyListSerialization dataWithPropertyList:userInfo format:NSPropertyListBinaryFormat_v1_0 options:0 error:&err];
		if (!data)
			THROW(@"Failed to serialize arguments: %@", err);
		//stash userInfoData in out pointer to stop it being deallocated before message is sent
		*userInfoData = data;
		fillOOLDescriptor(&msg->userInfo, data.bytes, data.length, false);
	}
	else
		fillOOLDescriptor(&msg->userInfo, NULL, 0, false);
}

-(BOOL)_validateMessage:(MRYIPCMessage_t*)msg forID:(uint32_t)msgID
{
	if (msg->base.header.msgh_size < sizeof(*msg))
		return NO;
	if (msg->base.header.msgh_id != msgID)
		return NO;
	if (!msg->messageName.address || msg->messageName.size < 2)
		return NO;
	return YES;
}

-(NSDictionary*)_userInfoForMessage:(MRYIPCMessage_t*)msg
{
	NSDictionary* userInfo = nil;
	if (msg->userInfo.address && msg->userInfo.size)
	{
		NSData* userInfoData = [NSData dataWithBytesNoCopy:msg->userInfo.address length:msg->userInfo.size freeWhenDone:NO];
		NSError* err;
		userInfo = [NSPropertyListSerialization propertyListWithData:userInfoData options:NSPropertyListImmutable format:NULL error:&err];
		if (userInfo && ![userInfo isKindOfClass:[NSDictionary class]])
			userInfo = nil;
	}
	return userInfo;
}

-(void)_freeOOLDataInMessage:(MRYIPCMessage_t*)msg
{
	if (msg->messageName.address && msg->messageName.size)
		vm_deallocate(mach_task_self(), (vm_address_t)msg->messageName.address, msg->messageName.size);
	if (msg->messageName.address && msg->messageName.size)
		vm_deallocate(mach_task_self(), (vm_address_t)msg->userInfo.address, msg->userInfo.size);
}

-(BOOL)_messageReceived:(MRYIPCMessage_t*)msg
{
	BOOL valid = [self _validateMessage:msg forID:kMRYIPCCallMethodID];
	if (!valid)
		return NO;
	char* messageName = msg->messageName.address;
	messageName[msg->messageName.size - 1] = '\0';
	messageName = strdup(messageName);

	NSDictionary* userInfo = [self _userInfoForMessage:msg];
	id args = userInfo[@"args"];
	_MRYIPCMethod* method = _methods[[NSString stringWithUTF8String:messageName]];
	if (!method)
		return NO;
	
	id returnValue = [method invokeWithArguments:args];
	userInfo = returnValue ? @{@"returnValue" : returnValue} : nil;

	[self _freeOOLDataInMessage:msg];

	NSData* userInfoData;
	[self _createMessage:msg withName:messageName userInfo:userInfo remotePort:msg->base.header.msgh_remote_port userInfoData:&userInfoData];
	msg->base.header.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
	msg->base.header.msgh_id = kMRYIPCMethodReplyID;

	free(messageName);
	return YES;
}

-(void)dealloc
{
	mach_port_deallocate(mach_task_self(), _serverPort);
}
@end
