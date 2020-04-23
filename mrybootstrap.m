#include "mrybootstrap.h"
#import <xpc/xpc.h>

#define HELPER_SERVICE "com.apple.mobilegestalt.xpc"
#define kMRYBootstrapMessageIDKey "MRYBootstrapMessageID"
#define kMRYBootstrapLookupServiceID 'LKUP'
#define kMRYBootstrapCheckinServiceID 'CKIN'

mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t dictionary, const char* name);
mach_port_t xpc_dictionary_extract_mach_recv(xpc_object_t dictionary, const char* name);

kern_return_t mrybootstrap_look_up(const name_t service_name, mach_port_t* sp)
{
	xpc_connection_t connection = xpc_connection_create_mach_service(HELPER_SERVICE, NULL, 0);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t some_object) { });
	xpc_connection_resume(connection);

    xpc_object_t object = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(object, kMRYBootstrapMessageIDKey, kMRYBootstrapLookupServiceID);
    xpc_dictionary_set_string(object, "service", service_name);
    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, object);
	kern_return_t kr = xpc_dictionary_get_uint64(reply, "error");
	mach_port_t port = xpc_dictionary_copy_mach_send(reply, "servicePort");
	*sp = port;

	return kr;
}

kern_return_t mrybootstrap_check_in(const name_t service_name, mach_port_t* sp)
{
	xpc_connection_t connection = xpc_connection_create_mach_service(HELPER_SERVICE, NULL, 0);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t some_object) { });
	xpc_connection_resume(connection);

    xpc_object_t object = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(object, kMRYBootstrapMessageIDKey, kMRYBootstrapCheckinServiceID);
    xpc_dictionary_set_string(object, "service", service_name);
    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, object);
    kern_return_t kr = xpc_dictionary_get_uint64(reply, "error");
	mach_port_t port = xpc_dictionary_extract_mach_recv(reply, "servicePort");
	*sp = port;

	return kr;
}
