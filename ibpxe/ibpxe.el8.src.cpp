#include <iostream>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <unistd.h>
#include <sys/stat.h>
#include <fstream>
#include <set>
#include <cstring> // 添加头文件以使用 strcmp 函数

using namespace std;

// Define global variables
const string IMG = "abcdefg-image";
const string Master_IB = "bond0";
const string IB_mac = "abcdefg-ibmac";

const string conf_path = "etc/";
const string conf_file = "modules";
const string netdev_file = "netdev.conf";

int main(int argc, char* argv[]) {

    // 检查用户权限
    if (getuid() != 0) {
      std::cout << "Error: This program must be run as root!" << std::endl;
      return -1;
    }

    // 添加参数解析
    if (argc < 3 || strcmp(argv[1], "-c") != 0) {
        std::cerr << "Usage: ./program -c CONF_DIR" << std::endl;
        return -1;
    }
    const string CONF_DIR(argv[2]);

    const string guid_ip_txt_path = CONF_DIR + "/guid-ip.txt";

    struct stat file_stat;
    if (stat(guid_ip_txt_path.c_str(), &file_stat) != 0) {
        std::cerr << "Error: guid-ip.txt not found in specified directory." << std::endl;
        return -1;
    }

    const string pxeimage_path = "/tftpboot/nbi_img/" + IMG;

    struct stat pxeimage_stat;
    if (stat(pxeimage_path.c_str(), &pxeimage_stat) != 0) {
        std::cerr << "Error: initrd pxe image not found." << std::endl;
        return -1;
    }

    const string image_root_init    = "imag_root/init";
    const string image_root_awk    = "imag_root/awk";
    const string node_root_init     = "node_root/init";

    struct stat init_stat;
    if (stat(image_root_init.c_str(), &init_stat) != 0 || stat(image_root_awk.c_str(), &init_stat) != 0|| stat(node_root_init.c_str(), &init_stat) != 0) {
        std::cerr << "Error! Check the file existences: imag_root/init, imag_root/awk, node_root/init." << std::endl;
        return -1;
    }

    // 读取 ib0 网卡的 MAC 地址并判断
    FILE *pipe = popen("ip addr show ib0|grep -i link|awk '{print $2}'","r");
    if (!pipe) {
        std::cerr << "Error: failed to execute command." << std::endl;
        return -1;
    }

    char buffer[128];
    if (fgets(buffer, sizeof(buffer), pipe) == NULL) {
        std::cerr << "Error: failed to read output of command." << std::endl;
        pclose(pipe);
        return -1;
    }

    std::string mac_address(buffer);
    mac_address = mac_address.substr(0, mac_address.length()-1); // 去除末尾的换行符
    pclose(pipe);

    if (mac_address != IB_mac) {
        std::cerr << "Error: unauthorized access!" << std::endl;
        //system("sleep 60");
        //system("service dhcpd restart");
        return -1;
    }

    // 清空临时文件夹
    remove("tmp");
    // 指定临时文件夹的权限
    mkdir("tmp", S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
    // 切换到临时文件夹中
    chdir("tmp");

    string cmd = "zcat /tftpboot/nbi_img/" + IMG + " | cpio -idm &>/dev/null";
    system(cmd.c_str());

    // 创建 netdev.conf 文件并写入内容
    ofstream netdev_conf(conf_path + netdev_file);
    netdev_conf << "netdevices=\"ib0\"" << endl;
    netdev_conf.close();

    // 写入 modules 文件
    set<string> modules;
    modules.insert("ib_ipoib ipoib_enhanced=0");
    modules.insert("mlx4_ib");
    modules.insert("mlx5_ib");

    ofstream modules_file(conf_path + conf_file, ios::app);
    for (auto &it : modules) {
        modules_file << it << endl;
    }
    modules_file.close();

    // 将 modules 文件去重并写回
    ifstream old_modules_file(conf_path + conf_file);
    set<string> new_modules;
    string line;
    while (getline(old_modules_file, line)) {
        if (!line.empty() && line[0] != '#') {
            new_modules.insert(line);
        }
    }
    old_modules_file.close();

    ofstream temp_modules_file(conf_path + "modules.tmp");
    for (auto &it : new_modules) {
        temp_modules_file << it << endl;
    }
    temp_modules_file.close();

    remove((conf_path + conf_file).c_str());
    rename((conf_path + "modules.tmp").c_str(), (conf_path + conf_file).c_str());

    system("rm -rf lib/modules/* && cp -a /lib/modules/* lib/modules/");
    system("\\cp -f /usr/lib64/libgcc_s.so.1 lib64/");
    
    system("\\cp -f /usr/lib64/libbpf.so.0 lib64/");
    system("\\cp -f /usr/lib64/libelf.so.1 lib64/");
    system("\\cp -f /usr/lib64/libmnl.so.0 lib64/");
    system("\\cp -f /usr/lib64/libzstd.so.1 lib64/");
    system("\\cp -f /usr/lib64/libbz2.so.1 lib64/");
    system("\\cp -f /usr/lib64/liblzma.so.5 lib64/");
    system("\\cp -f /usr/lib64/libbz2.so.1 lib64/");
    system("\\cp -f /usr/sbin/ip sbin/");
    system("\\cp -f ../imag_root/awk sbin/");
    system("\\cp -f /usr/bin/seq sbin/");
    system("\\cp -f ../imag_root/init ./ && chmod +x init");
    cmd = "\\cp -f ../" + CONF_DIR + "/guid-ip.txt etc/";
    system(cmd.c_str());

    cmd = "find . | cpio --quiet -o -H newc | gzip -6 > /tftpboot/nbi_img/"+IMG;
    system(cmd.c_str());

    system("\\cp -f ../node_root/init /tftpboot/node_root/sbin && chmod +x /tftpboot/node_root/sbin/init");
    chdir("..");
    system("rm -rf tmp/");

    return 0;
}
