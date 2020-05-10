#include "mrybootstrap.h"
#import <xpc/xpc.h>
#import <sandbox.h>

mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t dictionary, const char* name);
mach_port_t xpc_dictionary_extract_mach_recv(xpc_object_t dictionary, const char* name);

kern_return_t mrybootstrap_look_up(const name_t service_name, mach_port_t* sp)
{
	kern_return_t kr = KERN_SUCCESS;
	if (sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_GLOBAL_NAME | SANDBOX_CHECK_NO_REPORT, service_name) == 0)
	{
		kr = bootstrap_look_up(bootstrap_port, service_name, sp);
	}
	else
	{
		xpc_connection_t connection = xpc_connection_create_mach_service(HELPER_SERVICE, NULL, 0);
		xpc_connection_set_event_handler(connection, ^(xpc_object_t some_object) { });
		xpc_connection_resume(connection);

		xpc_object_t object = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_uint64(object, kMRYBootstrapMessageIDKey, kMRYBootstrapLookupServiceID);
		xpc_dictionary_set_string(object, "service", service_name);
		xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, object);
		kr = xpc_dictionary_get_uint64(reply, "error");
		mach_port_t port = xpc_dictionary_copy_mach_send(reply, "servicePort");
		*sp = port;
	}

	return kr;
}

kern_return_t mrybootstrap_check_in(const name_t service_name, mach_port_t* sp)
{
	kern_return_t kr = bootstrap_check_in(bootstrap_port, service_name, sp);
	if (kr == KERN_SUCCESS)
		return kr;
	xpc_connection_t connection = xpc_connection_create_mach_service(HELPER_SERVICE, NULL, 0);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t some_object) { });
	xpc_connection_resume(connection);

	xpc_object_t object = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_uint64(object, kMRYBootstrapMessageIDKey, kMRYBootstrapCheckinServiceID);
	xpc_dictionary_set_string(object, "service", service_name);
	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, object);
	kr = xpc_dictionary_get_uint64(reply, "error");
	mach_port_t port = xpc_dictionary_extract_mach_recv(reply, "servicePort");
	*sp = port;

	return kr;
}
