/*
 * VeraDroid: build the 4.1 binder driver as an out-of-tree module for Kindle kernels that
 * ship without CONFIG_ANDROID (PW4 / Oasis 3, 4.1.15-lab126). The driver uses a few kernel
 * functions that are not exported to modules; resolve them once at load time through
 * kallsyms_lookup_name (exported on these kernels) and redirect the calls with macros.
 * Included by binder.c after all kernel headers.
 */
#ifndef VD_COMPAT_H
#define VD_COMPAT_H
#include <linux/kallsyms.h>

#define VD_SYMS(X) \
	X(int, __alloc_fd, (struct files_struct *a, unsigned b, unsigned c, unsigned d)) \
	X(void, __fd_install, (struct files_struct *a, unsigned int b, struct file *c)) \
	X(int, __close_fd, (struct files_struct *a, unsigned int b)) \
	X(struct files_struct *, get_files_struct, (struct task_struct *a)) \
	X(void, put_files_struct, (struct files_struct *a)) \
	X(int, can_nice, (const struct task_struct *a, const int b)) \
	X(struct sighand_struct *, __lock_task_sighand, (struct task_struct *a, unsigned long *b)) \
	X(int, map_vm_area, (struct vm_struct *a, pgprot_t b, struct page **c)) \
	X(struct vm_struct *, get_vm_area, (unsigned long a, unsigned long b)) \
	X(void, zap_page_range, (struct vm_area_struct *a, unsigned long b, unsigned long c, struct zap_details *d)) \
	X(void, unmap_kernel_range, (unsigned long a, unsigned long b)) \
	X(int, task_work_add, (struct task_struct *a, struct callback_head *b, bool c))

#define VD_DECL(ret, name, args) static ret (*vd_##name) args;
VD_SYMS(VD_DECL)
#undef VD_DECL

static int vd_resolve(void)
{
#define VD_LOOK(ret, name, args) \
	vd_##name = (void *)kallsyms_lookup_name(#name); \
	if (!vd_##name) { pr_err("binder: symbol %s not found\n", #name); return -ENOENT; }
	VD_SYMS(VD_LOOK)
#undef VD_LOOK
	return 0;
}

#define __alloc_fd(...)          vd___alloc_fd(__VA_ARGS__)
#define __fd_install(...)        vd___fd_install(__VA_ARGS__)
#define __close_fd(...)          vd___close_fd(__VA_ARGS__)
#define get_files_struct(...)    vd_get_files_struct(__VA_ARGS__)
#define put_files_struct(...)    vd_put_files_struct(__VA_ARGS__)
#define can_nice(...)            vd_can_nice(__VA_ARGS__)
#define __lock_task_sighand(...) vd___lock_task_sighand(__VA_ARGS__)
#define map_vm_area(...)         vd_map_vm_area(__VA_ARGS__)
#define get_vm_area(...)         vd_get_vm_area(__VA_ARGS__)
#define zap_page_range(...)      vd_zap_page_range(__VA_ARGS__)
#define unmap_kernel_range(...)  vd_unmap_kernel_range(__VA_ARGS__)
#define task_work_add(...)       vd_task_work_add(__VA_ARGS__)
/* lock_task_sighand() is a static inline in sched.h that calls the unexported helper */
#define lock_task_sighand(t, f)  vd___lock_task_sighand(t, f)
#endif
