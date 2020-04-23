#include <mach/mach.h>
#include <bootstrap.h>
#include <xpc/xpc.h>

#define kMRYBootstrapMessageIDKey "MRYBootstrapMessageID"
#define kMRYBootstrapLookupServiceID 'LKUP'
#define kMRYBootstrapCheckinServiceID 'CKIN'

extern "C" void xpc_dictionary_set_mach_send(xpc_object_t dictionary, const char* name, mach_port_t port);
extern "C" void xpc_dictionary_set_mach_recv(xpc_object_t dictionary, const char* name, mach_port_t port);

void handleLookupRequest(xpc_object_t request)
{
	const char* service = xpc_dictionary_get_string(request, "service");
	mach_port_t sp = MACH_PORT_NULL;
	kern_return_t kr;
	if (strstr(service, "mry:") == service)
		kr = bootstrap_look_up(bootstrap_port, service, &sp);
	else
		kr = BOOTSTRAP_NOT_PRIVILEGED;
	xpc_object_t reply = xpc_dictionary_create_reply(request);
	if (reply)
	{
		xpc_dictionary_set_uint64(reply, "error", kr);
		xpc_dictionary_set_mach_send(reply, "servicePort", sp);

		xpc_connection_send_message(xpc_dictionary_get_remote_connection(request), reply);
	}
}

void handleCheckinRequest(xpc_object_t request)
{
	const char* service = xpc_dictionary_get_string(request, "service");
	mach_port_t sp = MACH_PORT_NULL;
	kern_return_t kr;
	if (strstr(service, "mry:") == service)
		kr = bootstrap_check_in(bootstrap_port, service, &sp);
	else
		kr = BOOTSTRAP_NOT_PRIVILEGED;
	xpc_object_t reply = xpc_dictionary_create_reply(request);
	if (reply)
	{
		xpc_dictionary_set_uint64(reply, "error", kr);
		xpc_dictionary_set_mach_recv(reply, "servicePort", sp);

		xpc_connection_send_message(xpc_dictionary_get_remote_connection(request), reply);
	}
}

%hookf(void, xpc_connection_set_event_handler, xpc_connection_t connection, xpc_handler_t handler)
{
	if (connection)
	{
		xpc_handler_t oldHandler = handler;
		handler = ^(xpc_object_t object){
			if (object)
			{
				xpc_type_t type = xpc_get_type(object);
				if (type == XPC_TYPE_DICTIONARY)
				{
					uint64_t messageID = xpc_dictionary_get_uint64(object, kMRYBootstrapMessageIDKey);
					switch (messageID)
					{
						case kMRYBootstrapLookupServiceID:
							handleLookupRequest(object);
							return;
						case kMRYBootstrapCheckinServiceID:
							handleCheckinRequest(object);
							return;
					}
				}
			}
			if (oldHandler)
				oldHandler(object);
		};
	}
	%orig;
}
