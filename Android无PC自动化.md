# Android无PC自动化
[参考](https://blog.csdn.net/CDaron/article/details/125698972)
### 配置Termux
1. 在[F-Droid](https://f-droid.org/)下载[Termux](https://f-droid.org/zh_Hans/packages/com.termux/)和[Termux:Boot](https://f-droid.org/zh_Hans/packages/com.termux.boot/)并安装
2. 手机上配置`Termux:Boot`和`Termux`开机启动，并允许后台运行
3. 修改源并开启ssh服务
    ```bash
    echo 'deb https://mirrors.ustc.edu.cn/termux/apt/termux-main stable main' > /data/data/com.termux/files/usr/etc/apt/sources.list
    pkg update -y && pkg upgrade -y
    pkg install vim openssh termux-api termux-tools -y
    termux-setup-storage
    ```
4. ssh服务开机启动
    ```bash
    mkdir -p ~/.termux/boot/
    echo '#!/data/data/com.termux/files/usr/bin/bash
    termux-wake-lock
    sshd' > ~/.termux/boot/start-sshd
    chmod +x ~/.termux/boot/start-sshd
    ~/.termux/boot/start-sshd
    passwd
    ```
### 安装python和uiautomator2
```bash
pkg install -y python3 clang libxml2 libxslt libjpeg-turbo zlib android-tools
# 配置pip源
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install lxml cython uiautomator2 weditor
```
### 开启adb调试
1. 手机上打开`开发者选项`-->`USB调试`
2. 如果手机已经root
    ```bash
    adbd stop
    setprop service.adb.tcp.port 5555
    adbd start
    ```
    如果没有root，手机连接PC，在PC上执行
    ```bash
    adb.exe tcpip 5555
    ```
    或在开发者选项中打开无线调试
 3. 手机上
    ```bash
    adb connect 127.0.0.1
    ```
### 使用
1. 连上adb后初始化
    ```bash
    uiautomator2 init
    ```
2. 测试一下
    ```python
    import uiautomator2
    u = uiautomator2.connect('0.0.0.0')
    u.app_start('com.android.filemanager')
    ```
    如果打开了文件管理器，说明成功。