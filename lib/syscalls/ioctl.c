#include <sys/ioctl.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>

#include "mpu_wrappers.h"

int _vioctl_r(struct _reent *ptr, int fd, unsigned long request, va_list args) PRIVILEGED_FUNCTION
{
	printf("first variable arg %d\n", va_arg(args, int));

	ptr->_errno = ENOTTY;
	return -1;
}

