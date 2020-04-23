#ifndef MRYBOOTSTRAP_H
#define MRYBOOTSTRAP_H

#include <mach/mach.h>
#include <bootstrap.h>

#ifdef __cplusplus
extern "C" {
#endif

kern_return_t mrybootstrap_look_up(const name_t service_name, mach_port_t* sp);
kern_return_t mrybootstrap_check_in(const name_t service_name, mach_port_t* sp);

#ifdef __cplusplus
}
#endif

#endif //MRYBOOTSTRAP_H
