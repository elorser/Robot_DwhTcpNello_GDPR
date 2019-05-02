#!/bin/ksh
usage()
{
   echo 
   echo
   echo "Script usage options.."
   echo "1) #Run a datastage job#"
   echo "   Usage: $0 -start script_properties_file"
   echo "2) #Stop currently running datastage job#"
   echo "   Usage: $0 -stop script_properties_file"
   echo "3) #Retrieve log details of latest job#"
   echo "   Usage: $0 -lognewest script_properties_file"
   echo
   echo
}

checkfolder()
{
    # If folder does not exist or is not writable, print an error message and exit with given status
 exitstatus=$1
    folder=$2
    if [ ! -d "$folder" ]; then
      echo "ERROR: $folder cannot be found"
      exit $exitstatus
    fi

    if [ ! -w "$folder" ]; then
      echo "ERROR: $folder does not have write permission"
      exit $exitstatus
    fi
}

sendmail()
{
    # If email id is not blank then send mail content to the recepient address
    email_id=$1
    subject=$2
    mailfile=$3
    if [ -n "$email_id" ]; then
        echo "Sending mail to $email_id"
        mail -s "$subject" "$email_id" < "$mailfile"
    fi
}

checkdsjobreturncode()
{
    jobcode=$1
    # Decodifica del codice di ritorno
    case $jobcode in
          0) dsjobretdes="Job is actually running" ;;
	  1) dsjobretdes="Job finished a normal run with no warnings" ;;
	  2) dsjobretdes="Job finished a normal run with warnings" ;;
	  3) dsjobretdes="Job finished a normal run with a fatal error" ;;
	  4) dsjobretdes="Job queued waiting for resource allocation" ;;
	 11) dsjobretdes="Job finished a validation run with no warnings" ;;
	 12) dsjobretdes="Job finished a validation run with warnings" ;;
	 13) dsjobretdes="Job failed a validation run" ;;
	 21) dsjobretdes="Job finished a reset run" ;;
	 96) dsjobretdes="Job has crashed" ;;
	 97) dsjobretdes="Job was stopped by operator intervention" ;;
	 98) dsjobretdes="Job has not been compiled" ;;
	 99) dsjobretdes="Any other status" ;;
	255) dsjobretdes="The inactivity time out setting in DS Administrator is too low - Client connection is closed" ;;
	  *) dsjobretdes="Unknown error code" ;
    esac
    echo $dsjobretdes
}	

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

action=$1

# Absolute path to this file
propertiesfile=$( cd -P -- "$(dirname -- "$(command -v -- "$2")")" && pwd -P )
propertiesfile=$propertiesfile'/'$2
echo "Porperties File: "$propertiesfile | tee "$logfilename"

if [ ! -f "$propertiesfile" ]; then
    echo "Porperties file '$2' does not exists! Verify the correct directory" | tee "$logfilename"
    usage
    exit 1
fi

# Loading of properties file
. $propertiesfile

# Checks on datastage engine environment
if [ ! -n "$dsengine_env" ]; then
   echo "Please assign the datastage environment to 'dsengine_env' parameter in $propertiesfile file" | tee "$logfilename"
fi

if [ ! -f "$dsengine_env" ]; then
    echo "The dsenv profile cannot be found. Please assign the correct path to 'dsengine_env' parameter in $propertiesfile file" | tee "$logfilename"
    exit 1
fi

# Check on parameters valorization
if [ ! -n "$datastageproj" ]; then
    echo "Please assign the datastage project name to 'datastageproj' parameter in $propertiesfile file" | tee "$logfilename"
    exit 1
fi

if [ ! -n "$datastagejob" ]; then
    echo "Please assign the datastage job name to 'datastagejob' parameter in $propertiesfile file" | tee "$logfilename"
    exit 1
fi

if [ ! -n "$outputfolder" ]; then
    echo "Please specify folder name in 'outputfolder' parameter in $propertiesfile file for logging job run information" | tee "$logfilename"
    exit 1
fi

# If output folder does not exist, it is created
if [ ! -e "$outputfolder" ]; then
    mkdir -p "$outputfolder"
    # Fix read and write permission on outputfolder
    chmod 766 $outputfolder
fi

# Check on outputfolder 
checkfolder 1 $outputfolder

# Define  mailfile
mailfile="$outputfolder/dstagemail_`date "+%Y%m%d-%H.%M"`.log"
touch $mailfile

# Define log file
logfilename="$outputfolder"/"dslastrun_`date "+%Y%m%d-%H.%M"`.log"
touch $logfilename

# Initialization of allparam parameters list
allparam=""

# Loading of the datastage environment
. $dsengine_env

if [ "$action" = "-start" ]; then
    # Get all the parameters into allparam
    #for (( i=1 ; i<=$paramcount ; i++ ))
    i=1
    while [ $i -le $paramcount ];
    do
       param=$(eval echo $(eval echo '\$\{param$i\}'))
       valueforparam=$(eval echo $(eval echo '\$\{valueforparam$i\}'))
       if [ ! -n "$param" ] || [ ! -n "$valueforparam" ]; then
	    echo "Please make sure all parameters from param1 to param"$paramcount" and valueforparam1 to valueforparam"$paramcount" are assigned proper values in "$propertiesfile" file" | tee "$logfilename"
          exit 1
       fi
       ((i+=1))
       allparam="$allparam -param $param=$valueforparam "
       echo $allparam | tee "$logfilename"
    done
fi

#Job Status      : RUNNING (0) ;* This is the only status that means the job is actually running
#Job Status      : RUN OK (1) ;* Job finished a normal run with no warnings
#Job Status      : RUN with WARNINGS (2) ;* Job finished a normal run with warnings
#Job Status      : RUN FAILED (3) ;* Job finished a normal run with a fatal error

/*
echo "Checking status of previous execution for job $datastagejob" | tee "$logfilename"
jresult=`$DSHOME/bin/dsjob -jobinfo $datastageproj $datastagejob 2>>"$logfilename"` 
echo jresult | tee "$logfilename"

# If project name or job name is invalid then dsjob command will fail
if [ $? -ne 0 ]; then
    echo "Unable to get job information for job $datastagejob" | tee "$logfilename" 
    echo "Please check $logfilename for more information." > "$mailfile" | tee "$logfilename"
    sendmail "$email" "Unable to get job information" "$mailfile"
    exit
fi

# dsjob command was successfull and we can now extract Job Status from jresult
jstatus=`echo $jresult | head -1 | cut -d"(" -f2 | cut -d")" -f1`
if [ "$jstatus" = "0" ]; then
    if [ "$action" = "-stop" ]; then
       echo "Stopping job $datastagejob.." >> "$logfilename"
       # Please note that only a stop job command without wait option is issued and so the control returns immediately
       $DSHOME/bin/dsjob -stop $datastageproj $datastagejob 1>>"$logfilename" 2>&1
    else
       echo "The job $datastagejob is already running. Please wait until it completes" 
    fi
    echo "exiting"
    exit
fi
*/

echo "Starting job $datastagejob.." | tee "$logfilename"
$DSHOME/bin/dsjob -run -mode NORMAL -warn 0 -jobstatus $allparam $datastageproj $datastagejob 1>>"$logfilename" 2>&1
dsjobreturn=$?
# Read the description of return code from dsjob
returndes=$(checkdsjobreturncode $dsjobreturn)
echo "$returndes" | tee "$logfilename"


# Print the job status at the end of the run
case $dsjobreturn in
    1) echo "Job finished successfully - return code $dsjobreturn: $returndes" | tee "$logfilename";;
    2) echo "Job finished successfully - return code $dsjobreturn: $returndes" | tee "$logfilename";;
    *) echo "Job finished unsuccessfully - return code $dsjobreturn: $returndes" | tee "$logfilename"
       echo "Please check $logfilename for more information." | tee "$mailfile";;
esac

