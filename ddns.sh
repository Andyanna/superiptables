#! /bin/bash
# 



port1=这是起始端口
port2=这是终止端口
mubiao=这是域名
tempFile=$4
if [ "$4" = "" ];then
    tempFile=iplog
fi



red="\033[31m"
black="\033[0m"

echo ""
echo superiptables日志
echo 时间：$(date)

# 开启端口转发
sed -n '/^net.ipv4.ip_forward=1/'p /etc/sysctl.conf | grep -q "net.ipv4.ip_forward=1"
if [ $? -ne 0 ]; then
    echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
fi


    newmubiao=$(host -t a  $mubiao|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    if [ "$newmubiao" = "" ];then
        echo -e "无法解析域名，请填写正确的域名！"
        exit 1
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

lastip=$(cat /root/$tempFile 2> /dev/null)
if [ "$lastip" = "$newmubiao" ]; then
    echo 目标域名解析IP未发生变化，等待下一次检索
   
   # exit 1
fi

#判断
echo ""
echo "双重验证"
arr3=(`iptables -L PREROUTING -n -t nat --line-number |grep DNAT|grep "dpts:$port1"|sort -r|awk '{print $1,$3,$9}'|tr " " ":"|tr "\n" " "`)
for cell2 in ${arr3[@]}  # cell= 1:tcp:to:8.8.8.8:543
do
        arr4=(`echo $cell2|tr ":" " "`)  #arr2=(1 tcp to 8.8.8.8 543)

        targetIP1=${arr4[3]}
        done
if [ "$lastip" = "$targetIP1" ]; then
    echo 目标域名解析IP未发生变化，等待下一次检索
    exit 1
fi




echo 上一次查询ip: $lastip
echo 最新ip: $newmubiao
echo $newmubiao > /root/$tempFile


## 获取本机地址
local=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | grep -Ev '(^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.1[6-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.2[0-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.3[0-1]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$)')
if [ "${local}" = "" ]; then
	local=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 )
fi
echo ""
echo 本地ip: $local
echo 有更新，正在重新设置iptables转发规则

#删除旧的中转规则
arr1=(`iptables -L PREROUTING -n -t nat --line-number |grep DNAT|grep "dpts:$port1"|sort -r|awk '{print $1,$3,$9}'|tr " " ":"|tr "\n" " "`)
for cell in ${arr1[@]}  # cell= 1:tcp:to:8.8.8.8:543
do
        arr2=(`echo $cell|tr ":" " "`)  #arr2=(1 tcp to 8.8.8.8 543)
        index=${arr2[0]}
        proto=${arr2[1]}
        targetIP=${arr2[3]}
        targetPort=${arr2[4]}
        echo 清除本机$port1:$port2端口到$targetIP的${proto} prerOUTING转发规则 $index
        iptables -t nat  -D PREROUTING $index
        
done        
ar1=(`iptables -L POSTROUTING -n -t nat --line-number |grep SNAT|grep "dpts:$port1"|sort -r|awk '{print $1,$3,$9}'|tr " " ":"|tr "\n" " "`)
for cell1 in ${ar1[@]}  # cell= 1:tcp:to:8.8.8.8:543
do
        ar2=(`echo $cell1|tr ":" " "`)  #arr2=(1 tcp to 8.8.8.8 543)
       out=${ar2[0]}

        
        
       # toRmIndexs=(`iptables -L POSTROUTING -n -t nat --line-number|grep $targetIP|grep $port1:$port2|grep $proto|awk  '{print $1}'|sort -r|tr "\n" " "`)
      #  for cell2 in ${toRmIndexs[@]} 
     #   do
      iptables -t nat  -D POSTROUTING $out
       echo 清除本机$port1:$port2端口到$targetIP的${proto} postOUTING转发规则 $out
done


## 建立新的中转规则
#iptables -t nat -A PREROUTING -p tcp --dport $localport -j DNAT --to-destination $remote:$remoteport
#iptables -t nat -A PREROUTING -p udp --dport $localport -j DNAT --to-destination $remote:$remoteport
#iptables -t nat -A POSTROUTING -p tcp -d $remote --dport $remoteport -j SNAT --to-source $local
#iptables -t nat -A POSTROUTING -p udp -d $remote --dport $remoteport -j SNAT --to-source $local


iptables -t nat  -A PREROUTING -p tcp -m tcp --dport $port1:$port2 -j DNAT --to-destination $newmubiao
iptables -t nat  -A PREROUTING -p udp -m udp --dport $port1:$port2 -j DNAT --to-destination $newmubiao
iptables -t nat  -A POSTROUTING -d $newmubiao -p tcp -m tcp --dport $port1:$port2 -j SNAT --to-source $local
iptables -t nat  -A POSTROUTING -d $newmubiao -p udp -m udp --dport $port1:$port2 -j SNAT --to-source $local


service iptables save 2> /dev/null
service iptables restart  2> /dev/null
