# xen-backup-fromtags
A single script to manage XEN backups based on tags. The script will backup vm:s based on a number of vm-tags set in XEN center:
* "daily", backup every day, files are saved in directory named as date[yyyy-mm-dd]
* "weekly", backup every Saturday, files are saved in directory named as date[yyyy-mm-dd]
* "monthly", backup first Sunday every month, files are saved in directory named as date[yyyy-mm-dd]
* "archive", backup and save in directory named as [vm-name], backups are never overwritten

vm-tags can be combined; If duplicate backups are detected, for example if a daily 
backup is triggered at the same time as a monthly backup, the script will use the 
duplicateBackupMethod setting to determine how to handle the situation; in case the same VM is 
targeted for several backups simultaneously, one VM backed gets up in two or more of the archive, 
monthly, weekly, or daily backups. Valid options are: "newBackup", "copyBackup", "textFile" or "symLink".

Duplicates are evaluated in the order: 1. archive, 2. monthly, 3, weekly, 4 daily to 
minimize the risk that original backup is replaced causing a textfile reference or a
symLink to become invalid. PLEASE NOTE: Avoid the "symLink" option if using external 
NFS filestores as symlinks will not be valid outside the Xen context.

All VMs having valid names defined in XEN-center can be backed up, including names with spaces or special 
characters in names. The script includes a setting to to backup also halted VMs.

To exclude a disk from backup for any reason, add the tag "exclude_" followed by backup
type. E.g. disk-tag "exclude_weekly" to the disk in XEN-center will exclude the disk 
from weekly backups. PLEASE NOTE: This will not work for duplicate backups in case 
defining any other "duplicateBackupMethod" setting that "newBackup". The first backup
will otherwise will be used as source along with all disks included in that backup.

Different filestores may be defined for each type of backup using a valid path in the XEN-master and cleanup rules can 
be defined for each type of backup by specifying nbr of days. Default cleanup setting are:
* cleanupBackupDirDaily="3"		# KEEP 4 DAILY BACKUPS, CURRENT AND 3 PREVIOUS
* cleanupBackupDirWeekly="21"		# KEEP 3 WEEKS
* cleanupBackupDirMonthly="93"	# KEEP 3 MONTHS
* cleanupBackupDirArchive="false"	# No cleanup
* cleanupBackupDirMeta="false"	# No cleanup

Backups older than these settings will be erased prior backup...

Script includes logging functionality and if executed in terminal script will write to std-out letting you know whats going on. 
Logging can be set as "extensive" for detailed logging and mail reports. The script also includes a function to send email reports 
using other email settings than defined in XEN-center not utilizing Xen native ssmtp. This makes it possible to use another mail 
gateway and port than configured in the Xen-center set-up. Please note that you may have to adjust the sendScriptMail function "expect"
lines according to expected responces from your mail gateway.

The script also includes a setting to enable compression; valid options are: "gzip" and "pigzee". Using the "pigzee" option will enable 
parallell processing gzip for super fast backups. PLEASE NOTE: For the pigzee-option to work you must first install pigz. e.g.:
wget http://mirror.centos.org/centos/7/extras/x86_64/Packages/pigz-2.3.3-1.el7.centos.x86_64.rpm && rpm -ivh pigz-2.3.3-1.el7.centos.x86_64.rpm
