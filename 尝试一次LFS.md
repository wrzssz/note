# 尝试一次LFS
全文参照[Linux From Scratch](https://www.linuxfromscratch.org/lfs/view/stable/) - Version 11.2
### 准备安装环境
1. 下载[Ubuntu](http://mirrors.ustc.edu.cn/) LiveCD-->新建虚拟机-->选择`Try Ubuntu`
2. 检查安装环境-->运行[脚本](https://www.linuxfromscratch.org/lfs/view/stable/chapter02/hostreqs.html)
3. 配置环境
    ```bash
    apt update -y
    apt install vim texinfo gawk bison g++ make patch -y
    ln -sf bash /bin/sh
    ```
### 分区
1. 使用`GParted`，硬盘/dev/sda一共20G，分两个区`/boot`200M，剩下的都是`/`
2. `/dev/sda1`和`/dev/sda2`均格式化为`ext4`
3. 挂载分区
    ```bash
    export LFS=/mnt/lfs
    mkdir $LFS
    mount /dev/sda2 $LFS
    mkdir $LFS/boot
    mount /dev/sda1 $LFS/boot/
    ```
### 下载软件包
```bash
mkdir $LFS/sources
chmod 1777 $LFS/sources
wget https://www.linuxfromscratch.org/lfs/view/stable/wget-list-sysv
wget -c -i ./wget-list-sysv -P $LFS/sources
# wget -r -p -np -k -e robots=off http://mirrors.ustc.edu.cn/lfs/lfs-packages/11.2/
```
### 准备chroot
1. 创建目录
    ```bash
    mkdir -p $LFS/{etc,var,lib64,tools,usr/{bin,lib,sbin}}
    for i in bin lib sbin; do
        ln -s usr/$i $LFS/$i
    done
    ```
2. 创建用户
    ```bash
    groupadd lfs
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
    passwd lfs
    chown -v lfs $LFS/{usr{,/*},lib64,lib,var,etc,bin,sbin,tools}
    su - lfs
    ```
3. 设置环境变量
    ```bash
    cat > ~/.bash_profile << "EOF"
    exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
    EOF

    cat > ~/.bashrc << "EOF"
    set +h
    umask 022
    LFS=/mnt/lfs
    LC_ALL=POSIX
    LFS_TGT=$(uname -m)-lfs-linux-gnu
    PATH=/usr/bin
    if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
    PATH=$LFS/tools/bin:$PATH
    CONFIG_SITE=$LFS/usr/share/config.site
    export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
    EOF

    source ~/.bash_profile
    ```
### 构建工具链
1. Binutils
    ```bash
    cd $LFS/sources && tar xf binutils-2.39.tar.xz && cd binutils-2.39
    mkdir build && cd build

    ../configure --prefix=$LFS/tools \
                 --with-sysroot=$LFS \
                 --target=$LFS_TGT   \
                 --disable-nls       \
                 --enable-gprofng=no \
                 --disable-werror
    make && make install
    ```
2. GCC
    ```bash
    cd $LFS/sources && tar xf gcc-12.2.0.tar.xz && cd gcc-12.2.0
    tar xf ../mpfr-4.1.0.tar.xz && mv mpfr-4.1.0 mpfr
    tar xf ../gmp-6.2.1.tar.xz && mv gmp-6.2.1 gmp
    tar xf ../mpc-1.2.1.tar.gz && mv mpc-1.2.1 mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    mkdir build && cd build
    
    ../configure --target=$LFS_TGT         \
                 --prefix=$LFS/tools       \
                 --with-glibc-version=2.36 \
                 --with-sysroot=$LFS       \
                 --with-newlib             \
                 --without-headers         \
                 --disable-nls             \
                 --disable-shared          \
                 --disable-multilib        \
                 --disable-decimal-float   \
                 --disable-threads         \
                 --disable-libatomic       \
                 --disable-libgomp         \
                 --disable-libquadmath     \
                 --disable-libssp          \
                 --disable-libvtv          \
                 --disable-libstdcxx       \
                 --enable-languages=c,c++
    make && make install 

    cd .. && cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h
    ```
3. Linux Headers
    ```bash
    cd $LFS/sources && tar xf linux-5.19.2.tar.xz && cd linux-5.19.2
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -r usr/include $LFS/usr
    ```
4. Glibc
    ```bash
    ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
    ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3

    cd $LFS/sources && tar xf glibc-2.36.tar.xz  && cd glibc-2.36
    patch -Np1 -i ../glibc-2.36-fhs-1.patch
    mkdir build && cd build
    echo "rootsbindir=/usr/sbin" > configparms

    ../configure --prefix=/usr                      \
                 --host=$LFS_TGT                    \
                 --build=$(../scripts/config.guess) \
                 --enable-kernel=3.2                \
                 --with-headers=$LFS/usr/include    \
                 libc_cv_slibdir=/usr/lib
    make && make DESTDIR=$LFS install

    sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
    $LFS/tools/libexec/gcc/$LFS_TGT/12.2.0/install-tools/mkheaders
    ```
5. Libstdc++
    ```bash
    cd $LFS/sources && rm -rf gcc-12.2.0 && tar xf gcc-12.2.0.tar.xz && cd gcc-12.2.0
    mkdir build && cd build

    ../libstdc++-v3/configure --host=$LFS_TGT                 \
                              --build=$(../config.guess)      \
                              --prefix=/usr                   \
                              --disable-multilib              \
                              --disable-nls                   \
                              --disable-libstdcxx-pch         \
                              --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/12.2.0
    make && make DESTDIR=$LFS install

    rm $LFS/usr/lib/lib{stdc++,stdc++fs,supc++}.la
    ```
### 编译工具
1. M4
    ```bash
    cd $LFS/sources && tar xf m4-1.4.19.tar.xz && cd m4-1.4.19
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
2. Ncurses
    ```bash
    cd $LFS/sources && tar xf ncurses-6.3.tar.gz  && cd ncurses-6.3
    sed -i s/mawk// ./configure && mkdir build && cd build

    ../configure && make -C include && make -C progs tic && cd ..
    ./configure --prefix=/usr                \
                --host=$LFS_TGT              \
                --build=$(./config.guess)    \
                --mandir=/usr/share/man      \
                --with-manpage-format=normal \
                --with-shared                \
                --without-normal             \
                --with-cxx-shared            \
                --without-debug              \
                --without-ada                \
                --disable-stripping          \
                --enable-widec
    make && make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
    echo "INPUT(-lncursesw)" > $LFS/usr/lib/libncurses.so
    ```
3. Bash
    ```bash
    cd $LFS/sources && tar xf bash-5.1.16.tar.gz && cd bash-5.1.16
    ./configure --prefix=/usr                   \
                --build=$(support/config.guess) \
                --host=$LFS_TGT                 \
                --without-bash-malloc
    make && make DESTDIR=$LFS install
    ln -s bash $LFS/bin/sh
    ```
4. Coreutils
    ```bash
    cd $LFS/sources && tar xf coreutils-9.1.tar.xz && cd coreutils-9.1
    ./configure --prefix=/usr                     \
                --host=$LFS_TGT                   \
                --build=$(build-aux/config.guess) \
                --enable-install-program=hostname \
                --enable-no-install-program=kill,uptime
    make && make DESTDIR=$LFS install

    mv $LFS/usr/bin/chroot $LFS/usr/sbin
    mkdir -p $LFS/usr/share/man/man8
    mv $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' $LFS/usr/share/man/man8/chroot.8
    ```
5. Diffutils
    ```bash
    cd $LFS/sources && tar xf diffutils-3.8.tar.xz && cd diffutils-3.8
    ./configure --prefix=/usr --host=$LFS_TGT
    make && make DESTDIR=$LFS install
    ```
6. File
    ```bash
    cd $LFS/sources && tar xf file-5.42.tar.gz && cd file-5.42
    mkdir build && cd build
    ../configure --disable-bzlib      \
                 --disable-libseccomp \
                 --disable-xzlib      \
                 --disable-zlib
    make && cd ..

    ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
    make FILE_COMPILE=$(pwd)/build/src/file && make DESTDIR=$LFS install
    rm $LFS/usr/lib/libmagic.la
    ```
7. Findutils
    ```bash
    cd $LFS/sources && tar xf findutils-4.9.0.tar.xz && cd findutils-4.9.0
    ./configure --prefix=/usr                   \
                --localstatedir=/var/lib/locate \
                --host=$LFS_TGT                 \
                --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
8. Gawk
    ```bash
    cd $LFS/sources && tar xf gawk-5.1.1.tar.xz && cd gawk-5.1.1
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
9. Grep
    ```bash
    cd $LFS/sources && tar xf grep-3.7.tar.xz && cd grep-3.7
    ./configure --prefix=/usr --host=$LFS_TGT
    make && make DESTDIR=$LFS install
    ```
10. Gzip
    ```bash
    cd $LFS/sources && tar xf gzip-1.12.tar.xz && cd gzip-1.12
    ./configure --prefix=/usr --host=$LFS_TGT
    make && make DESTDIR=$LFS install
    ```
11. Make
    ```bash
    cd $LFS/sources && tar xf make-4.3.tar.gz && cd make-4.3
    ./configure --prefix=/usr   \
                --without-guile \
                --host=$LFS_TGT \
                --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
12. Patch
    ```bash
    cd $LFS/sources && tar xf patch-2.7.6.tar.xz && cd patch-2.7.6
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
13. Sed
    ```bash
    cd $LFS/sources && tar xf sed-4.8.tar.xz && cd sed-4.8
    ./configure --prefix=/usr --host=$LFS_TGT
    make && make DESTDIR=$LFS install
    ```
14. Tar
    ```bash
    cd $LFS/sources && tar xf tar-1.34.tar.xz && cd tar-1.34
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
    make && make DESTDIR=$LFS install
    ```
15. Xz
    ```bash
    cd $LFS/sources && tar xf xz-5.2.6.tar.xz && cd xz-5.2.6
    ./configure --prefix=/usr                     \
                --host=$LFS_TGT                   \
                --build=$(build-aux/config.guess) \
                --disable-static                  \
                --docdir=/usr/share/doc/xz-5.2.6
    make && make DESTDIR=$LFS install
    rm $LFS/usr/lib/liblzma.la
    ```
16. 第二遍Binutils
    ```bash
    cd $LFS/sources && rm -rf binutils-2.39 && tar xf binutils-2.39.tar.xz && cd binutils-2.39
    sed '6009s/$add_dir//' -i ltmain.sh

    mkdir build && cd build
    ../configure --prefix=/usr              \
                 --build=$(../config.guess) \
                 --host=$LFS_TGT            \
                 --disable-nls              \
                 --enable-shared            \
                 --enable-gprofng=no        \
                 --disable-werror           \
                 --enable-64-bit-bfd
    make && make DESTDIR=$LFS install

    rm $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes}.{a,la}
    ```
17. 再来一遍GCC
    ```bash
    cd $LFS/sources && rm -rf gcc-12.2.0 && tar xf gcc-12.2.0.tar.xz && cd gcc-12.2.0
    tar xf ../mpfr-4.1.0.tar.xz && mv mpfr-4.1.0 mpfr
    tar xf ../gmp-6.2.1.tar.xz && mv gmp-6.2.1 gmp
    tar xf ../mpc-1.2.1.tar.gz && mv mpc-1.2.1 mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

    mkdir build && cd build
    ../configure --build=$(../config.guess)                     \
                 --host=$LFS_TGT                                \
                 --target=$LFS_TGT                              \
                 LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
                 --prefix=/usr                                  \
                 --with-build-sysroot=$LFS                      \
                 --enable-initfini-array                        \
                 --disable-nls                                  \
                 --disable-multilib                             \
                 --disable-decimal-float                        \
                 --disable-libatomic                            \
                 --disable-libgomp                              \
                 --disable-libquadmath                          \
                 --disable-libssp                               \
                 --disable-libvtv                               \
                 --enable-languages=c,c++
    make && make DESTDIR=$LFS install

    ln -s gcc $LFS/usr/bin/cc
    ```
### 进入隔离环境
1. 隔离前的准备
    ```bash
    exit # 退回root用户
    chown -R root:root $LFS/{lib64,usr,lib,var,etc,bin,sbin,tools}
    mkdir -p $LFS/{dev,proc,sys,run}

    mount --bind /dev $LFS/dev
    mount --bind /dev/pts $LFS/dev/pts
    mount -t proc proc $LFS/proc
    mount -t sysfs sysfs $LFS/sys
    mount -t tmpfs tmpfs $LFS/run

    chroot "$LFS" /usr/bin/env -i   \
        HOME=/root                  \
        TERM="$TERM"                \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin     \
        /bin/bash --login
    ```
2. 创建各种目录
    ```bash
    mkdir -p /{home,mnt,opt,srv} /etc/{opt,sysconfig}
    mkdir -p /lib/firmware /media/{floppy,cdrom}
    mkdir -p /usr/{,local/}{include,src} /usr/local/{bin,lib,sbin}
    mkdir -p /usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -p /usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -p /usr/{,local/}share/man/man{1..8}
    mkdir -p /var/{cache,local,log,mail,opt,spool}
    mkdir -p /var/lib/{color,misc,locate}

    ln -sf /run /var/run
    ln -sf /run/lock /var/lock

    install -dm 0750 /root
    install -dm 1777 /tmp /var/tmp
    ```
3. 创建各种文件
    ```bash
    ln -s /proc/self/mounts /etc/mtab

    cat > /etc/hosts << EOF
    127.0.0.1  localhost $(hostname)
    ::1        localhost
    EOF

    cat > /etc/passwd << "EOF"
    root:x:0:0:root:/root:/bin/bash
    bin:x:1:1:bin:/dev/null:/usr/bin/false
    daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
    messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
    uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
    nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
    EOF

    cat > /etc/group << "EOF"
    root:x:0:
    bin:x:1:daemon
    sys:x:2:
    kmem:x:3:
    tape:x:4:
    tty:x:5:
    daemon:x:6:
    floppy:x:7:
    disk:x:8:
    lp:x:9:
    dialout:x:10:
    audio:x:11:
    video:x:12:
    utmp:x:13:
    usb:x:14:
    cdrom:x:15:
    adm:x:16:
    messagebus:x:18:
    input:x:24:
    mail:x:34:
    kvm:x:61:
    uuidd:x:80:
    wheel:x:97:
    users:x:999:
    nogroup:x:65534:
    EOF

    exec /usr/bin/bash --login
    touch /var/log/{btmp,lastlog,faillog,wtmp}
    chgrp utmp /var/log/lastlog
    chmod 664 /var/log/lastlog
    chmod 600 /var/log/btmp
    ```
4. Gettext
    ```bash
    cd /sources && tar xf gettext-0.21.tar.xz && cd gettext-0.21
    ./configure --disable-shared
    make && cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
    ```
5. Bison
    ```bash
    cd /sources && tar xf bison-3.8.2.tar.xz && cd bison-3.8.2
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make && make install
    ```
6. Perl
    ```bash
    cd /sources && tar xf perl-5.36.0.tar.xz  && cd perl-5.36.0
    sh Configure -des                                        \
                 -Dprefix=/usr                               \
                 -Dvendorprefix=/usr                         \
                 -Dprivlib=/usr/lib/perl5/5.36/core_perl     \
                 -Darchlib=/usr/lib/perl5/5.36/core_perl     \
                 -Dsitelib=/usr/lib/perl5/5.36/site_perl     \
                 -Dsitearch=/usr/lib/perl5/5.36/site_perl    \
                 -Dvendorlib=/usr/lib/perl5/5.36/vendor_perl \
                 -Dvendorarch=/usr/lib/perl5/5.36/vendor_perl
    make && make install
    ```
7. Python
    ```bash
    cd /sources && tar xf Python-3.10.6.tar.xz && cd Python-3.10.6
    ./configure --prefix=/usr --enable-shared --without-ensurepip
    make && make install
    ```
8. Texinfo
    ```bash
    cd /sources && tar xf texinfo-6.8.tar.xz && cd texinfo-6.8
    ./configure --prefix=/usr
    make && make install 
    ```
9. Util-linux
    ```bash
    cd /sources && tar xf util-linux-2.38.1.tar.xz  && cd util-linux-2.38.1
    mkdir -p /var/lib/hwclock
    ./configure ADJTIME_PATH=/var/lib/hwclock/adjtime    \
                --libdir=/usr/lib    \
                --docdir=/usr/share/doc/util-linux-2.38.1 \
                --disable-chfn-chsh  \
                --disable-login      \
                --disable-nologin    \
                --disable-su         \
                --disable-setpriv    \
                --disable-runuser    \
                --disable-pylibmount \
                --disable-static     \
                --without-python     \
                runstatedir=/run
    make && make install 
    ```
10. 清理环境
    ```bash
    find /sources -maxdepth 1 -mindepth 1 -type d -exec rm -rf {} \;
    find /usr/{lib,libexec} -name \*.la -delete
    rm -rf /usr/share/{info,man,doc}/* /tools
    ```
### 正式编译系统
1. Man-pages
    ```bash
    cd /sources && tar xf man-pages-5.13.tar.xz && cd man-pages-5.13
    make prefix=/usr install
    ```
2. Iana-Etc
    ```bash
    cd /sources && tar xf iana-etc-20220812.tar.gz && cd iana-etc-20220812
    cp services protocols /etc
    ```
3. Glibc
    ```bash
    cd /sources && tar xf glibc-2.36.tar.xz  && cd glibc-2.36
    patch -Np1 -i ../glibc-2.36-fhs-1.patch
    mkdir build && cd build
    echo "rootsbindir=/usr/sbin" > configparms

    ../configure --prefix=/usr                            \
                 --disable-werror                         \
                 --enable-kernel=3.2                      \
                 --enable-stack-protector=strong          \
                 --with-headers=/usr/include              \
                 libc_cv_slibdir=/usr/lib
    make
    touch /etc/ld.so.conf
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
    cp ../nscd/nscd.conf /etc/nscd.conf && mkdir -p /var/cache/nscd

    mkdir -p /usr/lib/locale
    localedef -i POSIX -f UTF-8 C.UTF-8
    localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
    localedef -i de_DE -f ISO-8859-1 de_DE
    localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
    localedef -i de_DE -f UTF-8 de_DE.UTF-8
    localedef -i el_GR -f ISO-8859-7 el_GR
    localedef -i en_GB -f ISO-8859-1 en_GB
    localedef -i en_GB -f UTF-8 en_GB.UTF-8
    localedef -i en_HK -f ISO-8859-1 en_HK
    localedef -i en_PH -f ISO-8859-1 en_PH
    localedef -i en_US -f ISO-8859-1 en_US
    localedef -i en_US -f UTF-8 en_US.UTF-8
    localedef -i es_ES -f ISO-8859-15 es_ES@euro
    localedef -i es_MX -f ISO-8859-1 es_MX
    localedef -i fa_IR -f UTF-8 fa_IR
    localedef -i fr_FR -f ISO-8859-1 fr_FR
    localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
    localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
    localedef -i is_IS -f ISO-8859-1 is_IS
    localedef -i is_IS -f UTF-8 is_IS.UTF-8
    localedef -i it_IT -f ISO-8859-1 it_IT
    localedef -i it_IT -f ISO-8859-15 it_IT@euro
    localedef -i it_IT -f UTF-8 it_IT.UTF-8
    localedef -i ja_JP -f EUC-JP ja_JP
    localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS
    localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
    localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
    localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
    localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
    localedef -i se_NO -f UTF-8 se_NO.UTF-8
    localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
    localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
    localedef -i zh_CN -f GB18030 zh_CN.GB18030
    localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
    localedef -i zh_TW -f UTF-8 zh_TW.UTF-8
    make localedata/install-locales
    localedef -i POSIX -f UTF-8 C.UTF-8
    localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS

    cat > /etc/nsswitch.conf << "EOF"
    # Begin /etc/nsswitch.conf

    passwd: files
    group: files
    shadow: files

    hosts: files dns
    networks: files

    protocols: files
    services: files
    ethers: files
    rpc: files

    # End /etc/nsswitch.conf
    EOF

    tar xf ../../tzdata2022c.tar.gz
    ZONEINFO=/usr/share/zoneinfo
    mkdir -p $ZONEINFO/{posix,right}
    for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
        zic -L /dev/null -d $ZONEINFO ${tz}
        zic -L /dev/null -d $ZONEINFO/posix ${tz}
        zic -L leapseconds -d $ZONEINFO/right ${tz}
    done
    cp zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York
    unset ZONEINFO
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    cat > /etc/ld.so.conf << "EOF"
    # Begin /etc/ld.so.conf
    /usr/local/lib
    /opt/lib
    # Add an include directory
    include /etc/ld.so.conf.d/*.conf
    EOF
    mkdir -p /etc/ld.so.conf.d
    ```
4. Zlib
    ```bash
    cd /sources && tar xf zlib-1.2.12.tar.xz && cd zlib-1.2.12
    ./configure --prefix=/usr
    make && make install 
    rm -f /usr/lib/libz.a 
    ```
5. Bzip2
    ```bash
    cd /sources && tar xf bzip2-1.0.8.tar.gz && cd bzip2-1.0.8
    patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

    make -f Makefile-libbz2_so && make clean
    make && make PREFIX=/usr install

    cp -a libbz2.so.* /usr/lib
    ln -s libbz2.so.1.0.8 /usr/lib/libbz2.so
    cp bzip2-shared /usr/bin/bzip2
    for i in /usr/bin/{bzcat,bunzip2}; do
        ln -sf bzip2 $i
    done
    rm -f /usr/lib/libbz2.a
    ```
6. Xz
    ```bash
    cd /sources && tar xf xz-5.2.6.tar.xz && cd xz-5.2.6
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz-5.2.6
    make && make install 
    ```
7. Zstd
    ```bash
    cd /sources && tar xf zstd-1.5.2.tar.gz && cd zstd-1.5.2
    patch -Np1 -i ../zstd-1.5.2-upstream_fixes-1.patch
    make prefix=/usr && make prefix=/usr install
    rm /usr/lib/libzstd.a
    ```
8. File
    ```bash
    cd /sources && tar xf file-5.42.tar.gz && cd file-5.42
    ./configure --prefix=/usr
    make && make install 
    ```
9. Readline
    ```bash
    cd /sources && tar xf readline-8.1.2.tar.gz && cd readline-8.1.2
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install

    ./configure --prefix=/usr    \
                --disable-static \
                --with-curses    \
                --docdir=/usr/share/doc/readline-8.1.2
    make SHLIB_LIBS="-lncursesw" && make SHLIB_LIBS="-lncursesw" install
    install -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.1.2
    ```
10. M4
    ```bash
    cd /sources && tar xf m4-1.4.19.tar.xz && cd m4-1.4.19
    ./configure --prefix=/usr
    make && make install 
    ```
11. Bc
    ```bash
    cd /sources && tar xf bc-6.0.1.tar.xz && cd bc-6.0.1
    CC=gcc ./configure --prefix=/usr -G -O3 -r
    make && make install 
    ```
12. Flex
    ```bash
    cd /sources && tar xf flex-2.6.4.tar.gz && cd flex-2.6.4
    ./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.6.4 --disable-static
    make && make install
    ln -s flex /usr/bin/lex
    ```
13. Tcl
    ```bash
    cd /sources && tar xf tcl8.6.12-src.tar.gz && cd tcl8.6.12
    tar xf ../tcl8.6.12-html.tar.gz --strip-components=1

    SRCDIR=$(pwd) && cd unix
    ./configure --prefix=/usr --mandir=/usr/share/man
    make
    sed -e "s|$SRCDIR/unix|/usr/lib|" \
        -e "s|$SRCDIR|/usr/include|"  \
        -i tclConfig.sh
    sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.3|/usr/lib/tdbc1.1.3|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.3/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/tdbc1.1.3/library|/usr/lib/tcl8.6|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.3|/usr/include|"            \
        -i pkgs/tdbc1.1.3/tdbcConfig.sh
    sed -e "s|$SRCDIR/unix/pkgs/itcl4.2.2|/usr/lib/itcl4.2.2|" \
        -e "s|$SRCDIR/pkgs/itcl4.2.2/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/itcl4.2.2|/usr/include|"            \
        -i pkgs/itcl4.2.2/itclConfig.sh
    unset SRCDIR
    make install

    chmod u+w /usr/lib/libtcl8.6.so
    make install-private-headers
    ln -sf tclsh8.6 /usr/bin/tclsh
    mv /usr/share/man/man3/{Thread,Tcl_Thread}.3

    mkdir -p /usr/share/doc/tcl-8.6.12
    cp -r  ../html/* /usr/share/doc/tcl-8.6.12
    ```
14. Expect
    ```bash
    cd /sources && tar xf expect5.45.4.tar.gz && cd expect5.45.4
    ./configure --prefix=/usr           \
                --with-tcl=/usr/lib     \
                --enable-shared         \
                --mandir=/usr/share/man \
                --with-tclinclude=/usr/include
    make && make install 
    ln -sf expect5.45.4/libexpect5.45.4.so /usr/lib
    ```
15. DejaGNU
    ```bash
    cd /sources && tar xf dejagnu-1.6.3.tar.gz && cd dejagnu-1.6.3
    mkdir build && cd build
    ../configure --prefix=/usr
    makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
    makeinfo --plaintext -o doc/dejagnu.txt ../doc/dejagnu.texi
    make install
    install -dm755 /usr/share/doc/dejagnu-1.6.3
    install -m644 doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
    ```
16. Binutils
    ```bash
    cd /sources && tar xf binutils-2.39.tar.xz && cd binutils-2.39
    mkdir build && cd build
    ../configure --prefix=/usr       \
                --sysconfdir=/etc   \
                --enable-gold       \
                --enable-ld=default \
                --enable-plugins    \
                --enable-shared     \
                --disable-werror    \
                --enable-64-bit-bfd \
                --with-system-zlib
    make tooldir=/usr && make tooldir=/usr install
    rm -f /usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes}.a
    ```
17. GMP
    ```bash
    cd /sources && tar xf gmp-6.2.1.tar.xz && cd gmp-6.2.1
    ./configure --prefix=/usr    \
                --enable-cxx     \
                --disable-static \
                --docdir=/usr/share/doc/gmp-6.2.1
    make && make html && make install && make install-html
    ```
18. MPFR
    ```bash
    cd /sources && tar xf mpfr-4.1.0.tar.xz && cd mpfr-4.1.0
    ./configure --prefix=/usr        \
                --disable-static     \
                --enable-thread-safe \
                --docdir=/usr/share/doc/mpfr-4.1.0
    make && make html && make install && make install-html
    ```
19. MPC
    ```bash
    cd /sources && tar xf mpc-1.2.1.tar.gz && cd mpc-1.2.1
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpc-1.2.1
    make && make html && make install && make install-html
    ```
20. Attr
    ```bash
    cd /sources && tar xf attr-2.5.1.tar.gz && cd attr-2.5.1
    ./configure --prefix=/usr     \
                --disable-static  \
                --sysconfdir=/etc \
                --docdir=/usr/share/doc/attr-2.5.1
    make && make install 
    ```
21. Acl
    ```bash
    cd /sources && tar xf acl-2.3.1.tar.xz && cd acl-2.3.1
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/acl-2.3.1
    make && make install 
    ```
22. Libcap
    ```bash
    cd /sources && tar xf libcap-2.65.tar.xz && cd libcap-2.65
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib && make prefix=/usr lib=lib install
    ```
23. Shadow
    ```bash
    cd /sources && tar xf shadow-4.12.2.tar.xz && cd shadow-4.12.2
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD SHA512:' \
        -e 's:/var/spool/mail:/var/mail:'                 \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                \
        -i etc/login.defs
    touch /usr/bin/passwd

    ./configure --sysconfdir=/etc --disable-static --with-group-name-max-length=32
    make && make exec_prefix=/usr install && make -C man install-man

    pwconv && grpconv
    mkdir -p /etc/default && useradd -D --gid 999
    passwd
    ```
24. GCC
    ```bash
    cd /sources && tar xf gcc-12.2.0.tar.xz && cd gcc-12.2.0
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64

    mkdir build && cd build
    ../configure --prefix=/usr            \
                LD=ld                    \
                --enable-languages=c,c++ \
                --disable-multilib       \
                --disable-bootstrap      \
                --with-system-zlib
    make && make install

    ln -sr /usr/bin/cpp /usr/lib
    ln -sf ../../libexec/gcc/$(gcc -dumpmachine)/12.2.0/liblto_plugin.so /usr/lib/bfd-plugins/
    mkdir -p /usr/share/gdb/auto-load/usr/lib
    mv /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
    ```
25. Pkg-config
    ```bash
    cd /sources && tar xf pkg-config-0.29.2.tar.gz && cd pkg-config-0.29.2
    ./configure --prefix=/usr              \
                --with-internal-glib       \
                --disable-host-tool        \
                --docdir=/usr/share/doc/pkg-config-0.29.2
    make && make install 
    ```
26. Ncurses
    ```bash
    cd /sources && tar xf ncurses-6.3.tar.gz && cd ncurses-6.3
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --with-shared           \
                --without-debug         \
                --without-normal        \
                --with-cxx-shared       \
                --enable-pc-files       \
                --enable-widec          \
                --with-pkg-config-libdir=/usr/lib/pkgconfig
    make && make DESTDIR=$PWD/dest install
    install -m755 dest/usr/lib/libncursesw.so.6.3 /usr/lib
    rm dest/usr/lib/libncursesw.so.6.3
    cp -a dest/* /

    rm -f /usr/lib/lib{ncurses,form,panel,menu,cursesw}.so
    echo "INPUT(-lncursesw)" > /usr/lib/libncurses.so
    echo "INPUT(-lformw)" > /usr/lib/libform.so
    echo "INPUT(-lpanelw)" > /usr/lib/libpanel.so
    echo "INPUT(-lmenuw)" > /usr/lib/libmenu.so
    echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so
    ln -sf ncursesw.pc /usr/lib/pkgconfig/ncurses.pc
    ln -sf formw.pc /usr/lib/pkgconfig/form.pc
    ln -sf panelw.pc /usr/lib/pkgconfig/panel.pc
    ln -sf menuw.pc /usr/lib/pkgconfig/menu.pc
    ln -sf libncurses.so /usr/lib/libcurses.so
    mkdir -p /usr/share/doc/ncurses-6.3
    cp -R doc/* /usr/share/doc/ncurses-6.3
    ```
27. Sed
    ```bash
    cd /sources && tar xf sed-4.8.tar.xz && cd sed-4.8
    ./configure --prefix=/usr
    make && make html && make install
    install -dm755 /usr/share/doc/sed-4.8
    install -m644 doc/sed.html /usr/share/doc/sed-4.8
    ```
28. Psmisc
    ```bash
    cd /sources && tar xf psmisc-23.5.tar.xz && cd psmisc-23.5
    ./configure --prefix=/usr
    make && make install 
    ```
29. Gettext
    ```bash
    cd /sources && tar xf gettext-0.21.tar.xz && cd gettext-0.21
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext-0.21
    make && make install && chmod 0755 /usr/lib/preloadable_libintl.so
    ```
30. Bison
    ```bash
    cd /sources && tar xf bison-3.8.2.tar.xz && cd bison-3.8.2
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make && make install 
    ```
31. Grep
    ```bash
    cd /sources && tar xf grep-3.7.tar.xz && cd grep-3.7
    ./configure --prefix=/usr
    make && make install
    ```
32. Bash
    ```bash
    cd /sources && tar xf bash-5.1.16.tar.gz && cd bash-5.1.16
    ./configure --prefix=/usr                      \
                --docdir=/usr/share/doc/bash-5.1.16 \
                --without-bash-malloc              \
                --with-installed-readline
    make && make install
    exec /usr/bin/bash --login
    ```
33. Libtool
    ```bash
    cd /sources && tar xf libtool-2.4.7.tar.xz && cd libtool-2.4.7
    ./configure --prefix=/usr
    make && make install
    rm -f /usr/lib/libltdl.a
    ```
34. GDBM
    ```bash
    cd /sources && tar xf gdbm-1.23.tar.gz && cd gdbm-1.23
    ./configure --prefix=/usr --disable-static --enable-libgdbm-compat
    make && make install 
    ```
35. Gperf
    ```bash
    cd /sources && tar xf gperf-3.1.tar.gz && cd gperf-3.1
    ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.1
    make && make install
    ```
36. Expat
    ```bash
    cd /sources && tar xf expat-2.4.8.tar.xz && cd expat-2.4.8
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/expat-2.4.8
    make && make install
    install -m644 doc/*.{html,css} /usr/share/doc/expat-2.4.8
    ```
37. Inetutils
    ```bash
    cd /sources && tar xf inetutils-2.3.tar.xz && cd inetutils-2.3
    ./configure --prefix=/usr        \
                --bindir=/usr/bin    \
                --localstatedir=/var \
                --disable-logger     \
                --disable-whois      \
                --disable-rcp        \
                --disable-rexec      \
                --disable-rlogin     \
                --disable-rsh        \
                --disable-servers
    make && make install
    mv /usr/{,s}bin/ifconfig
    ```
38. Less
    ```bash
    cd /sources && tar xf less-590.tar.gz && cd less-590
    ./configure --prefix=/usr --sysconfdir=/etc
    make && make install
    ```
39. Perl
    ```bash
    cd /sources && tar xf perl-5.36.0.tar.xz && cd perl-5.36.0
    export BUILD_ZLIB=False
    export BUILD_BZIP2=0
    sh Configure -des                                         \
                -Dprefix=/usr                                \
                -Dvendorprefix=/usr                          \
                -Dprivlib=/usr/lib/perl5/5.36/core_perl      \
                -Darchlib=/usr/lib/perl5/5.36/core_perl      \
                -Dsitelib=/usr/lib/perl5/5.36/site_perl      \
                -Dsitearch=/usr/lib/perl5/5.36/site_perl     \
                -Dvendorlib=/usr/lib/perl5/5.36/vendor_perl  \
                -Dvendorarch=/usr/lib/perl5/5.36/vendor_perl \
                -Dman1dir=/usr/share/man/man1                \
                -Dman3dir=/usr/share/man/man3                \
                -Dpager="/usr/bin/less -isR"                 \
                -Duseshrplib                                 \
                -Dusethreads
    make && make install
    unset BUILD_ZLIB BUILD_BZIP2
    ```
40. XML::Parser
    ```bash
    cd /sources && tar xf XML-Parser-2.46.tar.gz && cd XML-Parser-2.46
    perl Makefile.PL
    make && make install
    ```
41. Intltool
    ```bash
    cd /sources && tar xf intltool-0.51.0.tar.gz && cd intltool-0.51.0
    sed -i 's:\\\${:\\\$\\{:' intltool-update.in
    ./configure --prefix=/usr
    make && make install
    install -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
    ```
42. Autoconf
    ```bash
    cd /sources && tar xf autoconf-2.71.tar.xz && cd autoconf-2.71
    ./configure --prefix=/usr
    make && make install
    ```
43. Automake
    ```bash
    cd /sources && tar xf automake-1.16.5.tar.xz && cd automake-1.16.5
    ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.16.5
    make && make install
    ```
44. OpenSSL
    ```bash
    cd /sources && tar xf openssl-3.0.5.tar.gz && cd openssl-3.0.5
    ./config --prefix=/usr         \
            --openssldir=/etc/ssl \
            --libdir=lib          \
            shared                \
            zlib-dynamic
    make
    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make MANSUFFIX=ssl install
    mv /usr/share/doc/openssl /usr/share/doc/openssl-3.0.5
    cp -fr doc/* /usr/share/doc/openssl-3.0.5
    ```
45. Kmod
    ```bash
    cd /sources && tar xf kmod-30.tar.xz && cd kmod-30
    ./configure --prefix=/usr          \
                --sysconfdir=/etc      \
                --with-openssl         \
                --with-xz              \
                --with-zstd            \
                --with-zlib
    make && make install

    for target in depmod insmod modinfo modprobe rmmod; do
        ln -sf ../bin/kmod /usr/sbin/$target
    done
    ln -sf kmod /usr/bin/lsmod
    ```
46. Libelf
    ```bash
    cd /sources && tar xf elfutils-0.187.tar.bz2 && cd elfutils-0.187
    ./configure --prefix=/usr                \
                --disable-debuginfod         \
                --enable-libdebuginfod=dummy
    make && make -C libelf install
    install -m644 config/libelf.pc /usr/lib/pkgconfig
    rm /usr/lib/libelf.a
    ```
47. Libffi
    ```bash
    cd /sources && tar xf libffi-3.4.2.tar.gz && cd libffi-3.4.2
    ./configure --prefix=/usr          \
                --disable-static       \
                --with-gcc-arch=native \
                --disable-exec-static-tramp
    make && make install
    ```
48. Python 3
    ```bash
    cd /sources && tar xf Python-3.10.6.tar.xz && cd Python-3.10.6
    ./configure --prefix=/usr        \
                --enable-shared      \
                --with-system-expat  \
                --with-system-ffi    \
                --enable-optimizations
    make && make install

    install -dm755 /usr/share/doc/python-3.10.6/html
    tar --strip-components=1  \
        --no-same-owner       \
        --no-same-permissions \
        -C /usr/share/doc/python-3.10.6/html \
        -xf ../python-3.10.6-docs-html.tar.bz2

    cat > /etc/pip.conf << EOF
    [global]
    root-user-action = ignore
    disable-pip-version-check = true
    EOF

    tar xf ../wheel-0.37.1.tar.gz && cd wheel-0.37.1
    pip3 install --no-index $PWD
    ```
49. Ninja
    ```bash
    cd /sources && tar xf ninja-1.11.0.tar.gz && cd ninja-1.11.0
    python3 configure.py --bootstrap
    install -m755 ninja /usr/bin/
    install -Dm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
    install -Dm644 misc/zsh-completion /usr/share/zsh/site-functions/_ninja
    ```
50. Meson
    ```bash
    cd /sources && tar xf meson-0.63.1.tar.gz && cd meson-0.63.1
    pip3 wheel -w dist --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist meson
    install -Dm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
    install -Dm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
    ```
51. Coreutils
    ```bash
    cd /sources && tar xf coreutils-9.1.tar.xz && cd coreutils-9.1
    patch -Np1 -i ../coreutils-9.1-i18n-1.patch
    autoreconf -fiv
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --enable-no-install-program=kill,uptime
    make && make install

    mv /usr/bin/chroot /usr/sbin
    mv /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
    ```
52. Check
    ```bash
    cd /sources && tar xf check-0.15.2.tar.gz && cd check-0.15.2
    ./configure --prefix=/usr --disable-static
    make && make docdir=/usr/share/doc/check-0.15.2 install
    ```
53. Diffutils
    ```bash
    cd /sources && tar xf diffutils-3.8.tar.xz && cd diffutils-3.8
    ./configure --prefix=/usr
    make && make install
    ```
54. Gawk
    ```bash
    cd /sources && tar xf gawk-5.1.1.tar.xz && cd gawk-5.1.1
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr
    make && make install
    mkdir -p /usr/share/doc/gawk-5.1.1
    cp doc/{awkforai.txt,*.{eps,pdf,jpg}} /usr/share/doc/gawk-5.1.1
    ```
55. Findutils
    ```bash
    cd /sources && tar xf findutils-4.9.0.tar.xz && cd findutils-4.9.0
    ./configure --prefix=/usr --localstatedir=/var/lib/locate
    make && make install
    ```
56. Groff
    ```bash
    cd /sources && tar xf groff-1.22.4.tar.gz && cd groff-1.22.4
    PAGE=A4 ./configure --prefix=/usr
    make -j1 && make install
    ```
57. GRUB
    ```bash
    cd /sources && tar xf grub-2.06.tar.xz && cd grub-2.06
    ./configure --prefix=/usr          \
                --sysconfdir=/etc      \
                --disable-efiemu       \
                --disable-werror
    make && make install
    mv /etc/bash_completion.d/grub /usr/share/bash-completion/completions
    ```
58. Gzip
    ```bash
    cd /sources && tar xf gzip-1.12.tar.xz && cd gzip-1.12
    ./configure --prefix=/usr
    make && make install
    ```
59. IPRoute2
    ```bash
    cd /sources && tar xf iproute2-5.19.0.tar.xz && cd iproute2-5.19.0
    sed -i /ARPD/d Makefile && rm -f man/man8/arpd.8
    ./configure --prefix=/usr
    make NETNS_RUN_DIR=/run/netns && make SBINDIR=/usr/sbin install
    mkdir -p /usr/share/doc/iproute2-5.19.0
    cp COPYING README* /usr/share/doc/iproute2-5.19.0
    ```
60. Kbd
    ```bash
    cd /sources && tar xf kbd-2.5.1.tar.xz && cd kbd-2.5.1
    patch -Np1 -i ../kbd-2.5.1-backspace-1.patch
    sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
    sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
    ./configure --prefix=/usr --disable-vlock
    make && make install
    mkdir -p /usr/share/doc/kbd-2.5.1
    cp -R docs/doc/* /usr/share/doc/kbd-2.5.1
    ```
61. Libpipeline
    ```bash
    cd /sources && tar xf libpipeline-1.5.6.tar.gz && cd libpipeline-1.5.6
    ./configure --prefix=/usr
    make && make install
    ```
62. Make
    ```bash
    cd /sources && tar xf make-4.3.tar.gz && cd make-4.3
    ./configure --prefix=/usr
    make && make install
    ```
63. Patch
    ```bash
    cd /sources && tar xf patch-2.7.6.tar.xz && cd patch-2.7.6
    ./configure --prefix=/usr
    make && make install
    ```
64. Tar
    ```bash
    cd /sources && tar xf tar-1.34.tar.xz && cd tar-1.34
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
    make && make install && make -C doc install-html docdir=/usr/share/doc/tar-1.34
    ```
65. Texinfo
    ```bash
    cd /sources && tar xf texinfo-6.8.tar.xz && cd texinfo-6.8
    ./configure --prefix=/usr
    make && make install && make TEXMF=/usr/share/texmf install-tex
    cd /usr/share/info && rm dir
    for f in *; do install-info $f dir; done
    ```
66. Vim
    ```bash
    cd /sources && tar xf vim-9.0.0228.tar.gz && cd vim-9.0.0228
    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
    ./configure --prefix=/usr
    make && make install
    ln -s ../vim/vim90/doc /usr/share/doc/vim-9.0.0228

    cat > /etc/vimrc << "EOF"
    " Begin /etc/vimrc

    " Ensure defaults are set before customizing settings, not after
    source $VIMRUNTIME/defaults.vim
    let skip_defaults_vim=1

    set nocompatible
    set backspace=2
    set mouse=
    syntax on
    if (&term == "xterm") || (&term == "putty")
    set background=dark
    endif

    " End /etc/vimrc
    EOF
    ```
67. Eudev
    ```bash
    cd /sources && tar xf eudev-3.2.11.tar.gz && cd eudev-3.2.11
    ./configure --prefix=/usr           \
                --bindir=/usr/sbin      \
                --sysconfdir=/etc       \
                --enable-manpages       \
                --disable-static
    make
    mkdir -p /usr/lib/udev/rules.d /etc/udev/rules.d
    make install

    tar xf ../udev-lfs-20171102.tar.xz
    make -f udev-lfs-20171102/Makefile.lfs install
    udevadm hwdb --update
    ```
68. Man-DB
    ```bash
    cd /sources && tar xf man-db-2.10.2.tar.xz && cd man-db-2.10.2
    ./configure --prefix=/usr                         \
                --docdir=/usr/share/doc/man-db-2.10.2 \
                --sysconfdir=/etc                     \
                --disable-setuid                      \
                --enable-cache-owner=bin              \
                --with-browser=/usr/bin/lynx          \
                --with-vgrind=/usr/bin/vgrind         \
                --with-grap=/usr/bin/grap             \
                --with-systemdtmpfilesdir=            \
                --with-systemdsystemunitdir=
    make && make install
    ```
69. Procps-ng
    ```bash
    cd /sources && tar xf procps-ng-4.0.0.tar.xz && cd procps-ng-4.0.0
    ./configure --prefix=/usr                            \
                --docdir=/usr/share/doc/procps-ng-4.0.0 \
                --disable-static                         \
                --disable-kill
    make && make install
    ```
70. Util-linux
    ```bash
    cd /sources && tar xf util-linux-2.38.1.tar.xz && cd util-linux-2.38.1
    ./configure ADJTIME_PATH=/var/lib/hwclock/adjtime   \
                --bindir=/usr/bin    \
                --libdir=/usr/lib    \
                --sbindir=/usr/sbin  \
                --docdir=/usr/share/doc/util-linux-2.38.1 \
                --disable-chfn-chsh  \
                --disable-login      \
                --disable-nologin    \
                --disable-su         \
                --disable-setpriv    \
                --disable-runuser    \
                --disable-pylibmount \
                --disable-static     \
                --without-python     \
                --without-systemd    \
                --without-systemdsystemunitdir
    make && make install
    ```
71. E2fsprogs
    ```bash
    cd /sources && tar xf e2fsprogs-1.46.5.tar.gz && cd e2fsprogs-1.46.5
    mkdir build && cd build
    ../configure --prefix=/usr           \
                --sysconfdir=/etc       \
                --enable-elf-shlibs     \
                --disable-libblkid      \
                --disable-libuuid       \
                --disable-uuidd         \
                --disable-fsck
    make && make install
    rm -f /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
    gunzip /usr/share/info/libext2fs.info.gz
    install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
    makeinfo -o doc/com_err.info ../lib/et/com_err.texinfo
    install -m644 doc/com_err.info /usr/share/info
    install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
    ```
72. Sysklogd
    ```bash
    cd /sources && tar xf sysklogd-1.5.1.tar.gz && cd sysklogd-1.5.1
    sed -i '/Error loading kernel symbols/{n;n;d}' ksym_mod.c
    sed -i 's/union wait/int/' syslogd.c
    make && make BINDIR=/sbin install

    cat > /etc/syslog.conf << "EOF"
    # Begin /etc/syslog.conf

    auth,authpriv.* -/var/log/auth.log
    *.*;auth,authpriv.none -/var/log/sys.log
    daemon.* -/var/log/daemon.log
    kern.* -/var/log/kern.log
    mail.* -/var/log/mail.log
    user.* -/var/log/user.log
    *.emerg *

    # End /etc/syslog.conf
    EOF
    ```
73. Sysvinit
    ```bash
    cd /sources && tar xf sysvinit-3.04.tar.xz && cd sysvinit-3.04
    patch -Np1 -i ../sysvinit-3.04-consolidated-1.patch
    make && make install
    ```
74. 运行[脚本](https://www.linuxfromscratch.org/lfs/view/stable/chapter08/stripping.html)除去调试符号
75. 清理
    ```bash
    rm -rf /tmp/*
    find /usr/lib /usr/libexec -name \*.la -delete
    find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
    ```
### 配置系统
1. 安装一些脚本
    ```bash
    cd /sources && tar xf lfs-bootscripts-20220723.tar.xz && cd lfs-bootscripts-20220723
    make install
    ```
2. 设备管理器
    ```bash
    bash /usr/lib/udev/init-net-rules.sh
    ```
3. 配置网络
    ```bash
    cat > /etc/sysconfig/ifconfig.eth0 << "EOF"
    ONBOOT=yes
    IFACE=eth0
    SERVICE=ipv4-static
    IP=192.168.100.66
    GATEWAY=192.168.100.1
    PREFIX=24
    BROADCAST=192.168.100.255
    EOF

    cat > /etc/resolv.conf << "EOF"
    domain lfs.server
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    EOF

    cat > /etc/hosts << "EOF"
    127.0.0.1 localhost.localdomain localhost
    ::1       localhost ip6-localhost ip6-loopback
    ff02::1   ip6-allnodes
    ff02::2   ip6-allrouters
    EOF

    echo "lfs" > /etc/hostname
    ```
4. 配置服务
    ```bash
    cat > /etc/inittab << "EOF"
    # Begin /etc/inittab

    id:3:initdefault:

    si::sysinit:/etc/rc.d/init.d/rc S

    l0:0:wait:/etc/rc.d/init.d/rc 0
    l1:S1:wait:/etc/rc.d/init.d/rc 1
    l2:2:wait:/etc/rc.d/init.d/rc 2
    l3:3:wait:/etc/rc.d/init.d/rc 3
    l4:4:wait:/etc/rc.d/init.d/rc 4
    l5:5:wait:/etc/rc.d/init.d/rc 5
    l6:6:wait:/etc/rc.d/init.d/rc 6

    ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

    su:S06:once:/sbin/sulogin
    s1:1:respawn:/sbin/sulogin

    1:2345:respawn:/sbin/agetty --noclear tty1 9600
    2:2345:respawn:/sbin/agetty tty2 9600
    3:2345:respawn:/sbin/agetty tty3 9600
    4:2345:respawn:/sbin/agetty tty4 9600
    5:2345:respawn:/sbin/agetty tty5 9600
    6:2345:respawn:/sbin/agetty tty6 9600

    # End /etc/inittab
    EOF
    ```
5. 配置时钟
    ```bash
    cat > /etc/sysconfig/clock << "EOF"
    # Begin /etc/sysconfig/clock

    UTC=1

    # Set this to any options you might need to give to hwclock,
    # such as machine hardware clock type for Alphas.
    CLOCKPARAMS=

    # End /etc/sysconfig/clock
    EOF
    ```
6. 配置控制台
    ```bash
    cat > /etc/sysconfig/console << "EOF"
    UNICODE="1"
    KEYMAP="es"
    FONT="lat1-16 -m 8859-1"
    EOF

    LC_ALL=en_GB.iso88591 locale language
    LC_ALL=en_GB.iso88591 locale charmap
    LC_ALL=en_GB.iso88591 locale int_curr_symbol
    LC_ALL=en_GB.iso88591 locale int_prefix
    echo 'export LANG=en_GB.ISO-8859-1' > /etc/profile
    ```
7. 创建/etc/inputrc
    ```bash
    cat > /etc/inputrc << "EOF"
    # Begin /etc/inputrc
    # Modified by Chris Lynn <roryo@roryo.dynup.net>

    # Allow the command prompt to wrap to the next line
    set horizontal-scroll-mode Off

    # Enable 8-bit input
    set meta-flag On
    set input-meta On

    # Turns off 8th bit stripping
    set convert-meta Off

    # Keep the 8th bit for display
    set output-meta On

    # none, visible or audible
    set bell-style none

    # All of the following map the escape sequence of the value
    # contained in the 1st argument to the readline specific functions
    "\eOd": backward-word
    "\eOc": forward-word

    # for linux console
    "\e[1~": beginning-of-line
    "\e[4~": end-of-line
    "\e[5~": beginning-of-history
    "\e[6~": end-of-history
    "\e[3~": delete-char
    "\e[2~": quoted-insert

    # for xterm
    "\eOH": beginning-of-line
    "\eOF": end-of-line

    # for Konsole
    "\e[H": beginning-of-line
    "\e[F": end-of-line

    # End /etc/inputrc
    EOF
    ```
8. 创建/etc/shells
    ```bash
    cat > /etc/shells << "EOF"
    # Begin /etc/shells

    /bin/sh
    /bin/bash

    # End /etc/shells
    EOF
    ```
### 准备启动
1. 配置/etc/fstab
    ```bash
    cat > /etc/fstab << "EOF"
    # Begin /etc/fstab

    # file system  mount-point  type     options             dump  fsck
    #                                                              order

    /dev/sda1      /boot        ext4     defaults,noauto     0     2
    /dev/sda2      /            ext4     defaults            1     1
    proc           /proc        proc     nosuid,noexec,nodev 0     0
    sysfs          /sys         sysfs    nosuid,noexec,nodev 0     0
    devpts         /dev/pts     devpts   gid=5,mode=620      0     0
    tmpfs          /run         tmpfs    defaults            0     0
    devtmpfs       /dev         devtmpfs mode=0755,nosuid    0     0

    # End /etc/fstab
    EOF
    ```
2. 安装内核
    ```bash
    cd /sources && tar xf linux-5.19.2.tar.xz && cd linux-5.19.2
    make menuconfig
    # 按照10.3.1中Note配置config酌情增减
    make
    make modules_install

    cp arch/x86/boot/bzImage /boot/vmlinuz-5.19.2-lfs-11.2
    cp System.map /boot/System.map-5.19.2
    cp .config /boot/config-5.19.2
    install -d /usr/share/doc/linux-5.19.2
    cp -r Documentation/* /usr/share/doc/linux-5.19.2
    ```
3. 配置内核模块加载顺序
    ```bash
    install -m755 -d /etc/modprobe.d
    cat > /etc/modprobe.d/usb.conf << "EOF"
    # Begin /etc/modprobe.d/usb.conf

    install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
    install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

    # End /etc/modprobe.d/usb.conf
    EOF
    ```
4. 配置Grub
    ```bash
    grub-install /dev/sda
    cat > /boot/grub/grub.cfg << "EOF"
    # Begin /boot/grub/grub.cfg
    set default=0
    set timeout=5

    insmod ext2
    set root=(hd0,1)

    menuentry "GNU/Linux, Linux 5.19.2-lfs-11.2" {
        linux /vmlinuz-5.19.2-lfs-11.2 root=/dev/sda2 ro
    }
    EOF
    ```
5. 系统版本号
    ```bash
    echo 11.2 > /etc/lfs-release
    cat > /etc/lsb-release << "EOF"
    DISTRIB_ID="Linux From Scratch"
    DISTRIB_RELEASE="11.2"
    DISTRIB_CODENAME="wrzssz"
    DISTRIB_DESCRIPTION="Linux From Scratch"
    EOF
    cat > /etc/os-release << "EOF"
    NAME="Linux From Scratch"
    VERSION="11.2"
    ID=lfs
    PRETTY_NAME="Linux From Scratch 11.2"
    VERSION_CODENAME="wrzssz"
    EOF
    ```
### 重启