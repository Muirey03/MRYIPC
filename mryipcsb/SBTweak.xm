#import <spawn.h>

static void respring(void)
{
	kill(getpid(), SIGTERM);
}

static void restartServices(void)
{
	pid_t pid;
    int status;
    const char* args[] = {"mryldrestart", NULL};
    posix_spawn(&pid, "/usr/bin/mryldrestart", NULL, NULL, (char* const*)args, NULL);
    waitpid(pid, &status, WEXITED);

	[[NSRunLoop currentRunLoop] performBlock:^{
		respring();
	}];
}

%ctor
{
	NSString* const flagPath = @"/tmp/mryipcneedsrestart";
	NSFileManager* manager = [NSFileManager defaultManager];
	if ([manager fileExistsAtPath:flagPath])
	{
		BOOL success = [manager removeItemAtPath:flagPath error:NULL];
		if (success)
			restartServices();
	}
}
