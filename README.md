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

My script calls the script email_attachments.sh to create an email body with the raw log file as an attachment.  The
email_attachments.sh was not created by me, and was found online - original author unknown.

Note: The rclone config file save via the CLI is different to the one used in the FreeNAS GUI Cloud Sync Tasks, so its
safe to update this configuration file via "rclone config" without affecting anything you have configured
in the FreeNAS GUI.

Installation and setup walkthrough available on the FreeNAS Community Forums: https://www.ixsystems.com/community/resources/a-script-to-run-rclone-on-the-freenas-server-to-backup-nas-data-to-backblaze-b2-cloud-storage.123/

Change Log
----------
Update(1) The log file rclone produces is not user friendly, therefore this script will also create a more user
friendly log (to use as the email body).  This shows the stats, and for "sync" a list of files Copied (new),
Copied (replaced existing), and Deleted - as well as any errors/notices; for "cryptcheck" it only lists
errors or notices.

29-02-2020: I've noticed that since upgrading to FreeNAS v11.3 that this script was no longer working.  When
you create the "rclone.conf" file from a shell prompt (or SSH connection) with the command "rclone config"
it is stored at "/root/.config/rclone/rclone.conf" (you can check this by running the command "rclone config file").
However, when you then run this bash script as a cron task, for some reason it is looking for the config file at
"/.config/rclone/rclone.conf"; a quick fix was to copy the "rclone.conf" file to this folder.  However, it's not a
good idea to have multiple copies of the "rclone.conf" config file as this could become confusing when you make
changes.  Therefore I decided to update the script to utilise the "--config" parameter of rclone to point to the
config file created at "/root/.config/rclone/rclone.conf".  I did log this as a bug (NAS-105088), but it was closed
by IX as a script issue - however, I don't believe that is correct!

12-03-2020: I have updated the script to be dual purpose, with regard to running a "rclone sync" to backup, and
"rclone cryptcheck" to do a verification of your cloud based files and see if any files are missing as well as
confirming the checksums of all encrypted files (for the paranoid out there!).  You now need to run this script
with an parameter, for example: "rclonebackup.sh sync" or "rclonebackup.sh cryptcheck", any other parameters or
no parameter will result in an error email being sent.  As this reuses code dynamically it means that any
configuration changes in this script are only entered once and used for both sync and cryptcheck.
Further information about cryptcheck can be found at: https://rclone.org/commands/rclone_cryptcheck/

02-04-2020: I have updated it as follows:
* Tidied up the script;
* Separated out user and system defined variables (to make editing easier);
* Have moved from multiple "--exclude" statements to using "--exclude-from" and a separate file to hold excludes, which will make managing excludes much easier and saves editing this script.
* Have changed the default email to root.
* Have added in a third parameter option "check", which checks the files in the source and destination match.
* Rewrote the email generation aspect of the script to remove the need for the separate email_attachments.sh script - all managed within the one script now; as well as moving from "echo" to "printf" commands for more control.
