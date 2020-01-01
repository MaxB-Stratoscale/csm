#!/usr/bin/bash 


##############################################################
### Parameters


vmId=$1


targetPool=af80f0dd-1a1f-47c8-9df6-569b1929c497          #the ID of the target disk pool
attachhostlocal=stratonode0.node.strato     # Symphony node that will be used for attach-to-host and dd in the lolcal cluster
attachhostremote=stratonode0.node.strato  # Symphony node that will be used for attach-to-host and dd in the remote cluster
remotenode=9.9.9.9    #IP address of the node in the new-target cluster that will be used for copy
remNb=https://9.9.9.10    # the NB IP of the new-target cluster
lpass=admin   #password of the admin cloud_admin user on the local cluster
rpass=admin   #password of the admin cloud_admin user on the remote cluster
rootp="passwd"   # root password in the remote cluster


customproject=no # can be yes or no, if yes is specified, you need to provide the project id for myprojectId, if no is used, the script will use the same project ID for the target as it is on source
myprojectId=""   #if no custom project id provided, use ""
isremote=remote  #cluster, can be remote or local,  local will copy volumes to a pool on local cluster

### End of PARAMETERS
#################################################################

display_help() {
    echo
    echo "Usage: $0 VM_ID" >&2
    echo
    echo " The only parameter that this script acceps is a VM ID"
    echo " This is the VM that needs to be migrated"
    echo " Everything else shoould be statically set in the Parameters section of this script  "
    echo " The script will clone all volumes of the VM to the target pool and create a VM "
    echo " The target pool can be on the same cluster or on remote cluster "
    exit 1
}

#check if the vm exists
symp -q -u admin -p $lpass -d cloud_admin -k -r default vm get $vmId > /dev/null 2>&1
      if [ $? != 0 ]; then
         printf "%s \n"  " Can not find VM with ID  $vmId "
         display_help
         exit 1
      fi

      if [ "$1" == "-h" ]; then
         display_help
         exit 0
      fi

#check if the target disk pool exists
     if [ $isremote == remote ]; then
        symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default storage pool get $targetPool > /dev/null 2>&1
         if [ $? != 0 ]; then
             printf "%s \n"  "  "
             printf "%s \n"  " Can not find the pool $targetPool on remote cluster $remNb "
             printf "%s \n"  " Make sure the details in the Parameters section correct "
            display_help
            exit 1
         fi

     fi

echo " Start collecting information on the VM "
instance_type=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default vm get $vmId 2>&1 |grep -v Connect|awk -F "|" '$2 ~ "instanceType" {print $3}' |tr -d ' ')
printf "%s \n"  "   instance_type= $instance_type"

vmName=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default vm get $vmId 2>&1 |grep -v Connect|awk -F "|" '$2 ~ " name " {print $3}' |tr -d ' ')

printf "%s \n" "   vm_name= $vmName"

newvmName=migrated_$vmName
printf "%s \n" "   new VM name is $newvmName"
#need to check if a VM with the corresponding name already exists



 


bootvolId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default vm get $vmId 2>&1 |grep -v Connect |awk -F "|" ' $2 ~ "bootVolume" {print $3}' |tr -d ' ')
printf "%s \n"  "   bootvolid= $bootvolId"

bootvolName=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $bootvolId 2>&1 |grep -v Connect |awk -F '|' '$2 ~ "name" {print $3}' | tr -d ' ')
isprotected=$(mancala volumes get $bootvolId |awk -F "|" '$2 ~ "isTracked" {print $3}' |tr -d ' ')


    if [ $isprotected = "True" ]; then
         printf "%s \n" "    volume  $bootvolName  is protected and trtacked, please make sure the VM is not protected and then run the following command before running this script again"
         printf "%s \n" "    mancala volumes untrack  $bootvolId "
         echo "    you can check if thevolume is tracked by running:   mancala volumes get $bootvolId |awk -F \"|\" '\$2 ~ \"isTracked\" {print \$3}'|tr -d ' ' "
         exit 1
    fi


echo "   bootvolname=" $bootvolName


    if [ $customproject = "no" ]; then

        projectId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $bootvolId  2>&1 |grep -v Connect |awk -F "|" '$2 ~ "projectID" {print $3}')
    else
        projectId=$myprojectId
    fi
echo "   projectid=" $projectId

#if the project is "default", then we will use admin project on the target cluster as well
projectName=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default project get $projectId -c name  2>&1 |grep -v Connect |awk -F "|" '/name/ {print $3}' |tr -d " " )
 

    if [ $isremote = "remote" ]; then

	    targadminprojectId=$(symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default project list  2>&1 |grep -v Connect |awk -F "|" '/cloud_admin/ {print $2}' |tr -d " ")
   
   	    if [ "$projectName" = "default" ]; then
 		    projectId=$targadminprojectId
   	    fi
    else
	    targadminprojectId=$projectId
    fi
 
    

    if [ $isremote = "remote" ]; then

	   symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default project get $projectId > /dev/null 2>&1
	    
	     if [ $? != 0 ]; then
                      printf "%s \n "   "project id $projectId does not exist on the target cluster, exiting"
		      exit 1
    	     fi					 

    fi 	  
 
bootvolSize=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $bootvolId  2>&1 |grep -v Connect |awk -F "|" '$2 ~ "size" {print $3}'| tr -d ' ' |awk -F "." '{print $1}' )
printf "%s \n" "   bootvolsize= $bootvolSize"


######################
#start creating new volumes
#####################
#create a clone of the boot volume, this clone will be used as a source for copying to a new volume
printf "%s \n" "   creating a new boot volume on the target pool"
clonebootvolId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume create --source-id $bootvolId clone_$bootvolName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ' )


    if [ $? = 0 ]; then
        printf "%s \n "   " volume clone_$bootvolName  was created"
    else
        printf "%s \n"    " clone of the $bootvolName  volume could not be created"
        exit 1
    fi

echo "   clonebootvolid=" $clonebootvolId

soursemountPoint=$(mancala volumes attach-to-host $clonebootvolId $attachhostlocal  |awk -F "'" '/attachments/ {print $20}')

    if [ $? != 0 ]; then
        echo "    attach-to-host command did not work for the CLONED BOOT VOL, something is wrong"
        exit 1
    fi

echo "   soursemountPoint=" $soursemountPoint
  

#create new volume on the target pool
echo " Going to clone the boot volume  "
    if [ $isremote = "remote" ]; then

	    newbootvolId=$(symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default volume create --size $bootvolSize  --storage-pool $targetPool --project-id $projectId new_$bootvolName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ')
        volcreatestatus=$?
    else

	    newbootvolId=$(symp -q  -u admin -p $lpass -d cloud_admin -k -r default volume create --size $bootvolSize  --storage-pool $targetPool --project-id $projectId new_$bootvolName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ')
        volcreatestatus=$?
    fi

    if [ $volcreatestatus = 0 ]; then
        printf "%s \n" "    volume new_$bootvolName  was created"
    else
        printf "%s \n" "    the new  $bootvolName  volume could not be created"
        exit 1
    fi

printf "%s \n" "   newbootvolId= $newbootvolId"

    if [ $isremote = "remote" ]; then

        targetmountPoint=$(sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root $remotenode mancala volumes attach-to-host $newbootvolId $attachhostremote|awk -F "'" '/attachments/ {print $22}')
        createtargmp=$?
#targetmountPoint=$(ssh -l root $remotenode mancala volumes attach-to-host $newbootvolId stratonode0.node.strato |awk -F "'" '/attachments/ {print $22}')
    else
        targetmountPoint=$(mancala volumes attach-to-host $newbootvolId $attachhostlocal  |awk -F "'" '/attachments/ {print $20}')
        createtargmp=$?
    fi


    if [ $createtargmp != 0 ]; then
        printf "%s \n" "    attach-to-host command did not work for the TARGET  VOL, something is wrong"
        exit 1
    fi

printf "%s \n" "   soursemountPoint= $soursemountPoint"
printf "%s \n" "   targetmountPoint= $targetmountPoint"


#need to find out if the instance type of the source VM can be used for the new VM, if not a default type will be used and a message will be printed, asking to adapt the VM instance type after creation
    if [ $isremote = "remote" ]; then
        symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default instance type get $instance_type > /dev/null  2>&1

# if the instance type is not in the list of known types we will use the t2.small as the default instance type 
        if [ $? != 0 ] ; then
            printf "%s \n" "******************* THE ORIGINAL INSTANCE TYPE WAS  $instance_type  AND IT IS NOT LONGER SUPPORTED"
            printf "%s \n"  "******************* The defaul type t2.small will be used for the VM, please change it manually if needed"
            original_instance_type=$instance_type
            instance_type=t2.small
        fi
    fi

# if the instance type is not standard we will use the t2.small as the default instance type
    if [[ $instance_type = *__* ]] ; then
        echo "******************* THE ORIGINAL INSTANCE TYPE WAS " $instance_type " AND IT IS NOT LONGER SUPPORTED"
        echo "******************* The defaul type t2.small will be used for the VM, please change it manually if needed"
        original_instance_type=$instance_type
        instance_type=t2.small
    fi
   printf "%s \n" " Starring the dd copy"
#######dd status=progress  if=$soursemountPoint bs=4M |ssh $remotenode  dd of=$targetmountPoint bs=4M
      if [ $isremote = "remote" ]; then
	    dd status=progress  if=$soursemountPoint bs=4M |sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root   $remotenode  dd of=$targetmountPoint bs=4M
           echo 1
      else
           dd status=progress  if=$soursemountPoint bs=4M of=$targetmountPoint bs=4M 
      fi
printf "%s \n"  "    Volume copy has finished  "
printf "%s \n"  "    Running sync "
sync
sync
sync
 
#when the copy is done we detach the volumes from the host
printf "%s \n" "    detaching the volumes from the host"

#mancala volumes detach-from-host $newbootvolId stratonode0.node.strato attachhostremote
    if [ $isremote = "remote" ]; then
        sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root $remotenode mancala volumes detach-from-host $newbootvolId $attachhostremote > /dev/null
    else
        mancala volumes detach-from-host $newbootvolId $attachhostlocal  > /dev/null
    fi

mancala volumes detach-from-host $clonebootvolId $attachhostlocal > /dev/null

echo "  deleting the clone volume that was used for copying the data to the new volume"
symp -q -u admin -p $lpass -d cloud_admin -k -r default volume remove $clonebootvolId 2>&1 |grep -v Connecting

#creating the new VM
    if [ $isremote = "remote" ]; then
        newvmId=$(sshpass -p $rootp ssh -o StrictHostKeyChecking=no  -l root $remotenode symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default vm create  --volumes-to-attach $newbootvolId  --instance-type $instance_type  --project-id $projectId  $newvmName |grep -v Connecting |awk -F "|" '$2 ~ " id " {print $3}'|tr -d " ")
	sshpass -p $rootp ssh -o StrictHostKeyChecking=no  -l root $remotenode symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default vm get $newvmId  >/dev/null 2>&1
        vmcreatestatus=$?
#printf "%s \n" "new VM ID is $newvmId" 
    else
        newvmId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default vm create  --volumes-to-attach $newbootvolId  --instance-type $instance_type  --project-id $projectId  $newvmName |grep -v Connecting |awk -F "|" '$2 ~ " id " {print $3}'|tr -d " ")
        symp -q -u admin -p $lpass -d cloud_admin -k -r default vm get $newvmId >/dev/null 2>&1
        vmcreatestatus=$?

    fi


    if [ $vmcreatestatus = 0 ] ; then
        printf "%s \n" " the vm  $newvmName  was created, please attach it to the network before powering on"
            if [ "$original_instance_type" = "$instance_type" ] ; then
                printf "%s \n" "  Please note, the original instance type  $original_instance_type  can not be used in this version and defaulr t1.small instance type was used instead"
                printf "%s \n" "  Please manually adopt the instance type of the new VM "
            fi
    else
        printf "%s \n" "   something went wrong and the vm was not created"
        printf "%s \n" "   this is the commant we used: "
        printf "%s \n" "   symp -q -u admin -p $lpass -d cloud_admin -k -r default vm create  --volumes-to-attach $newbootvolId  --instance-type $instance_type  --project-id $projectId  $newvmName"
        printf "%s \n" "   symp -q --url $remNb -u admin -p $rpass -d cloud_admin -k -r default vm create  --volumes-to-attach $newbootvolId  --instance-type $instance_type  --project-id $projectId  $newvmName"
    fi

#echo "    please manually delete the volume that was used for the copy by running"
#echo "    symp -q -u admin -p $lpass -d cloud_admin -k -r default volume remove " $clonebootvolId

#lets check if the VM owns any data volumes
vols=$(symp -u admin -p $lpass -d cloud_admin -k -r default vm get $vmId -c volumes 2>&1 |grep -v Connecting |awk -F "|" '/volumes/ {print $3}')

#####################################################################################

function copydatavols  {

volId=$1

volName=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $volId |awk -F '|' '$2 ~ "name" {print $3}' | tr -d ' ')
printf "%s \n" "    volname= $volName"
printf "%s \n" "    volume ID= $volId"

isprotected=$(mancala volumes get $volId |awk -F "|" '$2 ~ "isTracked" {print $3}' |tr -d ' ')

    if [ $isprotected = "True" ]; then
        printf "%s \n" "    volume  $volName is protected and trtacked, please make sure the VM is not protected and then run the following command before running this script again"
        printf "%s \n" "    mancala volumes untrack  $volId"
        printf "%s \n" "    you can check if the volume is tracked by running:   mancala volumes get $volId |grep  isTracked "

        exit 1
    fi


	if [ $customproject = "no" ]; then

		projectId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $volId |awk -F "|" '$2 ~ "projectID" {print $3}')
		projectName=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default project get $projectId -c name |awk -F "|" '/name/ {print $3}' |tr -d " " )
		printf "%s \n" "   projectid= $projectId"

   			if [ "$projectName" = "default" ]; then
        			projectId=$targadminprojectId
   			fi
		printf "%s \n" "projectid is  $projectId"
	else
		projectId=$myprojectId
	fi
volSize=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume get $volId |awk -F "|" '$2 ~ "size" {print $3}'| tr -d ' ' |awk -F "." '{print $1}' )

printf "%s \n" "   volsize= $volSize"


######################
##start creating new volumes
#####################
##create a clone of the volume, this clone will be used as a source for copying to a new volume
clonevolId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume create --source-id $volId clone_$volName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ' )


    if [ $? = 0 ]; then
        printf "%s \n" "   volume clone_$volName  was created"
    else
        printf "%s \n" "   clone of the $volName volume could not be created"
        exit 1
    fi

printf "%s \n" "    clonevolid= $clonevolId"

soursemountPoint=$(mancala volumes attach-to-host $clonevolId $attachhostlocal  |awk -F "'" '/attachments/ {print $20}')

    if [ $? != 0 ]; then
        printf "%s \n" "    attach-to-host command did not work for the CLONED VOL  $clonevolId   , something is wrong"
        exit 1
    fi

printf "%s \n" "    soursemountPoint= $soursemountPoint"


##create new volume on the target pool

printf "%s \n " "creating new volume on remote node "
echo "running create vol on remote node"
	if [ $isremote = "remote" ]; then
		newvolId=$(symp -q --url $remNb  -u admin -p $rpass -d cloud_admin -k -r default volume create --size $volSize  --storage-pool $targetPool --project-id $projectId new_$volName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ')
	    newvolcrstatus=$?
	else
		newvolId=$(symp -q -u admin -p $lpass -d cloud_admin -k -r default volume create --size $volSize  --storage-pool $targetPool --project-id $projectId new_$volName |awk -F "|" '$2 ~ " id " {print $3}'| tr -d ' ')
	    newvolcrstatus=$?
	fi

    if [ $newvolcrstatus = 0 ]; then
        printf "%s \n" "    volume new_$volName  was created"
    else
        printf "%s \n" "    the new $volName volume could not be created"
        exit 1
    fi

printf "%s \n" "   newvolId= $newvolId"

	if [ $isremote = "remote" ]; then
		targetmountPoint=$(sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root $remotenode mancala volumes attach-to-host $newvolId $attachhostremote  |awk -F "'" '/attachments/ {print $22}')
	    crmntpointstatus=$?
	else
		targetmountPoint=$(mancala volumes attach-to-host $newvolId $attachtohostlocal  |awk -F "'" '/attachments/ {print $20}')
	    crmntpointstatus=$?
	fi

    if [ $crmntpointstatus != 0 ]; then
        printf "%s \n"  "     attach-to-host command did not work for the TARGET  VOL  $newvolId, something is wrong"
        exit 1
    fi

printf "%s \n" "   soursemountPoint= $soursemountPoint"
printf "%s \n" "   targetmountPoint= $targetmountPoint"
printf "%s \n" "   now starting the dd copy"
	if [ $isremote = "remote" ]; then
		dd status=progress  if=$soursemountPoint bs=4M |sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root   $remotenode  dd of=$targetmountPoint bs=4M
	else
		dd status=progress  if=$soursemountPoint of=$targetmountPoint bs=4M
	fi
sync
sync
sync
printf "%s \n"  "    Volume copy has finished "

##when the copy is done we detach the volumes from the host
printf "%s \n" "    detaching the volumes from the host"

printf "%s \n"  "detaching the newvolume $newvolId "

    if [ $isremote = "remote" ]; then
		sshpass -p $rootp ssh -o StrictHostKeyChecking=no -l root $remotenode mancala volumes detach-from-host $newvolId $attachhostremote  > /dev/null 2>&1
	else
		mancala volumes detach-from-host $newvolId $attachhostlocal   # > /dev/null
	fi
printf "%s \n" "detaching local coppy of the volume $volId "
mancala volumes detach-from-host $clonevolId $attachhostlocal  > /dev/null


printf "%s \n"  "  deleting the clone volume that was used for copying the data to the new volume"
symp -q -u admin -p $lpass -d cloud_admin -k -r default volume remove  $clonevolId >/dev/null 2>&1

printf "%s \n"  "   Done with copying data volume  $volId  $volName "
printf "%s \n"  "   Attaching volume  $volName to  $vmName "
	if [ $isremote = "remote" ]; then
		symp -u admin -p $rpass --url $remNb -d cloud_admin -k -r default -q vm volumes attach $newvmId $newvolId >/dev/null 2>&1
	    volattachstatus=$?
	else
		symp -u admin -p $lpass -d cloud_admin -k -r default -q vm volumes attach $newvmId $newvolId 
	    volattachstatus=$?
	fi

  if [ $volattachstatus = 0 ]; then
      printf "%s \n" "    volume  $volName was sucessfully attached to $vmId "
      else
	 printf  "%s \n"    "   volume $volId  $volName  was not attached to the $newvmId,  please check"
  fi

} 


for vol in $vols
    do
        if  [[ "$vol" =~ [^a-zA-Z0-9] ]]; then
            printf "%s \n"  "additioanl volumes: "
                       
            copydatavols $vol
		else
			printf "%s \n" " no more data volumes to copy"
        fi
    done

printf "%s \n" "  all done "
