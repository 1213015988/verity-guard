/* vgkey —— 按键读取器（音量上/下、电源），同时抓住设备不让系统响应
 * 编译：musl-gcc -static -Os -s -o vgkey vgkey.c
 * 用法：vgkey [--timeout 秒] [--no-grab] [--hold 毫秒] /dev/input/eventX ...
 *
 * 输出一行：
 *   up / down   —— 短按音量上 / 音量下
 *   ok          —— 电源键按下，或音量键按住超过 --hold（默认 1000ms）
 * 退出：0 读到按键，3 超时，4 一个设备都打不开
 *
 * 短按=移动、长按=确认，所以只有音量键也能操作；电源键仍然可以直接确认。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <time.h>
#include <sys/ioctl.h>

/* 不依赖内核头文件，跨编译时省事 */
struct vg_event {
	long sec;
	long usec;
	unsigned short type;
	unsigned short code;
	int value;
};

#define VG_EV_KEY 0x01
#define VG_KEY_VOLUMEDOWN 114
#define VG_KEY_VOLUMEUP 115
#define VG_KEY_POWER 116
#define VG_EVIOCGRAB 0x40044590UL	/* _IOW('E', 0x90, int) */

#define MAXDEV 16
#define HOLD_MS 1000

static long now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

int main(int argc, char **argv)
{
	int fds[MAXDEV], nfd = 0, i, timeout = 20, hold = HOLD_MS, grab = 1;
	const char *paths[MAXDEV];
	const char *out = NULL;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--timeout") && i + 1 < argc)
			timeout = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--hold") && i + 1 < argc)
			hold = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--no-grab"))
			grab = 0;
		else if (argv[i][0] == '-')
			continue;
		else if (nfd < MAXDEV) {
			int fd = open(argv[i], O_RDWR);
			if (fd < 0)
				fd = open(argv[i], O_RDONLY);
			if (fd >= 0) {
				paths[nfd] = argv[i];
				fds[nfd++] = fd;
			}
		}
	}
	if (nfd == 0) {
		fputs("vgkey: 没有可用设备\n", stderr);
		return 4;
	}

	if (grab) {
		for (i = 0; i < nfd; i++) {
			if (ioctl(fds[i], VG_EVIOCGRAB, 1) < 0)
				dprintf(2, "vgkey: 抓不住 %s: %s\n", paths[i], strerror(errno));
		}
	}

	/* 打开时可能积压了旧事件（上一次没读完的），先丢掉，免得菜单自己乱跳 */
	for (i = 0; i < nfd; i++) {
		int fl = fcntl(fds[i], F_GETFL, 0);
		fcntl(fds[i], F_SETFL, fl | O_NONBLOCK);
		struct vg_event ev[16];
		while (read(fds[i], ev, sizeof(ev)) > 0)
			;
		fcntl(fds[i], F_SETFL, fl);
	}

	struct pollfd pf[MAXDEV];
	for (i = 0; i < nfd; i++) {
		pf[i].fd = fds[i];
		pf[i].events = POLLIN;
	}

	long total = (long)timeout * 1000;
	long t0 = now_ms();
	int alive = nfd;
	int pending = 0;	/* 正被按住的音量键 code */
	long pdown = 0;

	while (alive > 0 && !out) {
		long elapsed = now_ms() - t0;
		long remain = total - elapsed;
		if (remain <= 0)
			break;

		long wait = remain > 200 ? 200 : remain;
		if (pending) {
			long left = hold - (now_ms() - pdown);
			if (left <= 0) {
				out = "ok";	/* 按住不放 = 确认 */
				break;
			}
			if (left < wait)
				wait = left;
		}

		int r = poll(pf, nfd, (int)wait);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (r == 0)
			continue;

		for (i = 0; i < nfd && !out; i++) {
			if (pf[i].fd < 0 || !(pf[i].revents & POLLIN))
				continue;
			pf[i].revents = 0;
			struct vg_event ev[16];
			ssize_t n = read(fds[i], ev, sizeof(ev));
			if (n <= 0) {
				pf[i].fd = -1;
				alive--;
				continue;
			}
			int k, cnt = (int)(n / sizeof(ev[0]));
			for (k = 0; k < cnt && !out; k++) {
				if (ev[k].type != VG_EV_KEY)
					continue;
				if (ev[k].value == 1) {
					if (ev[k].code == VG_KEY_POWER) {
						out = "ok";
						break;
					}
					if (ev[k].code == VG_KEY_VOLUMEUP ||
					    ev[k].code == VG_KEY_VOLUMEDOWN) {
						pending = ev[k].code;
						pdown = now_ms();
					}
				} else if (ev[k].value == 0) {
					if (pending && ev[k].code == pending) {
						out = (ev[k].code == VG_KEY_VOLUMEUP) ? "up" : "down";
						pending = 0;
						break;
					}
				}
				/* value==2 是长按重复，忽略 */
			}
		}
	}

	if (grab) {
		for (i = 0; i < nfd; i++)
			ioctl(fds[i], VG_EVIOCGRAB, 0);
	}
	for (i = 0; i < nfd; i++)
		close(fds[i]);

	if (out) {
		printf("%s\n", out);
		fflush(stdout);
		return 0;
	}
	return 3;
}
