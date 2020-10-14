#!/bin/bash
#
#########################################################################################
# Script to manage XEN backups based on tags, bjorn.carlsson@veriscan.se, bjorn@beze.se
# Rev: 2020-10-14 Initial beta version
#
# The script will backup vm:s based on a number of vm-tags set in XEN center:
# "daily", backup every day, save as date[yyyy-mm-dd]
# "weekly", backup every Saturday, save as date[yyyy-mm-dd]
# "monthly", backup first Sunday every month, save as date[yyyy-mm-dd]
# "archive", backup and save as [vm-name], backups are never overwritten
#
# vm-tags can be combined; If duplicate backups are detected, for example if a daily 
# backup is triggered at the same time as a monthly backup, the script will use the  
# duplicateBackupMethod setting to determine how to handle the situation.
#
# To exclude a disk from backup for any reason, add the tag "exclude_" followed by backup
# type. E.g. disk-tag "exclude_weekly" to the disk in XEN-center will exclude the disk 
# from weekly backups. PLEASE NOTE: This will not work for duplicate backups in case 
# defining any other "duplicateBackupMethod" setting that "newBackup". The first backup
# will otherwise will be used as source along with all disks included in that backup.
#########################################################################################

#########################################################################################
# Settings, modify to suite your needs...

xenPoolname="Pool01"

scriptLockFile="/var/backup/backup-fromtags.lock"
scriptLogFile="/var/backup/backup-fromtags.log"
scriptMailFile="/var/backup/backup-fromtags.mail"

# Always use dedicated backupDirs for each type of backup
backupDirDaily="/run/sr-mount/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxx/xen/vm-daily"
backupDirWeekly="/run/sr-mount/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxx/xen/vm-weekly"
backupDirMonthly="/run/sr-mount/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxx/xen/vm-monthly"
backupDirArchive="/run/sr-mount/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxx/xen/vm-archive"
backupDirMeta="/run/sr-mount/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxx/xen/vm-metadata"

# Cleanup nbr of days, backups older than these settings will be erased prior backup
cleanupBackupDirDaily="3"		# KEEP 4 DAILY BACKUPS, CURRENT AND 3 PREVIOUS
cleanupBackupDirWeekly="21"		# KEEP 3 WEEKS
cleanupBackupDirMonthly="93"	# KEEP 3 MONTHS
cleanupBackupDirArchive="false"	# No cleanup
cleanupBackupDirMeta="false"	# No cleanup

# Uncomment to control directory and file security options
backupDirPermissions="777"
backupFilePermissions="644"

# Set a method to use in case the same VM is targeted for several backups simultaneously,
# one VM backed gets up in two or more of the archive, monthly, weekly, or daily backups.
# Valid options are: "newBackup", "copyBackup", "textFile" or "symLink".
#
# Duplicates are evaluated in the order: 1. archive, 2. monthly, 3, weekly, 4 daily to 
# minimize the risk that original backup is replaced causing a textfile reference or a
# symLink to become invalid. PLEASE NOTE: Avoid the "symLink" option if using external 
# NFS filestores as symlinks will not be valid outside the Xen context.
duplicateBackupMethod="newBackup"

# Mailsettings
mailFrom="kxen01@mydomain.org"
mailTo="support@mydomain.org"
mailSubject="Xenbackup on $(hostname) is done"

# Uncomment to send email using this script instead of utilizing Xen native ssmtp. This
# makes it possible to use another mail gateway and port than configured in the Xen
# set-up. Please note that you may have to adjust the sendScriptMail function "expect"
# lines according to expected responces from your mail gateway.
#mailUseScript="true"
#mailServerIP="nnn.nnn.nnn.nnn"
#mailServerPort="587"

# Uncomment to set logSetting="extensive" for detailed logging and mail reports
#logSetting="extensive"

# Set a compressionSetting to enable compression; valid options are: "gzip" and "pigzee".
# Using the "pigzee" option will enable parallell processing gzip for super fast backups.
# PLEASE NOTE: For the pigzee-option to work you must first install pigz. e.g.:
# wget http://mirror.centos.org/centos/7/extras/x86_64/Packages/pigz-2.3.3-1.el7.centos.x86_64.rpm && rpm -ivh pigz-2.3.3-1.el7.centos.x86_64.rpm
compressionSetting="pigzee"

# Set backupHalted="true" to backup also halted vm:s
backupHalted="true"

#########################################################################################
# DO NOT EDIT BELOW THIS LINE !!!!!!
#########################################################################################
#########################################################################################
#########################################################################################
# FUNCTIONS

function backupVM
{
	# Variables already set when calling this function:
	# ${vmName}
	# ${vmUuid}
	# ${vmTags}
	# ${lastVmName} (Name of last backed up VM)

	# Start checking what to backup
	for vmTag in ${vmTags}; do
		case ${vmTag} in
		"archive")
			# Archive backups are checked every time
			exportDir="${backupDirArchive}/${vmName}"
			exportFile="${exportDir}/${vmName}.xva"
			# Run the backup only if the target file does not yet exist
			test ! -f "${exportFile}" && exportVM
		;;
		"monthly")
			# Run a monthly backup first sunday every month
			if [[ ${DoM} -lt 8 && ${DoW} == 7 ]]; then
				# Make a new backup if this VM is not already backed up, or if setting is to always make a new backup
				if [[ "${lastVmName}" != "${vmName}" || "${duplicateBackupMethod}" == "newBackup" ]]; then
					exportDir="${backupDirMonthly}/$(date +%Y-%m-%d)/${vmName}"
					exportFile="${exportDir}/${vmName}.xva"
					# Run the backup only if the target file does not yet exist
					test ! -f "${exportFile}" && exportVM
				else
					copyDir="${backupDirMonthly}/$(date +%Y-%m-%d)/${vmName}"
					copyFile="${copyDir}/${vmName}.xva"
					# Run the copy function only if the target file does not yet exist
					test ! -f "${copyFile}" && copyVM
				fi
			fi
		;;
		"weekly")
			# Run a weekly backup every saturday
			if [[ ${DoW} == 6 ]]; then
				# Make a new backup if this VM is not already backed up, or if setting is to always make a new backup
				if [[ "${lastVmName}" != "${vmName}" || "${duplicateBackupMethod}" == "newBackup" ]]; then
					exportDir="${backupDirWeekly}/$(date +%Y-%m-%d)/${vmName}"
					exportFile="${exportDir}/${vmName}.xva"
					# Run the backup only if the target file does not yet exist
					test ! -f "${exportFile}" && exportVM
				else
					copyDir="${backupDirWeekly}/$(date +%Y-%m-%d)/${vmName}"
					copyFile="${copyDir}/${vmName}.xva"
					# Run the copy function only if the target file does not yet exist
					test ! -f "${copyFile}" && copyVM
				fi
			fi
		;;
		"daily")
			# Make a new backup if this VM is not already backed up, or if setting is to always make a new backup
			if [[ "${lastVmName}" != "${vmName}" || "${duplicateBackupMethod}" == "newBackup" ]]; then
				exportDir="${backupDirDaily}/$(date +%Y-%m-%d)/${vmName}"
				exportFile="${exportDir}/${vmName}.xva"
				# Run the backup only if the target file does not yet exist
				test ! -f "${exportFile}" && exportVM
			else
				copyDir="${backupDirDaily}/$(date +%Y-%m-%d)/${vmName}"
				copyFile="${copyDir}/${vmName}.xva"
				# Run the copy function only if the target file does not yet exist
				test ! -f "${copyFile}" && copyVM
			fi
		;;
		esac
	done
	return 0
}

# Export a new fresh backup from a new snapshot!
function exportVM
{
	snapshName="backup_${vmTag}_${vmName}_$(date +%Y-%m-%d)"
	lastVmName="${vmName}"
	logStartVM
	logMessage "${vmName}: \"${vmTag}\" backup of uuid=${vmUuid} started using method \"vm-export\""
	extensiveLogMessage "${vmName}: Create snapshot \"${snapshName}\""
	snapshUuid=`xe vm-snapshot uuid=${vmUuid} new-name-label="${snapshName}"`
	extensiveLogMessage "${vmName}: Set snapshot parameters to allow export as a VM"
	xe template-param-set is-a-template=false ha-always-run=false uuid=$snapshUuid > /dev/null
	# Clear tags to exclude snapshot from also being backed up; this is only a snapshot copy, not the original VM!
	xe vm-param-clear uuid=${snapshUuid} param-name="tags" > /dev/null
	# Before exporting vm, check if any of the snapshots disks shall be excluded from the backup
	# First, get a list of all disks in the pool that shall be excluded in this backup type!
	excludeDiskUuids="$(xe vdi-list tags:contains=exclude_$vmTag params=snapshots  | cut -d":"  -f2  | sed -r 's/\;//g' | cut -d" " -f2-)"
	# Then, get a list of disks in the snapshot
	snapshDiskUuids="$(xe snapshot-disk-list uuid=$snapshUuid | grep "uuid" | awk '{print $NF}')"
	# Check disks in the snapshot one-by-one
	for snapshDiskUuid in ${snapshDiskUuids}; do
		# Check list of disks to exclude to see if current snapshot-disk is matched
		for excludeDiskUuid in ${excludeDiskUuids}; do
			if [[ ${excludeDiskUuid} == ${snapshDiskUuid} ]]; then
				# OK, now we've found a snapshot-disk that shall be excluded from this backup, so lets remove it!
				excludeName="$(xe vdi-list uuid=$snapshDiskUuid params=name-label | cut -d":"  -f2  | cut -d" " -f2-)"
				extensiveLogMessage "${vmName}: Excluding snapshot-disk \"${excludeName}\"; uuid=${snapshDiskUuid} from backup"
				xe vdi-destroy uuid=${snapshDiskUuid}
			fi
		done
	done
	# If the export directory does not yet exist, create it
	createDir "${exportDir}"
	# Check compression method and run vm-export
	test "${compressionSetting}" != "" && extensiveLogMessage "${vmName}: Export \"${snapshName}\" to \"${exportFile}\" using ${compressionSetting} compression"
	test "${compressionSetting}" == "" && extensiveLogMessage "${vmName}: Export \"${snapshName}\" to \"${exportFile}\""
	test "${compressionSetting}" == "pigzee" && xe vm-export vm=${snapshUuid} filename= | pigz -c >"${exportFile}"
	test "${compressionSetting}" == "gzip" && xe vm-export compress=true vm=${snapshUuid} filename="${exportFile}"
	test "${compressionSetting}" == "" && xe vm-export vm=${snapshUuid} filename="${exportFile}"
	# Remove temporary snapshot used for the backup
	extensiveLogMessage "${vmName}: Cleaning up, removing snapchot \"${snapshName}\" with uuid=${snapshUuid}"
	xe vm-uninstall uuid=${snapshUuid} force=true > /dev/null
	extensiveLogMessage "${vmName}: Removal of snapshot \"${snapshName}\" with uuid=${snapshUuid} completed"
	logMessage "${vmName}: \"${vmTag}\" backup completed"
	logEndVM
	# And since we actually backed up a VM, we also want to send a mail after script has completed
	sendMail="true"
	return 0
}

# We apperently already have a valid backup of another type, just use that one as a source!
function copyVM
{
	logStartVM
	logMessage "${vmName}: \"${vmTag}\" backup of uuid=${vmUuid} started using method backup-copy with option \"${duplicateBackupMethod}\""
	# If the target directory does not exist, create it
	createDir "${copyDir}"
	# Handle the duplicate backup according to settings
	case ${duplicateBackupMethod} in
	"symLink")
		extensiveLogMessage "${vmName}: Creating symbolic link from file: ${exportFile} to: ${copyFile}"
		ln -s "${exportFile}" "${copyFile}"
	;;
	"textFile")
		extensiveLogMessage "${vmName}: Creating text reference to file: ${exportFile} in: ${copyFile}"
		echo "${exportFile}" >"${copyFile}"
	;;
	"copyBackup")
		extensiveLogMessage "${vmName}: Copy source file: ${exportFile} to: ${copyFile}"
		\cp -rf "${exportFile}" "${copyFile}"
	;;
	esac
	logMessage "${vmName}: \"${vmTag}\" backup completed"
	logEndVM
	return 0
}

# Log entry preceeding backup
function startLog
{
	logMessage ""
	logMessage "------------------------------------------------------------------------------------"
	logMessage "------------------------------------------------------------------------------------"
	logMessage "VM Backup for XEN-Pool ${xenPoolname} STARTED at $(date +%Y-%m-%d_%H-%M-%S)"
	logMessage "------------------------------------------------------------------------------------"
}

# Trailing log entry after completed backup
function endLog
{
	logMessage "------------------------------------------------------------------------------------"
	logMessage "VM Backup ENDED at $(date +%Y-%m-%d_%H-%M-%S)"
	logMessage "------------------------------------------------------------------------------------"
	logMessage "------------------------------------------------------------------------------------"
}

# Log entry preceeding logging of each backuped VM
function logStartVM
{
	logMessage ""
	extensiveLogMessage "------------------------------------------------------------------------------------"
}

# Trailing log entry after each backuped VM
function logEndVM
{
	extensiveLogMessage "------------------------------------------------------------------------------------"
}

# Funktion used to write logentrys if extensive logging is enabled
function extensiveLogMessage
{
	# ${1}; the message
	test "${logSetting}" == "extensive" && logMessage "${1}"
}

# Main log function adding information to both filelog and maillog, and echo that to terminal
function logMessage
{
	# ${1}; the message
	`echo "[$(date +%Y-%m-%d_%H-%M-%S)] ${1}" >>"${scriptLogFile}"`
	`echo "[$(date +%Y-%m-%d_%H-%M-%S)] ${1}" >>"${scriptMailFile}"`
	echo "[$(date +%Y-%m-%d_%H-%M-%S)] ${1}"
}

# This function uses expect code to send email directly from this script instead of using 
# XEN mail settings.
function sendScriptMail
{
	/usr/bin/expect <(cat << EOF
#########################################################################################
# This is expect code, sent to the expect binary

# Timeout setting in case expected responce is not met
set timeout 60

#########################################################################################
# This spawns the telnet program and connects to the mailserver
spawn telnet $mailServerIP $mailServerPort

#########################################################################################
# Different mailservers responds differently, so you probably need to adjust according to
# your server. The expected server responses below are valid for a MS exchange 2019 server
# and SurgeMail Version 7.4.(Another approach would be to just wait for the "timeout" to 
# send each command...)

#expect ".com\r" #Verified with Surgemail using a .com domain
expect "00\r" #Verified with Exchange
send "HELO ${hostName}\r"

#expect ")\r" #Verified with Surgemail
expect "]\r" #Verified with Exchange
send "MAIL FROM: <${mailFrom}>\r"

expect "OK\r" #Verified with Surgemail & Exchange
send "RCPT TO: <${mailTo}>\r"

#expect "ok\r" #Verified with Surgemail
expect "OK\r" #Verified with Exchange
send "DATA\r"

expect "<CRLF>.<CRLF>\r" #Verified with Surgemail & Exchange
send "Content-Type: text/plain\rFrom: ${mailFrom}\rTo: ${mailTo}\rSubject: ${mailSubject}\r\r"
send -- "[read [open "${scriptMailFile}" r]]"

expect "\r" #Verified with Surgemail & Exchange
send "\r\r.\r"

#expect "ok\r" #Verified with Surgemail
expect "delivery\r" #Verified with Exchange
send "QUIT\r"

# Thats it folks, mail is sent!
#########################################################################################
EOF
)
}

function sendlLog
{
	if [[ "${sendMail}" = "true" && "${mailFrom}" != "" && "${mailTo}" != "" && "${mailSubject}" != "" ]]; then
		if [[ "${mailUseScript}" == "true" ]]; then
			hostName=$(hostname)
			sendScriptMail
		else
			mailBody="$(cat $scriptMailFile)"
			printf "From: <%s>\nTo: <%s>\nSubject: %s\n\n%s" "$mailFrom" "$mailTo" "$mailSubject" "$mailBody" | ssmtp "$mailTo"
		fi
	fi
}

function cleanUp
{
	# $1; directory to cleanup, $2; the number of days
	if [[ "$2" != "false" ]]; then
		find "$1" -mtime +"$(($2 - 1))" -type f  -delete
		find "$1" -depth -exec rmdir {} \; 2>/dev/nul
		logMessage "Cleaning up directory $1: Removing files older than $2 days!"
		createDir "$1"
	fi
}

function setPermissions
{
	# ${1}; directory to chmod
	test "${backupDirPermissions}" != "" && find "${1}" -type d -exec chmod "${backupDirPermissions}" {} +
	test "${backupFilePermissions}" != "" && find "${1}" -type f -exec chmod "${backupFilePermissions}" {} +
}

function createDir
{
	# ${1}; directory to create
	test ! -d "${1}" && mkdir -p "${1}"
	setPermissions "${1}"
}

function metaBackup
{
	extensiveLogMessage ""
	logMessage "------------------------------------------------------------------------------------"
	extensiveLogMessage "Make also a metadata backup of pool ${xenPoolname}"

	# If directory doesn't exist, create it
	createDir "${backupDirMeta}/$(date +%Y-%m-%d)/${xenPoolname}"
	# If target file exists, remove it
	test -f "${backupDirMeta}/$(date +%Y-%m-%d)/${xenPoolname}/xen-metadata.xml" && rm -f "${backupDirMeta}/$(date +%Y-%m-%d)/${xenPoolname}/xen-metadata.xml"
	xe pool-dump-database file-name="${backupDirMeta}/$(date +%Y-%m-%d)/${xenPoolname}/xen-metadata.xml"
	extensiveLogMessage "${xenPoolname}: XEN metadata backup saved as ${backupDirMeta}/$(date +%Y-%m-%d)/${xenPoolname}/xen-metadata.xml"
	logMessage "${xenPoolname}: Metadata backup completed"
}

#########################################################################################
#########################################################################################
#########################################################################################
# Script start

# The date when this script is kicked off
DoW=$(date +%u)
DoM=$(date +%d)

# Make sure days are interpreted as decimal
DoW=${DoW#0}
DoM=${DoM#0}

# Lets check if the script is already running, if so, just quit!
test -f "${scriptLockFile}" && exit

# Tell the world that the backup script is now running!
test ! -f "${scriptLockFile}" && touch "${scriptLockFile}"

# Lets remove previous mail message
test -f "${scriptMailFile}" && rm -f "${scriptMailFile}"

# Write script start to log
startLog

#########################################################################################
# If backup directories does not exist, create them
createDir "${backupDirDaily}"
createDir "${backupDirWeekly}"
createDir "${backupDirMonthly}"
createDir "${backupDirArchive}"
createDir "${backupDirMeta}"

#########################################################################################
# Cleanup backup directories based on settings:
cleanUp "${backupDirArchive}" "${cleanupBackupDirArchive}"
cleanUp "${backupDirMonthly}" "${cleanupBackupDirMonthly}"
cleanUp "${backupDirWeekly}" "${cleanupBackupDirWeekly}"
cleanUp "${backupDirDaily}" "${cleanupBackupDirDaily}"
cleanUp "${backupDirMeta}" "${cleanupBackupDirMeta}"

#########################################################################################
# Check what to backup
test "${backupHalted}" == "true" && vmlist="$(xe vm-list is-control-domain=false)"
test "${backupHalted}" != "true" && vmlist="$(xe vm-list power-state=running is-control-domain=false)"
vmUuids="$(echo "$vmlist" | grep "uuid" | awk '{print $NF}')"

#########################################################################################
# Log backup types relevant to run this session, e.g: archive, monthly, weekly and daily 
# backups
extensiveLogMessage ""
message="Running \"archive\""
# Monthly backup first sunday every month
test ${DoM} -lt 8 && test ${DoW} == 7 && message="${message}, \"monthly\""
# Weekly backup every saturday
test ${DoW} == 6 && message="${message}, \"weekly\""
# Always run daily backups
extensiveLogMessage "${message} and \"daily\" backups"

#########################################################################################
# Log detected vm_names and tags
for vmUuid in ${vmUuids}; do
	vmName=$(xe vm-param-get uuid=$vmUuid param-name=name-label)
	vmTags="$(xe vm-param-get uuid=$vmUuid param-name=tags | sed -r 's/\,//g')"
	test "${vmTags}" != "" && extensiveLogMessage "Detected tags \"${vmTags}\" for VM \"${vmName}\" with uuid=${vmUuid}"
done

#########################################################################################
# Do backups based on tags
logMessage ""
logMessage "Start running backups for relevant VMs and tags"
for vmUuid in ${vmUuids}; do
	vmName=$(xe vm-param-get uuid=$vmUuid param-name=name-label)
	vmTags="$(xe vm-param-get uuid=$vmUuid param-name=tags | sed -r 's/\,//g')"

	# Sort the tags according to expected lifetime: 1. archive, 2. monthly, 3, weekly, 4 daily
	declare pos_{1..4}=""
	for vmTag in ${vmTags}; do
		test "${vmTag}" == "archive" && pos_1="archive"
		test "${vmTag}" == "monthly" && pos_2="monthly"
		test "${vmTag}" == "weekly" && pos_3="weekly"
		test "${vmTag}" == "daily" && pos_4="daily"
	done
	vmTags="${pos_1} ${pos_2} ${pos_3} ${pos_4}"
	backupVM
done

#########################################################################################
# Make also a Xen metadata backup
metaBackup

#########################################################################################
# Set permissions according to settings
setPermissions "${backupDirDaily}"
setPermissions "${backupDirWeekly}"
setPermissions "${backupDirMonthly}"
setPermissions "${backupDirArchive}"
setPermissions "${backupDirMeta}"

extensiveLogMessage "Permissions on folders and files set according to settings: folder access=${backupDirPermissions} and file access=${backupFilePermissions}"

#########################################################################################
# End of script, finish log and send log via mail
endLog

# Remove lockfile to allow script to run again!
test -f "${scriptLockFile}" && rm -f "${scriptLockFile}"

# Send email with backup log
sendlLog
