/* Compiled with fragments extracted from the fully patched kernel sources. */
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define IFNAMSIZ 16
#define MAX_EXT_DEVS 4
struct net_device {
	char name[IFNAMSIZ];
	int ifindex, refs, registered;
	struct net_device *master;
};
struct extdev_entry { struct net_device *dev; };
struct mtk_hnat {
	char wan[IFNAMSIZ], wan2[IFNAMSIZ], lan[IFNAMSIZ], lan2[IFNAMSIZ], ppd[IFNAMSIZ];
	struct net_device *g_wandev, *g_wan2dev, *g_ppdev;
	struct extdev_entry *ext_if[MAX_EXT_DEVS];
};
static struct mtk_hnat state;
static struct mtk_hnat *hnat_priv = &state;
static int init_net, checks;
static struct net_device devices[] = {
	{ "wan", 10, 0, 1, NULL },
	{ "sfp-wan", 20, 0, 1, NULL },
	{ "eth0", 30, 0, 1, NULL },
	{ "lan1", 40, 0, 1, NULL },
	{ "sfp-lan", 50, 0, 1, NULL },
	{ "br-wan", 60, 0, 1, NULL },
	{ "br-lan", 70, 0, 1, NULL },
	{ "uplink2", 80, 0, 1, NULL },
};
#define CHECK(x) do { checks++; if (!(x)) { \
	fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
#define rcu_read_lock() ((void)0)
#define rcu_read_unlock() ((void)0)
#define netif_is_bridge_port(d) ((d)->master != NULL)
#define netdev_master_upper_dev_get_rcu(d) ((d)->master)
#define IS_WAN(d) is_hnat_wan_dev(d)
#define IS_PPD(d) (!strcmp((d)->name, hnat_priv->ppd))
#define ext_if_del(e) ((void)(e))
#define kfree(p) free(p)
static struct net_device *dev_get_by_name(int *ns, const char *name)
{
	size_t i;
	(void)ns;
	for (i = 0; i < sizeof(devices) / sizeof(devices[0]); i++)
		if (devices[i].registered && !strcmp(name, devices[i].name)) {
			devices[i].refs++;
			return &devices[i];
		}
	return NULL;
}
static void dev_put(struct net_device *dev) { CHECK(dev->refs > 0); dev->refs--; }
static const char *property;
static int property_error;
static int of_property_read_string(void *np, const char *key, const char **name)
{
	(void)np;
	CHECK(!strcmp(key, "mtketh-wan2"));
	if (property_error) return property_error;
	if (!property) return -EINVAL;
	*name = property;
	return 0;
}
static int dev_valid_name(const char *s)
{
	return s[0] && strlen(s) < IFNAMSIZ && !strpbrk(s, "/ :\t\n") &&
	       strcmp(s, ".") && strcmp(s, "..");
}
static int strscpy(char *dst, const char *src, size_t len)
{
	if (strlen(src) >= len) return -E2BIG;
	strcpy(dst, src);
	return (int)strlen(src);
}
#define dev_err(...) ((void)0)
#define dev_info(...) ((void)0)
static int parse_wan2(void)
{
	int err;
	void *np = NULL;
	const char *name = NULL;
	/* @PARSE@ */
	return 0;
err_out2:
	return err;
}
/* @CLASSIFY@ */
/* @LOOKUP@ */
static void start_one_ppe(void) { /* @START@ */ }
/* @RELEASE@ */
static void register_dev(struct net_device *dev) { /* @REGISTER@ */ }
static void unregister_dev(struct net_device *dev) { /* @UNREGISTER@ */ }

int main(void)
{
	int i;
	strcpy(state.wan, "wan");
	strcpy(state.wan2, "sfp-wan");
	strcpy(state.ppd, "eth0");
	CHECK(IS_WAN(&devices[0]));
	CHECK(IS_WAN(&devices[1]));
	CHECK(!IS_WAN(&devices[3]));
	CHECK(!IS_WAN(&devices[4]));
	CHECK(!IS_WAN(NULL));
	start_one_ppe();
	/* Regression: upstream classification passes, secondary lookup does not. */
	CHECK(get_wandev_from_index(20) == &devices[1]);
	CHECK(get_wandev_from_index(10) == &devices[0]);
	CHECK(get_wandev_from_index(40) == NULL);
	for (i = 0; i < 3; i++) start_one_ppe();
	CHECK(devices[0].refs == 1);
	CHECK(devices[1].refs == 1);
	CHECK(devices[2].refs == 1);
	for (i = 0; i < 20; i++) CHECK(get_wandev_from_index(20) == &devices[1]);
	CHECK(devices[1].refs == 1);
	/* Preserve bridge role precedence from the upstream bridge patch. */
	devices[1].master = &devices[6];
	CHECK(!IS_WAN(&devices[1]));
	devices[1].master = NULL;
	devices[3].master = &devices[5];
	CHECK(IS_WAN(&devices[3]));
	devices[3].master = NULL;
	/* Unregister/re-register must release and acquire exactly one reference. */
	unregister_dev(&devices[1]);
	devices[1].registered = 0;
	CHECK(devices[1].refs == 0);
	CHECK(get_wandev_from_index(20) == NULL);
	CHECK(get_wandev_from_index(10) == &devices[0]);
	devices[1].ifindex = 21;
	devices[1].registered = 1;
	register_dev(&devices[1]);
	CHECK(get_wandev_from_index(20) == NULL);
	CHECK(get_wandev_from_index(21) == &devices[1]);
	unregister_dev(&devices[0]);
	devices[0].registered = 0;
	CHECK(get_wandev_from_index(10) == NULL);
	CHECK(get_wandev_from_index(21) == &devices[1]);
	hnat_release_netdev();
	for (i = 0; i < 3; i++) CHECK(devices[i].refs == 0);
	/* Optional property absent: retain legacy single-WAN behavior. */
	memset(&state, 0, sizeof(state));
	strcpy(state.wan, "wan");
	strcpy(state.ppd, "eth0");
	devices[0].registered = 1;
	start_one_ppe();
	CHECK(get_wandev_from_index(10) == &devices[0]);
	CHECK(get_wandev_from_index(21) == NULL);
	CHECK(!IS_WAN(&devices[7]));
	strcpy(state.wan2, "uplink2");
	CHECK(IS_WAN(&devices[7]));
	register_dev(&devices[7]);
	CHECK(get_wandev_from_index(80) == &devices[7]);
	hnat_release_netdev();
	for (i = 0; i < 8; i++) CHECK(devices[i].refs == 0);
	/* Exercise the actual DT property parser, including invalid names. */
	memset(state.wan2, 0, sizeof(state.wan2));
	CHECK(parse_wan2() == 0);
	CHECK(state.wan2[0] == 0);
	property = "sfp-wan";
	CHECK(parse_wan2() == 0);
	CHECK(!strcmp(state.wan2, "sfp-wan"));
	property = "";
	CHECK(parse_wan2() == -EINVAL);
	property = "wan";
	CHECK(parse_wan2() == -EINVAL);
	property = "wan sfp-wan";
	CHECK(parse_wan2() == -EINVAL);
	property = "abcdefghijklmnop";
	CHECK(parse_wan2() == -EINVAL);
	property = "sfp-wan";
	property_error = -EILSEQ;
	CHECK(parse_wan2() == -EILSEQ);
	printf("PASS: %d HNAT WAN classification, lookup and lifetime checks\n", checks);
	return 0;
}
