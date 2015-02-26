#!/bin/bash

. ../conf/common.sh
get_conf

function translate_id {
    host=$1
    item_id=$2
    letter_osd=`echo $item_id|awk -F ':' '{print $1}'|awk -F '/' '{print $3}'`
    letter_jou=`echo $item_id|awk -F ':' '{print $2}'|awk -F '/' '{print $3}'`
    id_osd=`ssh $host "ls -l /dev/disk/by-id" 2>/dev/null |grep ata | grep -w $letter_osd | awk '{print $9}'`
    id_jou=`ssh $host "ls -l /dev/disk/by-id" 2>/dev/null |grep ata | grep -w $letter_jou | awk '{print $9}'`
    if [ -z "$id_osd" ]||[ -z "$id_jou" ]; then
        item_id=$2
    else
        item_id="/dev/disk/by-id/"$id_osd":/dev/disk/by-id/"$id_jou
    fi
}

function do_deploy_osd {
    osd_host_list=$1
    index=0
    for host in $osd_host_list
    do
        echo "============start create osds on host $host============"
        disk=$(eval echo \$$host)
        osd_list=`echo $disk | sed 's/,/ /g'`
        for item in $osd_list
        do
            if [ `os_disk_check $host $item` = "false" ]; then
                echo "Devices contains os disk!"
                exit
            fi

            translate_id $host $item

#            if [ -z "$item_id" ]; then
#                echo "WARNING: cannot find disk $item on $host, skip that osd"
#                continue
#            fi
            
            ssh $host mkdir -p /var/lib/ceph/osd/ceph-$index
            echo "ceph-deploy --overwrite-conf osd prepare $host:$item"
            ceph-deploy --overwrite-conf osd prepare $host:$item_id
            error_check           
 
            echo "ceph-deploy osd activate $host:$item"
            ceph-deploy --overwrite-conf osd activate $host:$item_id
            error_check           
 
            index=$(($index + 1))
        done
    done

    echo "============finish create osd============"

}

osd_host_list=`echo $deploy_osd_servers | sed 's/,/ /g'`

echo 
echo "Please check the ceph.conf"
copy_to_conf "../conf/all.conf"
echo "***** ceph.conf *****"
cat ceph.conf
echo -e "*********************\n"

echo "Do you wanna check partitions on all disks( yes / no )"
if [ "`interact`" = "true" ]; then
    cd prepare-scripts
    bash list_disk_partition.sh -l
    cd ..
    echo "Do you wanna continue?( yes or no )"
    if [ "`interact`" != "true" ]; then
        exit
    fi
fi
do_deploy_osd "$osd_host_list"

ceph_nodes=`echo "$deploy_mon_servers,$deploy_osd_servers,$deploy_mds_servers,$deploy_rbd_nodes" | sed 's/,/\n/g' | sort -u | tr -s '\n' ' '`
for ceph_s in $ceph_nodes
do
    scp /etc/ceph/* $ceph_s://etc/ceph/
    ceph-deploy --overwrite-conf config push $ceph_s
    error_check
    #add mounted osd to fstab
    uuid_to_fstab $ceph_s
done
