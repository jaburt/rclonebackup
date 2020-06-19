#!/bin/bash

### Notes ###
# Freenas (v11.1 onwards) now supports rclone natively and also has GUI entries for
# Cloudsync, however there is no/limited option(s) to use additional parameters within
# the GUI, thus I have adapted a script to be run instead via a cron job.  This script
# will send a formatted email upon execution, it also checks for a valid parameter value
# of "sync", "cryptcheck", or "check".
#
# "rclone sync": Make source and dest identical, modifying destination only.
# "rclone cryptcheck": Cryptcheck checks the integrity of a crypted remote.
# "rclone check": Checks the files in the source and destination match.
#
# You will need to configure rclone for Backblaze B2 as per: https://rclone.org/b2/
# If encrypting your data with rclone you need to also configure as per: https://rclone.org/crypt/
#
# Note(1): The rclone config file saved via the CLI is different to the one used in
# the FreeNAS GUI, so its safe to update this configuration file via "rclone config"
# without affecting anything you have configured in the FreeNAS GUI.
#
# Note (2): If you are not using Backblaze B2 but another cloud provider then this script
# *may* still work, but it depends on the specifics of that provider.  You would need to
# be aware of the following:
#	Check the configuration guide on https://rclone.org/ for your cloud provider;
#	You may need to adjust the "transfers" value;
#	You will need to delete the "--b2-hard-delete" line from the script;
#	You may need to remove the "--fast-list" line from the script;
#
# Script was adapted from the one posted in the FreeNAS community forums by Martin Aspeli:
#	https://www.ixsystems.com/community/threads/rclone-backblaze-b2-backup-solution-instead-of-crashplan.58423/
#
# The latest version of this script can be found at:
#	https://www.github.com/jaburt
#
# A discussion forum for this script can be found at:
# 	https://www.ixsystems.com/community/threads/a-script-to-run-rclone-on-the-freenas-server-to-backup-nas-data-to-backblaze-b2-cloud-storage.77575/
#
# This script has been checked for bugs with the online ShellCheck website:
#	https://www.shellcheck.net/
### End ###

### Change Log ###
# Update(1): The log file rclone produces is not user friendly, therefore this script
# will also create a more user friendly log (to use as the email body).  This shows the
# stats, and for "sync" a list of files Copied (new), Copied (replaced existing), and
# Deleted - as well as any Errors/Notices; for "cryptcheck" it only lists Errors or
# Notices.
#
# 29-02-2020: I've noticed that since upgrading to FreeNAS v11.3 that this script was
# no longer working.  When you create the "rclone.conf" file from a shell prompt (or
# SSH connection) with the command "rclone config" it is stored at "/root/.config/rclone/rclone.conf"
# (you can check this by running the command "rclone config file").  However, when you
# then run this bash script as a cron task, for some reason it is looking for the config
# file at "/.config/rclone/rclone.conf"; a quick fix was to copy the "rclone.conf" file
# to this folder.  However, it's not a good idea to have multiple copies of the "rclone.conf"
# config file as this could become confusing when you make changes.  Therefore I decided
# to update the script to utilise the "--config" parameter of rclone to point to the config
# file created at "/root/.config/rclone/rclone.conf".  I did log this as a bug (NAS-105088),
# but it was closed by IX as a script issue - however, I don't believe that is correct!
#
# 12-03-2020: I have updated the script to be dual purpose, with regard to running a
# "rclone sync" to backup, and "rclone cryptcheck" to do a verification of your cloud
# based files and see if any files are missing as well as confirming the checksums of
# all encrypted files (for the paranoid out there!).  You now need to run this script
# with a parameter, for example: "rclonebackup.sh sync" or "rclonebackup.sh cryptcheck",
# any other parameters or no parameter will result in an error email being sent.  As
# this reuses code dynamically it means that any configuration changes in this script
# are only entered once and used for both sync and cryptcheck.
# Further information about cryptcheck can be found at: https://rclone.org/commands/rclone_cryptcheck/
#
# 02-04-2020: I have updated it as follows:
#	* Tidied up the script;
#	* Separated out user and system defined variables (to make editing easier);
#	* Have moved from multiple "--exclude" statements to using "--exclude-from" and
#	  a separate file to hold excludes, which will make managing excludes much easier
#     and saves editing this script.
#	* Have changed the default email to root.
#	* Have added in a third parameter option "check", which checks that the files in
#	  the source and destination match.
#	* Rewrote the email generation aspect of the script to remove the need for the
#	  separate email_attachments.sh script - all managed within the single script now;
#	  as well as moving from "echo" to "printf" commands for more control.
#
# 15-06-2020: I have updated it as follows:
#	* Tidied up the script some more;
#	* Have added another option to compress (gzip) the log file before being attached
#	  to the email (compressLog="yes"), this is set to "yes" by default.
#	* You can also now request the script to keep a local copy (backup) of the unformatted
#	  log file (keepLog="no"), this is set to "no" by default, as well as how many logs to
#	  keep (amountBackups=31). Keeping the log was code I used to cut-n-paste in for my debugging,
#	  but deceided to leave it in as an option now.
#	* Have added in some checks that will verify that some of the user defined variables are valid.
#
# TODO:
#	* Add in an option to set your bandwidth limits for rclone.
### End ###

### Usage ###
# 1) Configure rclone
#	 First off you need to configure rclone for Backblaze B2 as per: https://rclone.org/b2/,
#	 and if encrypting your data with rclone you then need to configure as per: https://rclone.org/crypt/.
#
# 2) Download the exclude list and script
#	 Visit my Github page and download the latest script and rclone_excludes.txt,
#	 and save them on your server.
#
# 3) Edit "rclonebackup.sh" script and the "rclone_excludes.txt" file
#	 There are twelve user-defined fields within the script, however many can be left
#	 at their defaults (depending on how you configured rclone).  You will need to
#	 review the following three at a minimum:
#
#	 src=, dest=, exclude_list=
#
#	 however, if you wish to keep a local copy of the logs, you will also need to
#	 review the following three:
#
#	 keepLog=, backupDestination=, amountBackups=
#
#	 Review the "rclone_excludes.txt" file, and add/remove exclusions as per your
#	 requirements.
#
# 4) Setup a Tasks -> Cron Jobs on the FreeNAS server
#	 You now want to create a new cron job task via the FreeNAS GUI, remembering
#	 the command you want to run is the full path to the "rclonebackup.sh" script,
#	 with the parameter of sync, check or cryptcheck.
#
#	 I recommend that for the first time you run this, that you do not enable the
#	 task. This is because the first run could take some time, many days if you
#	 have a few TB to backup. You do not want the server starting a new task while
#	 the old one is still running, as this will only confuse the backup process
#	 and slow down your server.
#
# Basically this script is running the following command, and then creating a user-friendly log:
# rclone sync|cryptcheck|check --config=LOCATION --transfers 16 --fast-list --copy-links --min-age 15m --log-level NOTICE --log-file /tmp/jab_rclonelog.txt --b2-hard-delete --exclude-from EXCLUDES_FILE /mnt/tank secret:/
###

### User Defined Variables ###
# The top-level source folder/directory you wish to sync/check/cryptcheck with rclone.
src="/mnt/tank"

# The destination remote/bucket (as defined with your rclone config setup).
dest="secret:/"

# The path where you have saved the "rclone_excludes.txt" file (include the filename as well).
exclude_list="/mnt/tank/Sysadmin/scripts/rclone_excludes.txt"

# Do you want the logfile compressed with gzip before being added to the email? (yes/no)
compressLog="yes"

# Do you want to keep a copy (backup) of the unformatted log file?
keepLog="yes"

# Backup Destination.  The trailing slash is NOT needed. This is the absolute location
# within your FreeNAS server.
# IMPORTANT: Make sure you only use this directory for these logs, as the delete process
# deletes all files within the directory (no matter the name) and only keeps the latest
# "amountBackups" amount.
backupDestination="/mnt/tank/Sysadmin/rclone_logs"

# How many backups do you want to keep in the "backupDestination"?
amountBackups=31

# Your email address, so that you can receive the emails generated by this script.
# This defaults to 'root' and thus the email address you have defined for root, if
# you want a different email, please edit appropriately.
your_email=root

# Set the location of the "rclone.conf" file (as displayed with the command "rclone config file"),
# using the "--config=" parameter (currently set to default location).
cfg_file="/root/.config/rclone/rclone.conf"

# This sets the log level for rclone, using the "--log-level" parameter. The default log
# level is NOTICE.  I would recommend you use NOTICE for your first sync as it can take
# a while, and if you not careful it can produce a rather large log file.  Once you have
# completed your first sync, you can change to INFO for a more detailed log for future
# updates.
log_level="INFO"

# Only transfer files older than this in suffix ms|s|m|h|d|w|M|y (default off),
# using the "--min-age=" parameter.  A good way to skip open files.
min_age="15m"

# Number of file transfers to run in parallel (default 4) using the "--transfers"
# parameter. Backblaze recommends that you do lots of transfers simultaneously for
# maximum speed.  You will want to experience with this depending on your Internet
# connection speed.
transfers="16"
### End ###

### Notes about extra parameters ###
# I am also using the following extra parameters:
#
# Use recursive list if available, using the "--fast-list" parameter. Uses more memory
# but fewer transactions (i.e. cheaper). Backblaze B2 supports.
#
# Follow symlinks, using the "--copy-links" parameter, and copy the pointed to items.
#
# Log everything to a log file, using the "--log-file" parameter.
#
# Permanently delete files on remote removal, otherwise hide files, using the "--b2-hard-delete"
# parameter. This is a Backblaze B2 specific parameter.  This means no version control
# of files on backblaze (saves space & thus costs).
### End ###

#################################################################
##### THERE IS NO NEED TO EDIT ANYTHING BEYOUND THIS POINT  #####
##### UNLESS YOU ARE ADAPTING FOR A NONE BACKBLAZE B2 SETUP #####
#################################################################

### System/Script defined Variables ###
# To allow concurrent runs of this script, the log file need to have unique names,
# a way to do this is by using the Process ID (PID) of this script as it runs.
# This is found by using the special code $$.
pid=$$

# Location and name of the log file used by the script, it is deleted at the
# end of the script. However a copy is made if keepLog="yes".
log_file=$(date "+/tmp/jab_rclonelog_(%Y-%m-%d_%I-%M%p)-PID(${pid}).txt")

# Create a variable with the start date/time of script execution.
started="$(date "+rclonebackup.sh script started at: %Y-%m-%d %I:%M:%S")"

# Random'ish (see https://tools.ietf.org/html/rfc2046#section-5.1.1) boundary text.
boundary="ZZ_/afg6432dfgkl.94531q"

# A regex expression used to test that "amountBackups" is a numeric value.
numberTest="^[0-9]+$"
### End ###

### A short function to tidy-up after the rclone process has finished. ###
run_tidyup()
{
if [ "${1}" = "Valid" ] ; then
# Did we compress the log file? If "yes", update the log file name.
	if [ ${compressLog} = "yes" ] ; then
		log_file="${log_file}.gz"
	fi

# Are we keeping a local copy (backup) of the log file?
	if [ ${keepLog} = "yes" ] ; then
		cp "${log_file}" "${backupDestination}/"

# Delete old backups and only keep the newest "amountBackups"
# cd to the correct directory before executing (for the paranoid!)
		cd ${backupDestination} || exit
		ls -1t | tail -n +$((${amountBackups}+1)) | xargs rm -f
	fi
fi

# Delete the temporary rclone log, in preparation for a new set of files on the
# next run and to save space!
rm -f "${log_file}"
}
### End ###

### A function to report that an invalid parameter has been passed upon script execution.
run_invalid()
{
# Define the email text and send it.
	{
	printf '%s\n' "From: ${your_email}
To: ${your_email}
Subject: rclone - ERROR: ${1}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"${boundary}\"
--${boundary}
Content-Type: text/plain; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
"
	date "+${started} and finished at: %Y-%m-%d %H:%M:%S"
	printf '%s\n' "
An error has occured, please check the subject line and the usage notes below:

Either invalid parameters were provided to the \"rclonebackup.sh\" script, correct usage is:

---- To start a rclone sync use the parameter sync, i.e. \"rclonebackup.sh sync\"
---- To start a rclone check use the parameter check, i.e. \"rclonebackup.sh check\"
---- To start a rclone cryptcheck use the parameter cryptcheck, i.e. \"rclonebackup.sh cryptcheck\"

or, a user defined variable has failed its verfication check:

---- The rclone configuration file is not at the location referenced in the user defined variable <cfg_file>.
---- The backup source directory is not valid, as per the location referenced in the user defined variable <src>.
---- The location where you wish to save copies of the log file in is not valid, as per the location referenced in the user defined variable <backupDestination>. However, this is only checked if <keepLog=\"yes\">.
---- The amount of backup logs you wish to keep is not a valid integer value (or is zero), as per the number referenced in the user defined variable <amountBackups>. However, this is only checked if <keepLog=\"yes\">.

Also ensure you have saved the \"rclone_excludes.txt\" file and that is it correctly referenced in the variable <exclude_list>, as this is needed by the script. The file can be empty if you don't want to exclude files, however you could end up backing up files you do not need backed up (for example iocage).

------------------------------------------------------------------------------------------------------------------------------
Please Note: The latest version of this script can be found at: https://www.github.com/jaburt
------------------------------------------------------------------------------------------------------------------------------
"
	} | sendmail -t -oi
}
### End ###

### Run rclone ###
# A function which does the main work by calling rclone with all the configured
# parameters and then formatting the log.
run_rclone()
{
# Execute rclone as a sync or cryptcheck, based on $1 parameter
rclone "$1" \
	--config="${cfg_file}" \
	--transfers "${transfers}" \
	--fast-list \
	--copy-links \
	--min-age "${min_age}" \
	--log-level "${log_level}" \
	--log-file "${log_file}" \
	--b2-hard-delete \
	--exclude-from "${exclude_list}" \
	"${src}" "${dest}"
success=$?

# Set the email Subject.
if [[ ${success} != 0 ]] ; then
	subject="rclone: An error occurred with the rclonebackup.sh ${1}. Please check the logs. (exit code:${success})"
else
	subject="rclone: rclonebackup.sh ${1} succeeded"
fi

# Create a variable with the end date/time of script execution (no need to change this).
finished=$(date "+ and finished at: %Y-%m-%d %I:%M:%S")

# Create the email
	{
# Build the email headers.
	printf '%s\n' "From: ${your_email}
To: ${your_email}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"${boundary}\"
--${boundary}
Content-Type: text/plain; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
"

# Create the email body text, i.e. the edited and formatted log extract for a "sync" process.
	if [[ "${1}" = "sync" ]] ; then

# If rclone reported an error, reference the exit-code URL in the email.
		if [[ ${success} != 0 ]] ; then
			printf '%s\n' "(refer to https://rclone.org/docs/#exit-code for more information about exit codes)
			"
		fi

# Print out the stats
		printf '%s\n' "${started}${finished}

======================================
The stats for this rclone backup were:
======================================"
		tail -n6 "${log_file}"

# List of NEW files copied.
		printf '%s\n' "====================================
The following NEW files were copied:
===================================="
		grep ': Copied (new)' "${log_file}" | cut -c 29- | rev | cut -c 15- | rev | sort
		printf '%s\n' ""

# List of files REPLACED.
		printf '%s\n' "==================================================
The following files were REPLACED with new copies:
=================================================="
		grep ': Copied (replaced existing)' "${log_file}" | cut -c 29- | rev | cut -c 29- | rev | sort
		printf '%s\n' ""

# List of files DELETED.
			printf '%s\n' "=================================
The following files were DELETED:
================================="
		grep ': Deleted' "${log_file}" | cut -c 29- | rev | cut -c 10- | rev | sort
		printf '%s\n' ""

# List of any ERRORs or NOTICEs found.
		printf '%s\n' "============================================
The following ERRORs and NOTICEs were found:
============================================"
		grep 'ERROR :\|NOTICE:' "${log_file}" | cut -c 21-
		printf '%s\n' ""

	else

# Create the email body text, i.e. the edited and formatted log extract for a
# "check" or "cryptcheck" process.
# List of any ERRORs found.
		printf '%s\n' "${started}${finished}

================================
The following ERRORs were found:
================================"
		grep 'ERROR :' "${log_file}" | cut -c 21-
		printf '%s\n' ""

# List of any NOTICEs found.
		printf '%s\n' "=================================
The following NOTICEs were found:
================================="
		grep 'NOTICE:' "${log_file}" | cut -c 21-
		printf '%s\n' ""

	fi

# Add a footer to the email body.
	printf '%s\n' "

------------------------------------------------------------------------------------------------------------------------------
Please Note: The latest version of this script can be found at: https://www.github.com/jaburt
------------------------------------------------------------------------------------------------------------------------------
"

# Attach the log file (as an attachment).
	printf '%s\n' "--${boundary}
"

	if [ ${compressLog} = "yes" ] ; then
		printf "Content-Type: application/x-gzip
"
		gzip -9 "${log_file}"
		log_file="${log_file}.gz"
	else
		printf "Content-Type: text/plain
"
	fi

	printf '%s\n' "--${boundary}
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=\"$log_file\"
"

	base64 "${log_file}"
	printf '%s\n' ""

# Print final boundary with closing --
	printf '%s\n' "--${boundary}--"

	} | sendmail -t -oi
}
### End ###

### Execute Script ###
# Check the existence of the excludes file as well as the parameter passed upon
# script execution, also do some verification of the user defined variables; and
# then run the relevant bespoke functions (detailed above).

if [ ${#} -eq 0 ] ; then
# If no parameter was passed, exit with invalid email.
	run_invalid "No Parameter Provided!"
	run_tidyup "Invalid"
    exit 1
elif [[ ! ${1} =~ ^(sync|cryptcheck|check)$ ]] ; then
# If the parameter passed doesn't equal sync, cryptcheck or check, exit with invalid
# email.
	run_invalid "Incorrect Parameter ($1) Provided!"
	run_tidyup "Invalid"
	exit 1
elif [ ! -f "${exclude_list}" ] ; then
# If the "exclude_list" file is missing, exit with invalid email.
	run_invalid "The rclone exclude list (${exclude_list}) is missing!"
	run_tidyup "Invalid"
	exit 1
elif [ ! -f "${cfg_file}" ] ; then
# If the rclone configuration file, "cfg_file", file is missing, exit with invalid
# email.
	run_invalid "The rclone configuration file (${cfg_file}) is missing!"
	run_tidyup "Invalid"
	exit 1
elif [ ! -d "${src}" ] ; then
# If the backup source, "src," directory is missing, exit with invalid email.
	run_invalid "The backup source directory (${src}) is not valid!"
	run_tidyup "Invalid"
	exit 1
elif [ "${keepLog}" == "yes" ] && [ ! -d "${backupDestination}" ] ; then
# If the location of where the log files are backed up is invalid exit with invalid
# email (but only if keepLog="yes").
	run_invalid "The log backup directory (${backupDestination}) is not valid!"
	run_tidyup "Invalid"
	exit 1
elif [ "${keepLog}" == "yes" ] && [[ ! ${amountBackups} =~ $numberTest || ${amountBackups} -eq 0 ]] ; then
# If the value of the amount of backups to keep, "amountBackups", is not an integer or is
# zero, exit with invalid email (but only if keepLog="yes").
	run_invalid "The amount of log files to keep (${amountBackups}) is not a valid integer (or is zero)!"
	run_tidyup "Invalid"
	exit 1
else
# All OK, so run rclone now.
	run_rclone "$1"
	run_tidyup "Valid"
	exit ${success}
fi
### End ###
