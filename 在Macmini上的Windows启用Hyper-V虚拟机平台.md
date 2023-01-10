# 在Macmini上的Windows启用Hyper-V虚拟机平台
1. 下载[rEFInd](https://sourceforge.net/projects/refind/)并解压,以下[参考](http://www.rodsbooks.com/refind/installing.html#windows)
2. 挂载ESP分区`mountvol R: /S`
3. 将`refind-bin-0.13\refind`复制到`R:\EFI\`下
4. 进入`R:\EFI\refind`删除不必要的文件`drivers_aa64`,`drivers_ia32`,`tools_aa64`,`tools_ia32`,`refind_aa64.efi`,`refind_ia32.efi`
5. 将`refind.conf-sample`重命名`refind.conf`,修改这两行
    ```
    timeout 20                     -->     timeout 3
    #enable_and_lock_vmx false     -->     enable_and_lock_vmx true
    ```
6. 将`rEFInd`设为默认EFI启动`bcdedit /set "{bootmgr}" path \EFI\refind\refind_x64.efi`
7. 重启后启用`Hyper-V`和`虚拟机平台`