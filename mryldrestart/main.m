#include <sys/types.h>
#include <dlfcn.h>
#include <unistd.h>
#import <spawn.h>

void patch_setuid()
{
    void* handle = dlopen("/usr/lib/libjailbreak.dylib", RTLD_LAZY);
    if (!handle) 
        return;

    // Reset errors
    dlerror();
    typedef void (*fix_setuid_prt_t)(pid_t pid);
    fix_setuid_prt_t ptr = (fix_setuid_prt_t)dlsym(handle, "jb_oneshot_fix_setuid_now");
    
    const char *dlsym_error = dlerror();
    if (dlsym_error) 
        return;

    ptr(getpid());
}

int main(int argc, char** argv, char** envp)
{
	patch_setuid();
	setuid(0);
	setuid(0);

	pid_t pid;
    int status;
    const char* args[] = {"ldrestart", NULL};
    posix_spawn(&pid, "/usr/bin/ldrestart", NULL, NULL, (char* const*)args, NULL);
    waitpid(pid, &status, WEXITED);

	return 0;
}
