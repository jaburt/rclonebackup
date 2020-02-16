#!/bin/bash

### Notes
# A script to run rclone on the FreeNAS server to backup my NAS data to Backblaze B2 cloud storage
#
# FreeNAS: https://freenas.org/
# rclone: https://rclone.org/
#
# Script was adapted from the one posted in the FreeNAS community forums by Martin Aspeli 
# https://www.ixsystems.com/community/threads/rclone-backblaze-b2-backup-solution-instead-of-crashplan.58423/
###

### Why?
# Freenas (v11.1 onwards) now supports rclone nativetly and also has GUI enteries for Cloudsync, however 
# there is no option to use additional parameters within the GUI, thus I have adapted a script to be 
# run instead via a cron job.
#
# You will need to configure rclone for Backblaze B2 as per: https://rclone.org/b2/ 
# If encrypting your data with rclone you need to configure as per: https://rclone.org/crypt/
#
# Note: The rclone config file save via the CLI is different to the one used in the FreeNAS GUI, so its
# safe to update this configuration file via "rclone config" without affecting anything you have configured
# in the FreeNAS GUI.
###

### Also
# The log file rclone produces is not user friendly, therefore this script will also create a more user friendly
# log (to use as email body).  This shows the stats, and a list of files Copied (new), Copied (replaced existing),
# and Deleted - as well as any errors/notices.
###

### What Parameters?
# I wish to use the following parameters:
#
# Number of file transfers to run in parallel. (default 4)  
# Backblaze recommends that you do lots of transfers simultaneously for maximum speed.  
# --transfers int
#
# Use recursive list if available. Uses more memory but fewer transactions (i.e. cheaper). Backblaze B2 supports.
# --fast-list
# 
# Follow symlinks and copy the pointed to item.
# --copy-links
#
# Only transfer files older than this in s or suffix ms|s|m|h|d|w|M|y (default off)
# --min-age 15m
#
# Log everything to a log file
# --log-file filename
#
# This sets the log level for rclone. The default log level is NOTICE.
# --log-level level
#
# Permanently delete files on remote removal, otherwise hide files. Backblaze B2 specific parameter. 
# Note: This means no version control of files on backblaze (saves space & thus costs)
# --b2-hard-delete
#
# Exclude files matching pattern (https://rclone.org/filtering/), make sure you put them within ""
# --exclude
# I wish to exclude: Thumbs.db, desktop.ini. AlbumArt*, .recycle, .windows, iocage (Jail files)
#
# For testing purposes only (i.e. don't actually sync files), so a trial run with no permanent changes
# --dry-run
###

###
# To verify your backup is fine and encrypted correctly you need to use rclone cryptcheck, don't forget to add in your
# exclusion though, or you will get errors about missing files. i.e.
#
# rclone cryptcheck --exclude "Thumbs.db" --exclude "desktop.ini" --exclude "AlbumArt*" --exclude ".recycle/**" --exclude ".windows" --exclude "iocage/**" /mnt/tank secret:/
#
# Further information at: https://rclone.org/commands/rclone_cryptcheck/
###

###
# In otherwords I'm running:
# rclone sync --transfers 16 --fast-list --copy-links --min-age 15m --log-level NOTICE --log-file /tmp/rclonelog.txt --b2-hard-delete --exclude "Thumbs.db" --exclude "desktop.ini" --exclude "AlbumArt*" --exclude ".recycle/**" --exclude ".windows" --exclude "iocage/**" /mnt/tank secret:/
###

### Define Parameters
src=/mnt/tank
dest=secret:/
email=your@email.address
log_file=/tmp/rclonelog.txt
log_level=INFO
log_file_formatted=/tmp/rclonelog_formatted.txt
min_age=15m
transfers=16
###

### Execute
# Record start date/time
started=$(date "+rclone backup started at: %Y-%m-%d %H:%M:%S")

# Start rclone
rclone sync \
	--transfers ${transfers} \
	--fast-list \
	--copy-links \
	--min-age ${min_age} \
	--log-level ${log_level} \
	--log-file ${log_file} \
	--b2-hard-delete \
	--exclude "Thumbs.db" \
	--exclude "desktop.ini" \
	--exclude "AlbumArt*" \
	--exclude ".recycle/**" \
	--exclude ".windows" \
	--exclude "iocage/**" \	
	${src} ${dest}
success=$?

# Record end date/time
finished=$(date "+ and finished at: %Y-%m-%d %H:%M:%S")
###

### Create the email
# Set the email Subject
if [[ $success != 0 ]]; then
	subject="rclone backup: An error occurred. Please check the logs. (exit code:${success})"
else
	subject="rclone backup: Backup succeeded"
fi

# Create the email body text, i.e. the edited and formatted log extract
# Create header
(
	if [[ $success != 0 ]]; then
		echo "(refer to https://rclone.org/docs/#exit-code for more information about exit codes)"
		echo ""
	fi
	echo "${started}${finished}"
	echo ""
	echo "======================================"
	echo "The stats for this rclone backup were:"
	echo "======================================"
	tail -n6 "${log_file}"
	echo ""
) > "${log_file_formatted}"

# List of NEW files copied
(
	echo "===================================="
	echo "The following NEW files were copied:"
	echo "===================================="
	grep ': Copied (new)' "${log_file}" | cut -c 29- | rev | cut -c 15- | rev | sort
	echo ""
) >> "${log_file_formatted}"

# List of files REPLACED
(
	echo "=================================================="
	echo "The following files were REPLACED with new copies:"
	echo "=================================================="
	grep ': Copied (replaced existing)' "${log_file}" | cut -c 29- | rev | cut -c 29- | rev | sort
	echo ""
) >> "${log_file_formatted}"

# List of files DELETED
(
	echo "================================="
	echo "The following files were DELETED:"
	echo "================================="
	grep ': Deleted' "${log_file}" | cut -c 29- | rev | cut -c 10- | rev | sort
	echo ""
) >> "${log_file_formatted}"

# List of any ERRORs or NOTICEs found
(
	echo "============================================"
	echo "The following ERRORs and NOTICEs were found:"
	echo "============================================"
	grep 'ERROR :\|NOTICE:' "${log_file}" | cut -c 21-
) >> "${log_file_formatted}"
###

### send the email using the email_attachments.sh script
/mnt/tank/Sysadmin/scripts/email_attachments.sh "${email}" "${email}" "${subject}" "$(cat $log_file_formatted)" "${log_file}"
###

### Tidy Up ###
## Delete the rclone log along with the edited and formatted log extract, in preparation of a new log
rm "${log_file}"
rm "${log_file_formatted}"
### End ###
