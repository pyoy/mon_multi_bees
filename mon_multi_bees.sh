#!/bin/bash
###################################
# function   监控多个bee运行状态
# 依赖：mutt msmtp
#
#
# touch /root/sh/mon_multi_bees.sh; chmod 700 /root/sh/mon_multi_bees.sh
# crontab:
# 00,05,10,15,20,25,30,35,40,45,50,55 * * * * root /root/sh/mon_multi_bees.sh default >> /root/sh/logs/mon_multi_bees.log 2>&1

# Change History:
# date        author          note
# 2021/07/03 pyoy 创建

###################################

############# ENV #################
# 脚本名称，临时文件或邮件中可能用到，避免同类脚本的变量的冲突，下面直接取脚本名
export project_name=`echo ${0##*/} | cut -d'.' -f 1`

# 本机IP，如果获取不准，可改为手动填写。
export local_primary_ip=`ip addr show dev eth0 | grep "inet" | awk -F ' ' '{print $2}' | cut -d'/' -f 1 | head -n 1 2> /dev/null`

# 工作目录，可能会产生临时文件
export work_dir=/root/sh

# 临时文件目录
export tmp_dir=${work_dir}/tmp

# 日志目录
export log_dir=${work_dir}/logs

# 数据目录
export var_dir=${work_dir}/var


# 告警标题头
export alert_sub="bee状态批量检查"


# 钉钉告警 on or off。因为新ECS大多不允许连接邮件服25端口了（smtps仍然可以），如果不方便，所以改用钉钉告警
export alert_dingding_sw=off

# 钉钉机器，请到钉钉群创建，并把信息源服务器IP加入其白名单
export alert_dingding_robot="https://oapi.dingtalk.com/robot/send?access_token=xxxxxx"


# 邮件配置，默认发件人
export mailfromadd="sender@mail.com"

# 邮件配置，默认收件人
export mailtoadd="user@mail.com"

# 定时发送，hhss
export mailtotime=0855

# 发邮件方式，装了mutt是的可以填mailto_advanced，后者支持中文，被判断为垃圾邮件的概率也较小
# 值为no，就是关闭发邮件
export mailto=mailto_advanced
#export mailto=no

# 控制台输出 yes or on
export console_output_sw=yes

# 邮件输出方式 html_notable or html_table
export mail_output_method=html_table



############# 配置结束 ##################

# 时间和环境变量，一般无需修改
export datetime=$(date +%Y%m%d-%H%M)
export nowtime=$(date +%H%M)
export LANG=C
#export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export parameter1=$1
export parameter2=$2
export parameter3=$3
export HOME=/root

############# PROC #################
# 记录开始时间
start_time=$(date +%s)
if [ "$console_output_sw" == "yes" ];then
    echo ""
    echo "######"
    echo "`date +"%Y-%m-%d %H:%M:%S"` 运行开始"
fi

### 函数 ###
# 帮助信息
function help_msg() {
echo -e "\033[41merror!!! 小心点，不要慌，现在出错了，请仔细查看下面的帮助信息：\033[0m"
cat <<EOF

监控多个bee运行状态
HELP:
\$1: parameters eg: default


exec eg: 
sh $0 default


EOF
echo -e "\033[41merror!!! 小心点，不要慌，现在出错了，请仔细查看上面的帮助信息：\033[0m"
}

# 标准发件函数
function mailto_advanced() {
# mail
echo "$msg" | /opt/mutt/bin/mutt \
-e 'set content_type="text/html"' \
-s "[${project_name}] $sub" \
-e 'my_hdr from:'"$mailfromadd" \
-c "$mailccadd" \
"$mailtoadd" --
}


cd $work_dir
test -d $tmp_dir || mkdir -p $tmp_dir
test -d $log_dir || mkdir -p $log_dir
test -d $var_dir || mkdir -p $var_dir


if [ "$parameter1" == "" ] || [ "$parameter1" == "help" ]; then
    help_msg
    echo "`date +"%Y-%m-%d %H:%M:%S"` error, exit."
    exit 1
elif [ "$parameter1" == "default" ]; then
    true
fi


# 初始化
cat /dev/null > ${tmp_dir}/${project_name}_console_output.txt
cat /dev/null > ${tmp_dir}/${project_name}_reports.html
cat /dev/null > ${tmp_dir}/${project_name}_total_list.txt
cat /dev/null > ${tmp_dir}/${project_name}_fail_list.txt
fail_num=0


beeiplistdata_array=(
'ipx.x.x.x bee0001 华为云 上海'
'ipx.x.x.x bee0002 华为云 上海'
'ipx.x.x.x bee0003 华为云 贵阳'
'ipx.x.x.x bee0004 华为云 贵阳'
'ipx.x.x.x bee0005 华为云 北京'
'ipx.x.x.x bee0006 华为云 北京'
'ipx.x.x.x bee0007 华为云 广州'
'ipx.x.x.x bee0008 华为云 广州'
'ipx.x.x.x bee0009 华为云 香港'
'ipx.x.x.x bee0010 华为云 香港'
)
# 注意：上面是模拟二维数组，确保每行有两个“元素”，并用单引号包住。
for beeipdata in "${beeiplistdata_array[@]}"
do
    beeip=`echo $beeipdata | awk '{ print $1; }'`
    bee_name=`echo $beeipdata | awk '{ print $2; }'`
    service_provider=`echo $beeipdata | awk '{ print $3; }'`
    region=`echo $beeipdata | awk '{ print $4; }'`


    peer_num=`curl -s --connect-timeout 7 http://${beeip}:1635/peers | jq '.peers | length'`

    if [ "$peer_num" == "" ]; then
        peer_num="-1"
        fail_num=$((${fail_num}+1))
    elif grep '^[[:digit:]]*$' <<< "$peer_num" > /dev/null; then
        true
    else
        peer_num="-1"
        fail_num=$((${fail_num}+1))
    fi

    echo "${bee_name} ${service_provider} ${region} ${beeip} ${peer_num}" >> ${tmp_dir}/${project_name}_total_list.txt

done



# 钉钉通知报告
if [ "${alert_dingding_sw}" == "on" ];then
    curl ''"${alert_dingding_robot}"'' \
       -H 'Content-Type: application/json' \
       -d '{"msgtype": "text", 
            "text": {
                "content": "'"${sub}"'"
            }
          }'
    if [ "$console_output_sw" == "yes" ];then
        echo "已发出钉钉告警"
    fi
elif [ "${alert_dingding_sw}" != "on" ];then
    if [ "$console_output_sw" == "yes" ];then
        echo "没有开启钉钉告警"
    fi
fi


if [ "$console_output_sw" == "yes" ];then
    echo "日志和邮件通知"
fi
if [ "$mailto" == "mailto_advanced" ];then
    total_num=`cat ${tmp_dir}/${project_name}_total_list.txt | wc -l`
    # fail_num=`cat ${tmp_dir}/${project_name}_fail_list.txt | wc -l`
    echo -e "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
        <title>${projectname}_report</title></head><body>" > ${tmp_dir}/${project_name}_reports.html
    sub="bee运行状态结果汇总，共有节点${total_num}个，其中故障节点${fail_num}个"

    
    
    ### 控制台输出 ###
    echo "检查时间：`date +"%Y-%m-%d %H:%M:%S"`" >> ${tmp_dir}/${project_name}_console_output.txt
    echo "信息来源：${local_primary_ip}" >> ${tmp_dir}/${project_name}_console_output.txt
    echo "" >> ${tmp_dir}/${project_name}_console_output.txt
    echo "" >> ${tmp_dir}/${project_name}_console_output.txt
    echo "### bee运行状态列表 ###" >> ${tmp_dir}/${project_name}_console_output.txt
    echo "节点名称 服务端 地域 节点IP 对等数量(-1代表故障)" >> ${tmp_dir}/${project_name}_console_output.txt
    cat "${tmp_dir}/${project_name}_total_list.txt" >> ${tmp_dir}/${project_name}_console_output.txt
    
    if [ "$console_output_sw" == "yes" ];then
        echo "$sub"
        cat ${tmp_dir}/${project_name}_console_output.txt
    fi
    
    
    
    ### 无表格html输出 ###
    if [ "$mail_output_method" == "html_notable" ];then
        echo -e "<pre>" >> ${tmp_dir}/${project_name}_reports.html
        cat ${tmp_dir}/${project_name}_console_output.txt >> ${tmp_dir}/${project_name}_reports.html
        echo -e "</pre>" >> ${tmp_dir}/${project_name}_reports.html
    fi
    
    
    #### 有表格html输出 ###
    html_tabletd_green(){
        # 浅绿色
        echo "<tr bgcolor="#D8F6CE">
        <td>$1</td>
        <td>$2</td>
        <td>$3</td>
        <td>$4</td>
        <td>$5</td>
        </tr>" >> ${tmp_dir}/${project_name}_reports.html
    }

    html_tabletd_red(){
        # 红色
        echo "<tr bgcolor="#FF0000">
        <td>$1</td>
        <td>$2</td>
        <td>$3</td>
        <td>$4</td>
        <td>$5</td>
        </tr>" >> ${tmp_dir}/${project_name}_reports.html
    }

    html_table_create(){
        i=1
        echo "
        <table border=1 border=1 cellspacing='0' cellpadding='0' >
        <tr bgcolor="#BDBDBD">
        <th>节点名称</th>
        <th>服务商</th>
        <th>地域</th>
        <th>ip地址</th>
        <th>对等数量(-1代表故障)</th>
        </tr>" > ${tmp_dir}/${project_name}_reports.html
        table_column1_array=$(awk -F " " '{print $1}' ${tmp_dir}/${project_name}_total_list.txt) # 表第一列数据组成阵列
        for table_column1 in $table_column1_array
        do
            j=2
            table_column2=$(awk -F " " 'NR==i { print $j}' i=$i j=$j ${tmp_dir}/${project_name}_total_list.txt) # 取该行第2列值
            let "j++"
            table_column3=$(awk -F " " 'NR==i { print $j}' i=$i j=$j ${tmp_dir}/${project_name}_total_list.txt) # 取该行第3列值
            let "j++"
            table_column4=$(awk -F " " 'NR==i { print $j}' i=$i j=$j ${tmp_dir}/${project_name}_total_list.txt) # 取该行第4列值
            let "j++"
            table_column5=$(awk -F " " 'NR==i { print $j}' i=$i j=$j ${tmp_dir}/${project_name}_total_list.txt) # 取该行第5列值
            
            # 判断该行第5列值是否为正，如果不是，显示浅绿色，反之红色
            if [ "$table_column5" -gt 0 ];then
                html_tabletd_green $table_column1 $table_column2 $table_column3 $table_column4 $table_column5   # 构造每行表格信息
            else
                html_tabletd_red $table_column1 $table_column2 $table_column3 $table_column4 $table_column5  # 构造每行表格信息
            fi

            let "i++"
            # 调试：
            # echo $table_column1 $table_column2 $table_column3 $i $j
        done
    echo "</table>" >> ${tmp_dir}/${project_name}_reports.html
    }
    if [ "$mail_output_method" == "html_table" ];then
        html_table_create
    fi
    
    
    echo -e "</body></html>" >> ${tmp_dir}/${project_name}_reports.html
    msg="$(cat ${tmp_dir}/${project_name}_reports.html)"
    
    if [ "$nowtime" == "$mailtotime" ] || [ "$fail_num" -ge 1 ];then
        mailto_advanced
        if [ "$console_output_sw" == "yes" ];then
            echo "已发出邮件通知。"
        fi
    fi
    
elif [ "$mailto" == "no" ];then
    if [ "$console_output_sw" == "yes" ];then
        echo "没有开启邮件告警"
    fi
fi


if [ "$console_output_sw" == "yes" ];then
    echo ""
    stop_time=$(date +%s)
    echo "`date +"%Y-%m-%d %H:%M:%S"` 运行结束"
    echo "本次脚本运行了$((${stop_time}-${start_time}))秒。"
fi


