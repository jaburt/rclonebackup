# rclonebackup
A script to run rclone on the FreeNAS server to backup NAS data to Backblaze B2 cloud storage

FreeNAS: https://freenas.org/
rclone: https://rclone.org/

Script was adapted from the one posted in the FreeNAS community forums by Martin Aspeli:
https://www.ixsystems.com/community/threads/rclone-backblaze-b2-backup-solution-instead-of-crashplan.58423/

Why?
Freenas (v11.1 onwards) now supports rclone nativetly and also has GUI entries for Cloudsync, however 
there is no option to use additional parameters within the GUI, thus I have adapted a script to be 
run instead via a cron job.

You will need to configure rclone for Backblaze B2 as per: https://rclone.org/b2/ 
If encrypting your data with rclone you need to configure as per: https://rclone.org/crypt/

The log file rclone produces is not user friendly, therefore this script will also create a more user friendly
log (to use as the email body).  This shows the stats, and a list of files Copied (new), Copied (replaced existing),
and Deleted - as well as any errors/notices.

My script calles the script email_attachments.sh to create an email body with the raw log file as an attachment.  The
email_attachments.sh was not created by me, and was found online - original author unknown.

Note: The rclone config file save via the CLI is different to the one used in the FreeNAS GUI Cloud Sync Tasks, so its
safe to update this configuration file via "rclone config" without affecting anything you have configured
in the FreeNAS GUI.

Installation and setup walkthrough available on the FreeNAS Community Forums: https://www.ixsystems.com/community/resources/a-script-to-run-rclone-on-the-freenas-server-to-backup-nas-data-to-backblaze-b2-cloud-storage.123/
