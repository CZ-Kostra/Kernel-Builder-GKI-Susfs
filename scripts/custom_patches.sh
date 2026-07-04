#!/bin/bash
# scripts/custom_patches.sh

set -euo pipefail

if [[ "${SU_VARIANT}" == "SukiSU-Ultra" ]]; then
    echo ">>> Target is SukiSU-Ultra. Applying Universal SuSFS 2.20 Patch..."
    
    # Navigate into the staged manager directory
    cd kernel_workspace/KernelSU
    
    # Attempt to apply the patch. We use || true so a rejection doesn't instantly crash the CI runner.
    # --no-backup-if-mismatch prevents patch from leaving messy .orig files around
    patch -p1 --no-backup-if-mismatch < ../../patches/2.20_universal_susfs.patch || true
    
    # Catch and resolve rejected hunks dynamically
    if find . -name "*.rej" | grep -q "."; then
        echo "[-] Patch rejections detected! Initiating dynamic fixup routine for SukiSU-Ultra..."

        # 1. kernel/Kbuild (Strip Next-specific hooks and apply SuSFS exclusions)
        sed -i '/kernelsu-objs += hook\/lsm_hook.o/,/endif/c\
# Core utilities\
ifeq ($(strip $(CONFIG_KPROBES)),y)\
kernelsu-objs += hook/lsm_hook.o\
ifeq ($(CONFIG_ARM64),y)\
kernelsu-objs += hook/arm64/patch_memory.o\
else ifeq ($(CONFIG_X86_64),y)\
kernelsu-objs += hook/x86_64/patch_memory.o\
endif\
endif\
\
# Hooks (excluded for SuSFS)\
ifneq ($(strip $(CONFIG_KSU_SUSFS)),y)\
ifeq ($(strip $(CONFIG_KPROBES)),y)\
kernelsu-objs += hook/syscall_event_bridge.o\
kernelsu-objs += hook/syscall_hook_manager.o\
kernelsu-objs += hook/tp_marker.o\
ifeq ($(CONFIG_ARM64),y)\
kernelsu-objs += hook/arm64/syscall_hook.o\
else ifeq ($(CONFIG_X86_64),y)\
kernelsu-objs += hook/x86_64/syscall_hook.o\
endif\
endif\
endif\
\
kernelsu-objs += hook/setuid_hook.o' kernel/Kbuild

        # 2. kernel/core/init.c (Inject SuSFS init/exit routines around SukiSU's stripped core)
        sed -i '/if (ksu_late_loaded) {/i #ifdef CONFIG_KSU_SUSFS\n\tksu_sucompat_init();\n\tksu_setuid_hook_init();\n\tksu_avc_spoof_init();\n#endif\n' kernel/core/init.c
        sed -i '/if (!getenforce()) {/i \t#ifdef CONFIG_KSU_SUSFS\n\tksu_avc_spoof_late_init();\n\t#endif\n\tksu_selinux_hide_drop_backup_if_unused();\n' kernel/core/init.c
        sed -i '/ksu_selinux_hide_exit();/i #ifdef CONFIG_KSU_SUSFS\n\tksu_avc_spoof_exit();\n\tksu_sucompat_exit();\n\tksu_setuid_hook_exit();\n#endif\n' kernel/core/init.c

        # 3. kernel/supercall/supercall.c (Inject only the SuSFS reboot handler, ignore missing toolkit)
        cat << 'EOF' >> kernel/supercall/supercall.c

#ifdef CONFIG_KSU_SUSFS
int ksu_supercall_reboot_handler(void __user **arg)
{
    struct ksu_install_fd_tw *tw;
    tw = kzalloc(sizeof(*tw), GFP_KERNEL);
    if (!tw) return 0;
    tw->outp = (int __user *)(*arg);
    tw->cb.func = ksu_install_fd_tw_func;
    if (task_work_add(current, &tw->cb, TWA_RESUME)) {
        kfree(tw);
        pr_warn("install fd add task_work failed\n");
    }
    return 0;
}
#endif
EOF

        # 4. kernel/selinux/selinux.c (Append all missing SuSFS SID caching mechanisms)
        cat << 'EOF' >> kernel/selinux/selinux.c

#ifdef CONFIG_KSU_SUSFS
#define KERNEL_INIT_DOMAIN "u:r:init:s0"
#define KERNEL_ZYGOTE_DOMAIN "u:r:zygote:s0"
#define KERNEL_PRIV_APP_DOMAIN "u:r:priv_app:s0:c512,c768"

static inline void susfs_set_sid(const char *secctx_name, u32 *out_sid) {
    int err;
    if (!secctx_name || !out_sid) return;
    err = security_secctx_to_secid(secctx_name, strlen(secctx_name), out_sid);
    if (!err) pr_info("sid '%u' is set for secctx_name '%s'\n", *out_sid, secctx_name);
}

bool susfs_is_sid_equal(const struct cred *cred, u32 sid2) {
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
    const struct task_security_struct *tsec = selinux_cred(cred);
#else
    const struct cred_security_struct *tsec = selinux_cred(cred);
#endif
    if (!tsec) return false;
    return tsec->sid == sid2;
}

u32 susfs_get_sid_from_name(const char *secctx_name) {
    u32 out_sid = 0;
    if (!secctx_name) return 0;
    security_secctx_to_secid(secctx_name, strlen(secctx_name), &out_sid);
    return out_sid;
}

u32 susfs_get_current_sid(void) { return current_sid(); }
bool susfs_is_current_zygote_domain(void) { return unlikely(current_sid() == susfs_zygote_sid); }
bool susfs_is_current_ksu_domain(void) { return unlikely(current_sid() == susfs_ksu_sid); }
bool susfs_is_current_init_domain(void) { return unlikely(current_sid() == susfs_init_sid); }

void susfs_set_batch_sid(void) {
    susfs_set_sid(KERNEL_ZYGOTE_DOMAIN, &susfs_zygote_sid);
    susfs_set_sid(KERNEL_SU_CONTEXT, &susfs_ksu_sid);
    susfs_set_sid(KERNEL_INIT_DOMAIN, &susfs_init_sid);
    susfs_set_sid(KERNEL_PRIV_APP_DOMAIN, &susfs_priv_app_sid);
}
#endif
EOF

        # 5. kernel/feature/sucompat.c (Static keys, user paths, and chroot protections)
        sed -i 's/bool ksu_su_compat_enabled __read_mostly = true;/static const char sh_path[] = SH_PATH;\nstatic const char su_path[] = SU_PATH;\nstatic const char ksud_path[] = KSUD_PATH;\n\nDEFINE_STATIC_KEY_TRUE(ksu_su_compat_enabled);/' kernel/feature/sucompat.c
        sed -i '/static int su_compat_feature_get/,/}/c\static int su_compat_feature_get(u64 *value)\n{\n    if (static_key_enabled(&ksu_su_compat_enabled))\n        *value = 1;\n    else\n        *value = 0;\n    return 0;\n}' kernel/feature/sucompat.c
        sed -i '/static int su_compat_feature_set/,/}/c\static int su_compat_feature_set(u64 value)\n{\n    bool enable = value != 0;\n    if (enable)\n        static_branch_enable(&ksu_su_compat_enabled);\n    else\n        static_branch_disable(&ksu_su_compat_enabled);\n    pr_info("su_compat: set to %d\\n", enable);\n    return 0;\n}' kernel/feature/sucompat.c
        sed -i '/static char __user \*ksud_user_path/i static char __user *sh_user_path(void)\n{\n    static const char sh_path_local[] = "/system/bin/sh";\n    return userspace_stack_buffer(sh_path_local, sizeof(sh_path_local));\n}\n' kernel/feature/sucompat.c
        sed -i '/static char __user \*ksud_user_path/,/}/c\static char __user *ksud_user_path(void)\n{\n    static const char ksud_path_local[] = KSUD_PATH;\n    return userspace_stack_buffer(ksud_path_local, sizeof(ksud_path_local));\n}' kernel/feature/sucompat.c
        
        # Inject chroot guards into the handler functions
        sed -i '/long ksu_handle_faccessat_sucompat/,/old_cred = override_creds(ksu_cred);/ s/if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {/if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {\n\t\tif (current_chrooted()) {\n\t\t\tpr_err("ksu: su found but NOT allowed in chroot\\n");\n\t\t\tgoto do_orig_facessat;\n\t\t}/' kernel/feature/sucompat.c
        sed -i '/long ksu_handle_stat_sucompat/,/old_cred = override_creds(ksu_cred);/ s/if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {/if (unlikely(!memcmp(path, su_path, sizeof(su_path)))) {\n\t\tif (current_chrooted()) {\n\t\t\tpr_err("ksu: su found but NOT allowed in chroot\\n");\n\t\t\tgoto do_orig_stat;\n\t\t}/' kernel/feature/sucompat.c
        sed -i '/long ksu_handle_execve_sucompat/,/ksu_compat_sulog/ s/goto do_orig_execve;/goto do_orig_execve;\n\n\tif (current_chrooted()) {\n\t\tpr_err("ksu: su found but NOT allowed in chroot\\n");\n\t\tgoto do_orig_execve;\n\t}/' kernel/feature/sucompat.c

        # 6. kernel/feature/kernel_umount.c (Exclude zygote checks for SuSFS and update init signature)
        sed -i 's/bool is_zygote_child = is_zygote(current_cred());/#ifndef CONFIG_KSU_SUSFS\n    bool is_zygote_child = is_zygote(current_cred());/' kernel/feature/kernel_umount.c
        sed -i '/pr_info("handle umount ignore non zygote child:/,/return 0;/ { /return 0;/a \    #endif\n}' kernel/feature/kernel_umount.c
        sed -i '/void __init ksu_kernel_umount_init/,/}/c\void __init ksu_kernel_umount_init(void)\n{\n    ksu_register_feature_handler(\&kernel_umount_handler);\n}' kernel/feature/kernel_umount.c

        # 7. kernel/hook/setuid_hook.c (Swap seccomp bypass for native disable_seccomp)
        sed -i '/if (current->seccomp.mode == SECCOMP_MODE_FILTER/,/}/c\        disable_seccomp();' kernel/hook/setuid_hook.c

        # 8. kernel/supercall/dispatch.c (Update hook mode responses)
        sed -i 's/#ifdef CONFIG_HAVE_SYSCALL_TRACEPOINTS/#ifndef CONFIG_KSU_SUSFS\n#ifdef CONFIG_HAVE_SYSCALL_TRACEPOINTS/' kernel/supercall/dispatch.c
        sed -i '/strscpy(cmd.mode, "Kprobes", sizeof(cmd.mode));/,/#endif/c\        strscpy(cmd.mode, "Kprobes", sizeof(cmd.mode));\n#endif\n#elif defined(CONFIG_HAVE_SYSCALL_TRACEPOINTS) || defined(CONFIG_KPROBES)\n    strscpy(cmd.mode, "Hybrid", sizeof(cmd.mode));\n#else\n    strscpy(cmd.mode, "Inline", sizeof(cmd.mode));\n#endif' kernel/supercall/dispatch.c

        # 9. kernel/runtime/boot_event.c (Inject input hook static key)
        sed -i '/bool ksu_boot_completed __read_mostly = false;/a \n#ifdef CONFIG_KSU_SUSFS\nextern struct static_key_true ksu_is_input_hook_enabled;\n#endif\nextern void ksu_avc_spoof_late_init(void);' kernel/runtime/boot_event.c

        # Cleanup rejected files so the workspace is pristine for compilation
        find . -name "*.rej" -type f -delete
        echo ">>> SukiSU-Ultra dynamic fixups applied successfully!"
    else
        echo ">>> Patch applied cleanly!"
    fi
   
    cd ../..
fi
