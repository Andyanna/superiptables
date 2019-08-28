#! /bin/bash




function install_1(){
echo -n "请问是否需要安装自动ddns组件？回复y/n:" ;read ifddns

red="\033[31m"
black="\033[0m"
muhost=
port1=
port2=
echo -n "请输入起始端口:" ;read port1
echo -n "请输入结束端口:" ;read port2
echo -n "目标服务器域名/ip（不带http://）:" ;read muhost


if [ "$(echo  $muhost |grep -E -o '([0-9]{1,3}[\.]){3}[0-9]{1,3}')" != "" ];then
    isip=true
    mubiao=$muhost
else
    echo "正在安装host命令....."
    yum install -y wget bind-utils &> /dev/null
    echo "安装完成"
    mubiao=$(host -t a  $muhost|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
fi
if [ "$mubiao" = "" ];then
    echo -e "无法解析域名/IP，请填写正确的域名/IP"
    exit 1
fi




# 开启端口转发
sed -n '/^net.ipv4.ip_forward=1/'p /etc/sysctl.conf | grep -q "net.ipv4.ip_forward=1"
if [ $? -ne 0 ]; then
    echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
fi

#开放FORWARD
arr1=(`iptables -L FORWARD -n  --line-number |grep "REJECT"|grep "0.0.0.0/0"|sort -r|awk '{print $1,$2,$5}'|tr " " ":"|tr "\n" " "`)  #16:REJECT:0.0.0.0/0 15:REJECT:0.0.0.0/0
for cell in ${arr1[@]}
do
    arr2=(`echo $cell|tr ":" " "`)  #arr2=16 REJECT 0.0.0.0/0
    index=${arr2[0]}
    echo 删除禁止FOWARD的规则——$index
    iptables -D FORWARD $index
done
iptables --policy FORWARD ACCEPT

## 获取本机地址
local=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | grep -Ev '(^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.1[6-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.2[0-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.3[0-1]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$)')
if [ "x${local}" = "x" ]; then
	local=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 )
fi
echo "目标ip: $mubiao"
echo "本地ip: $local"


##如果有旧的，冲突的规则则删除
arr1=(`iptables -L PREROUTING -n -t nat --line-number |grep DNAT|grep "dpts:$port1:port2 "|sort -r|awk '{print $1,$3,$9}'|tr " " ":"|tr "\n" " "`)
for cell in ${arr1[@]}  # cell= 1:tcp:to:8.8.8.8:543
do
        arr2=(`echo $cell|tr ":" " "`)  #arr2=(1 tcp to 8.8.8.8 543)
        index=${arr2[0]}
        proto=${arr2[1]}
        targetIP=${arr2[3]}
        targetPort=${arr2[4]}
        echo 清除本机$port1:port2端口到$targetIP:$targetPort的${proto}PREROUTING转发规则$index
        iptables -t nat  -D PREROUTING $index
        echo 清除对应的POSTROUTING规则
        toRmIndexs=(`iptables -L POSTROUTING -n -t nat --line-number|grep $targetIP|grep $targetPort|grep $proto|awk  '{print $1}'|sort -r|tr "\n" " "`)
        for cell1 in ${toRmIndexs[@]} 
        do
            iptables -t nat  -D POSTROUTING $cell1
        done
done
#设置新的中转规则


iptables -t nat  -A PREROUTING -p tcp -m tcp --dport $port1:$port2 -j DNAT --to-destination $mubiao
iptables -t nat  -A PREROUTING -p udp -m udp --dport $port1:$port2 -j DNAT --to-destination $mubiao
iptables -t nat  -A POSTROUTING -d $mubiao -p tcp -m tcp --dport $port1:$port2 -j SNAT --to-source $local
iptables -t nat  -A POSTROUTING -d $mubiao -p udp -m udp --dport $port1:$port2 -j SNAT --to-source $local


echo "端口转发成功"
echo "目标ip: $mubiao"
echo "本地ip: $local"



service iptables save
service iptables restart     

if [ "$ifddns" = "y" ];then
    echo -e "开始安装自动化ddns组件"


cd /root/
echo "正在获取组件"
yum install -y wget bind-utils &> /dev/null
cd /usr/local
rm -f /usr/local/ddns.sh
wget ${Download2}ddns.sh  &> /dev/null


chmod +x /usr/local/ddns.sh
echo "组件下载完成"
sed -i 's/'这是起始端口'/'${port1}'/g' "/usr/local/ddns.sh"
sed -i 's/'这是终止端口'/'${port2}'/g' "/usr/local/ddns.sh"
sed -i 's/'这是域名'/'${mubiao}'/g' "/usr/local/ddns.sh"


# 判断端口是否为数字
#echo "$port1"|[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ] && echo $remoteport |[ -n "`sed -n '/^[0-9][0-9]*$/p'`" ]&& valid=true

#if [ "$valid" = "" ];then
#   echo  -e "${red}起始端口和结束端口请输入数字！！${black}"
#   exit 1;
#fi

IPrecordfile=${port1}:${port2}[${mubiao}:${port1}:${port2}]
# 开机强制刷新一次
chmod +x /etc/rc.d/rc.local
echo "rm -f /root/$IPrecordfile" >> /etc/rc.d/rc.local
# 替换下面的port1 port2 mubiao
echo "/bin/bash /usr/local/ddns.sh $port1:$port2 $mubiao $IPrecordfile &>> /root/iptables${port1}:${port2}.log" >> /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
# 定时任务，每分钟检查一下
echo "* * * * * root /usr/local/ddns.sh $port1:$port2 $mubiao $IPrecordfile &>> /root/iptables${port1}:${port2}.log" >> /etc/crontab
cd
rm -f /root/$IPrecordfile
bash /usr/local/ddns.sh $port1:$port2 $mubiao $IPrecordfile &>> /root/iptables${port1}:${port2}.log
echo "成功"
echo "现在每分钟都会检查ddns的ip是否改变，并自动更新"
    
    
    else
    exit 1

fi
}

function install_2(){
     echo ""
}
function install_fix(){
     #删除安装环境
     echo "开始"
}

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
ulimit -c 0
#rm -rf s*
clear
cd /root
rm -rf superiptables.sh
yum install curl -y
	
	
[ $(id -u) != "0" ] && { echo "错误: 您必须以root用户运行此脚本"; exit 1; }

#echo "################################################"

ipAddress=$(ip addr | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -E -v "^192\\.168|^172\\.1[6-9]\\.|^172\\.2[0-9]\\.|^172\\.3[0-2]\\.|^10\\.|^127\\.|^255\\." | head -n 1) || '0.0.0.0'
#ipAddress=`curl -s http://members.3322.org/dyndns/getip`;
#ipAddress=`wget http://members.3322.org/dyndns/getip -O - -q ; echo`;
shadowsocksr="https://raw.githubusercontent.com/Andyanna/ssrrs/master/shadowsocksr.zip"
shadowsocksr2="https://raw.githubusercontent.com/Andyanna/ssrrs/master/shadowsocksr.zip"
libAddr="https://github.com/jedisct1/libsodium/releases/download/1.0.10/libsodium-1.0.10.tar.gz"

Download1="http://www.berryphone.club/"
Download2="https://raw.githubusercontent.com/Andyanna/superiptables/master/"
	
	
mysqlPWD=`date +%s%N | md5sum | head -c 20 ; echo`;
#echo "################################################"








sleep 1
clear
echo "superiptables版本:20190112 基于开源代码制作"
echo "1. >>>安装一键多端口中转 "
echo "2. >>>安装一键单端口中转 "
echo "        "
echo "          "
echo " bug反馈:telegram:@Andyanna"
echo '请输入需要安装的选项数字'
echo
read installway
if [[ $installway == "1" ]]
then
install_1
elif [[ $installway == "2" ]]
then
install_2
elif [[ $installway == "3" ]]
then
install_3
else 
echo '输入错误，请重新运行脚本'
exit 0;
fi

