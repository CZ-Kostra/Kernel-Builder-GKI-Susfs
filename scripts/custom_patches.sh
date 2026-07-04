#!/bin/bash
# scripts/custom_patches.sh

set -euo pipefail

if [[ "${SU_VARIANT}" == "SukiSU-Ultra" ]]; then
    echo ">>> Target is SukiSU-Ultra. Applying Universal SuSFS 2.20 Patch..."
    
    cd kernel_workspace/KernelSU
    
    # Apply the filtered patch. We use || true so a rejection doesn't instantly crash the CI runner.
    patch -p1 --no-backup-if-mismatch < ../../patches/2.20_universal_susfs.patch || true
    
    # Catch and resolve rejected hunks dynamically
    if find . -name "*.rej" | grep -q "."; then
        echo "[-] Patch rejections detected! Initiating awk fixup routine for SukiSU-Ultra..."

        # 1. kernel/Kbuild (Revert patch corruption, then apply precise hook exclusions)
        git checkout kernel/Kbuild
        
        awk '/kernelsu-objs \+= hook\/lsm_hook\.o/ {
            print "# Core utilities\nifeq ($(strip $(CONFIG_KPROBES)),y)\nkernelsu-objs += hook/lsm_hook.o"
            print "ifeq ($(CONFIG_ARM64),y)\nkernelsu-objs += hook/arm64/patch_memory.o\nelse ifeq ($(CONFIG_X86_64),y)"
            print "kernelsu-objs += hook/x86_64/patch_memory.o\nendif\nendif\n\n# Hooks (excluded for SuSFS)"
            print "ifneq ($(strip $(CONFIG_KSU_SUSFS)),y)\nifeq ($(strip $(CONFIG_KPROBES)),y)"
            print "kernelsu-objs += hook/syscall_event_bridge.o\nkernelsu-objs += hook/syscall_hook_manager.o\nkernelsu-objs += hook/tp_marker.o"
            print "ifeq ($(CONFIG_ARM64),y)\nkernelsu-objs += hook/arm64/syscall_hook.o\nelse ifeq ($(CONFIG_X86_64),y)"
            print "kernelsu-objs += hook/x86_64/syscall_hook.o\nendif\nendif\nendif\n"
            print "kernelsu-objs += hook/setuid_hook.o"
            skip = 1; next
        }
        /kernelsu-objs \+= infra\/file_wrapper\.o/ { skip = 0 }
        !skip { print }' kernel/Kbuild > tmp.mk && mv tmp.mk kernel/Kbuild

        # 2. kernel/core/init.c (Inject SuSFS init/exit routines around SukiSU's stripped core)
        awk '/if \(ksu_late_loaded\) \{/ {
            print "#ifdef CONFIG_KSU_SUSFS\n\tksu_sucompat_init();\n\tksu_setuid_hook_init();\n#endif"
            print; next
        }
        /if \(!getenforce\(\)\) \{/ {
            print "\tksu_selinux_hide_drop_backup_if_unused();"
            print; next
        }
        /ksu_selinux_hide_exit\(\);/ {
            print "#ifdef CONFIG_KSU_SUSFS\n\tksu_sucompat_exit();\n\tksu_setuid_hook_exit();\n#endif"
            print; next
        }
        1' kernel/core/init.c > tmp.c && mv tmp.c kernel/core/init.c

        # 3. kernel/supercall/supercall.c (Inject only the SuSFS reboot handler)
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

        # 5. kernel/feature/sucompat.c (Static keys, user paths, chroot protections, and strip sulog)
        awk '
        /ksu_compat_sulog/ { next }
        /bool ksu_su_compat_enabled __read_mostly = true;/ {
            print "static const char sh_path[] = SH_PATH;\nstatic const char su_path[] = SU_PATH;\nstatic const char ksud_path[] = KSUD_PATH;\n\nDEFINE_STATIC_KEY_TRUE(ksu_su_compat_enabled);"
            next
        }
        /static int su_compat_feature_get/,/}/ {
            if ($0 ~ /}/) { print "static int su_compat_feature_get(u64 *value)\n{\n\tif (static_key_enabled(&ksu_su_compat_enabled))\n\t\t*value = 1;\n\telse\n\t\t*value = 0;\n\treturn 0;\n}" }
            next
        }
        /static int su_compat_feature_set/,/}/ {
            if ($0 ~ /}/) { print "static int su_compat_feature_set(u64 value)\n{\n\tbool enable = value != 0;\n\tif (enable)\n\t\tstatic_branch_enable(&ksu_su_compat_enabled);\n\telse\n\t\tstatic_branch_disable(&ksu_su_compat_enabled);\n\tpr_info(\"su_compat: set to %d\\n\", enable);\n\treturn 0;\n}" }
            next
        }
        /static char __user \*ksud_user_path/ {
            if (!sh_path_added) {
                print "static char __user *sh_user_path(void)\n{\n\tstatic const char sh_path_local[] = \"/system/bin/sh\";\n\treturn userspace_stack_buffer(sh_path_local, sizeof(sh_path_local));\n}\n"
                sh_path_added = 1
            }
        }
        /static char __user \*ksud_user_path/,/}/ {
            if ($0 ~ /}/) { print "static char __user *ksud_user_path(void)\n{\n\tstatic const char ksud_path_local[] = KSUD_PATH;\n\treturn userspace_stack_buffer(ksud_path_local, sizeof(ksud_path_local));\n}" }
            next
        }
        /long ksu_handle_faccessat_sucompat/ { in_fac = 1; in_stat = 0; }
        /long ksu_handle_stat_sucompat/ { in_stat = 1; in_fac = 0; }
        /long ksu_handle_execve_sucompat/ { in_stat = 0; in_fac = 0; }
        /if \(unlikely\(!memcmp\(path, su_path, sizeof\(su_path\)\)\)\) \{/ {
            print
            if (in_fac) print "\t\tif (current_chrooted()) {\n\t\t\tpr_err(\"ksu: su found but NOT allowed in chroot\\n\");\n\t\t\tgoto do_orig_facessat;\n\t\t}"
            else if (in_stat) print "\t\tif (current_chrooted()) {\n\t\t\tpr_err(\"ksu: su found but NOT allowed in chroot\\n\");\n\t\t\tgoto do_orig_stat;\n\t\t}"
            next
        }
        /if \(likely\(memcmp\(path, su_path, sizeof\(su_path\)\)\)\)/ {
            print; getline; print
            print "\n\tif (current_chrooted()) {\n\t\tpr_err(\"ksu: su found but NOT allowed in chroot\\n\");\n\t\tgoto do_orig_execve;\n\t}"
            next
        }
        1' kernel/feature/sucompat.c > tmp.c && mv tmp.c kernel/feature/sucompat.c

        # 6. kernel/feature/kernel_umount.c (Exclude zygote checks for SuSFS and update init signature)
        awk '
        /bool is_zygote_child = is_zygote/ { print "#ifndef CONFIG_KSU_SUSFS"; print; next }
        /pr_info\("handle umount ignore non zygote child/ { print; getline; print; getline; print; print "#endif"; next }
        /if \(ksu_register_feature_handler/ { print "\tksu_register_feature_handler(&kernel_umount_handler);"; getline; getline; next }
        1' kernel/feature/kernel_umount.c > tmp.c && mv tmp.c kernel/feature/kernel_umount.c

        # 7. kernel/hook/setuid_hook.c (Swap seccomp bypass for native disable_seccomp)
        awk '/if \(current->seccomp\.mode == SECCOMP_MODE_FILTER/,/}/ {
            if ($0 ~ /}/) print "\t\tdisable_seccomp();"
            next
        }
        1' kernel/hook/setuid_hook.c > tmp.c && mv tmp.c kernel/hook/setuid_hook.c

        # 8. kernel/supercall/dispatch.c (Update hook mode responses)
        awk '
        /#ifdef CONFIG_HAVE_SYSCALL_TRACEPOINTS/ {
            if (!done) { print "#ifndef CONFIG_KSU_SUSFS"; print; done=1 } else { print }
            next
        }
        /strscpy\(cmd\.mode, "Kprobes", sizeof\(cmd\.mode\)\);/ {
            print; getline; print
            print "#elif defined(CONFIG_HAVE_SYSCALL_TRACEPOINTS) || defined(CONFIG_KPROBES)"
            print "\tstrscpy(cmd.mode, \"Hybrid\", sizeof(cmd.mode));"
            print "#else\n\tstrscpy(cmd.mode, \"Inline\", sizeof(cmd.mode));\n#endif"
            next
        }
        1' kernel/supercall/dispatch.c > tmp.c && mv tmp.c kernel/supercall/dispatch.c

        # 9. kernel/runtime/boot_event.c (Inject input hook static key and preserve ksu_boot_completed)
        awk '/bool ksu_boot_completed __read_mostly = false;/ {
            print $0
            print "\n#ifdef CONFIG_KSU_SUSFS\nextern struct static_key_true ksu_is_input_hook_enabled;\n#endif"
            next
        }
        1' kernel/runtime/boot_event.c > tmp.c && mv tmp.c kernel/runtime/boot_event.c
        
        # 10. kernel/feature/selinux_hide.c (Remove static from drop_backup for 6.6 linkage)
        if [ -f kernel/feature/selinux_hide.c ]; then
            awk '{ gsub(/static void ksu_selinux_hide_drop_backup_if_unused/, "void ksu_selinux_hide_drop_backup_if_unused"); print }' kernel/feature/selinux_hide.c > tmp.c && mv tmp.c kernel/feature/selinux_hide.c
        fi

        # 11. kernel/feature/sucompat.h (Inject missing forward declarations and function signatures)
        awk '
        BEGIN {
            print "struct pt_regs;"
            print "struct user_arg_ptr;"
        }
        { print }
        END {
            print "long ksu_handle_stat_sucompat(int orig_nr, struct pt_regs *regs);"
            print "long ksu_handle_faccessat_sucompat(int orig_nr, struct pt_regs *regs);"
            print "long ksu_handle_execve_sucompat(const char __user **filename_user, int orig_nr, struct pt_regs *regs);"
        }
        ' kernel/feature/sucompat.h > tmp.h && mv tmp.h kernel/feature/sucompat.h

        # 12. Upgrade SukiSU-Ultra's adb_root module to match Next's modernized signature
        echo ">>> Upgrading SukiSU-Ultra adb_root to Next standard to preserve toggle functionality..."
        curl -sL "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/main/kernel/feature/adb_root.c" -o kernel/feature/adb_root.c
        curl -sL "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/main/kernel/feature/adb_root.h" -o kernel/feature/adb_root.h

        # 13. kernel/hook/syscall_event_bridge.c (Fix old_uid unused var)
        awk '
        /uid_t old_uid = current_uid\(\)\.val;/ {
            print $0 " (void)old_uid;"
            next
        }
        1' kernel/hook/syscall_event_bridge.c > tmp.c && mv tmp.c kernel/hook/syscall_event_bridge.c

        # Cleanup rejected files so the workspace is pristine for compilation
        find . -name "*.rej" -type f -delete
        echo ">>> SukiSU-Ultra awk fixups applied successfully!"
    else
        echo ">>> Patch applied cleanly!"
    fi
    
    cd ../..
fi

# ==========================================
# Universal Feature Auto-Enabler
# ==========================================
echo ">>> Scanning KernelSU variant for optional features..."
KSU_KCONFIG="kernel_workspace/KernelSU/kernel/Kconfig"
GKI_DEFCONFIG_ARM64="kernel_workspace/common/arch/arm64/configs/gki_defconfig"
GKI_DEFCONFIG_X86="kernel_workspace/common/arch/x86/configs/gki_defconfig"

# Check if the variant's Kconfig natively supports KPM
if [ -f "$KSU_KCONFIG" ] && grep -q "config KPM" "$KSU_KCONFIG"; then
    echo ">>> KPM (Kernel Patch Manager) support detected! Auto-enabling CONFIG_KPM in GKI defconfigs..."
    
    # Inject into ARM64
    if [ -f "$GKI_DEFCONFIG_ARM64" ]; then
        sed -i '/CONFIG_KPM/d' "$GKI_DEFCONFIG_ARM64" # Prevent duplicate entries
        echo "CONFIG_KPM=y" >> "$GKI_DEFCONFIG_ARM64"
    fi
    
    # Inject into X86_64 (if building for emulator testing)
    if [ -f "$GKI_DEFCONFIG_X86" ]; then
        sed -i '/CONFIG_KPM/d' "$GKI_DEFCONFIG_X86"
        echo "CONFIG_KPM=y" >> "$GKI_DEFCONFIG_X86"
    fi
else
    echo ">>> KPM not supported by this variant or Kconfig missing. Skipping..."
fi
